import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import SwiftData

@Observable
final class FirebaseSharingManager {
    static let shared = FirebaseSharingManager()
    private var _db: Firestore?
    private var db: Firestore {
        if _db == nil { _db = Firestore.firestore() }
        return _db!
    }
    private(set) var currentUserId: String?

    private init() {}

    /// Returns the Member the current user has claimed in this group, if any.
    func claimedMember(in group: Group) -> Member? {
        guard let uid = currentUserId else { return nil }
        return group.members.first { $0.claimedByUid == uid }
    }

    /// Claim a member identity. Pushes to Firestore immediately if group is already shared;
    /// otherwise the claim is applied locally and will be uploaded when the group is shared.
    @MainActor
    func claimMember(_ member: Member, in group: Group, modelContext: ModelContext) async throws {
        try await signInAnonymously()
        guard let uid = currentUserId else { throw SharingError.notAuthenticated }
        member.claimedByUid = uid
        try? modelContext.save()
        if group.isShared {
            try? await pushMemberClaim(member, uid: uid, in: group)
            await logActivity(for: group, action: .joinedGroup, target: member.name)
        }
    }

    /// True if the given member is claimed by someone other than the current user.
    func isClaimedByOther(_ member: Member) -> Bool {
        guard let claim = member.claimedByUid else { return false }
        return claim != currentUserId
    }

    // MARK: - Auth

    func signInAnonymously() async throws {
        guard FirebaseApp.app() != nil else { return }
        if let user = Auth.auth().currentUser {
            currentUserId = user.uid
            return
        }
        let result = try await Auth.auth().signInAnonymously()
        currentUserId = result.user.uid
    }

    // MARK: - Invite Code

    func generateCode() -> String {
        let charset = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in charset[Int.random(in: 0..<charset.count)] })
    }

    /// Creates invite code for a group. Uploads group data to Firestore if not already shared.
    /// Returns the 6-char invite code.
    func createInviteCode(for group: Group) async throws -> String {
        try await signInAnonymously()
        guard let userId = currentUserId else { throw SharingError.notAuthenticated }

        // 已分享過就直接回傳邀請碼，不重推資料——花費平時已由 pushExpense 逐筆同步，
        // 這裡整包重推反而會把「本機尚未收到的較新遠端編輯」蓋回舊值。
        if let existingCode = group.inviteCode, group.firestoreGroupId != nil {
            return existingCode
        }

        // 產生不重複的邀請碼：碰撞極罕見，仍檢查避免劫持既有碼（配合 rules update:false 雙保險）
        var code = generateCode()
        for _ in 0..<5 {
            let existing = try? await db.collection("inviteCodes").document(code).getDocument()
            if existing?.exists != true { break }
            code = generateCode()
        }

        let groupData = serializeGroup(group, ownerId: userId, inviteCode: code)
        // 原子寫入 group 文件 + 邀請碼，任一失敗都不留孤兒文件
        let docRef = db.collection("groups").document()
        let batch = db.batch()
        batch.setData(groupData, forDocument: docRef)
        batch.setData([
            "groupId": docRef.documentID,
            "groupName": group.name,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("inviteCodes").document(code))
        try await batch.commit()

        await MainActor.run {
            group.firestoreGroupId = docRef.documentID
            group.firebaseOwnerId = userId
            group.inviteCode = code
        }

        await logActivity(for: group, action: .sharedGroup, target: group.name)
        return code
    }

    /// Joins a shared group using a 6-character invite code.
    func joinByInviteCode(_ code: String, modelContext: ModelContext) async throws {
        try await signInAnonymously()

        let upperCode = code.uppercased()

        let codeDoc = try await db.collection("inviteCodes").document(upperCode).getDocument()
        guard codeDoc.exists, let data = codeDoc.data(),
              let groupId = data["groupId"] as? String else {
            throw SharingError.inviteCodeNotFound
        }

        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        guard groupDoc.exists, let groupData = groupDoc.data() else {
            throw SharingError.groupNotFound
        }

        let localGroupIdStr = groupData["localGroupId"] as? String ?? ""
        if let localUUID = UUID(uuidString: localGroupIdStr) {
            let descriptor = FetchDescriptor<Group>(predicate: #Predicate { $0.id == localUUID })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.firestoreGroupId = groupId
                existing.firebaseOwnerId = groupData["ownerId"] as? String
                existing.inviteCode = upperCode
                try modelContext.save()
                return
            }
        }

        let group = try deserializeGroup(from: groupData, firestoreId: groupId, inviteCode: upperCode)
        modelContext.insert(group)
        for member in group.members { modelContext.insert(member) }
        for expense in group.expenses {
            modelContext.insert(expense)
            for split in expense.splits { modelContext.insert(split) }
        }
        try modelContext.save()
    }

    // MARK: - Sync

    /// 整批推送（雙寫過渡）：僅用於「全部花費都變」的情境（初次分享、換基準幣）。
    /// 日常單筆編輯請改用 `pushExpense` 以避免併發互蓋。
    /// 同時寫 group 文件（meta+members+舊 expenses[] 陣列，給舊版 client）與每筆 expenses 子文件。
    func pushChanges(for group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        guard let userId = currentUserId else { return }

        let data = serializeGroup(group, ownerId: group.firebaseOwnerId ?? userId, inviteCode: group.inviteCode ?? "")
        let groupRef = db.collection("groups").document(firestoreId)

        let batch = db.batch()
        batch.setData(data, forDocument: groupRef)
        for expense in group.expenses {
            let ref = groupRef.collection("expenses").document(expense.id.uuidString)
            batch.setData(serializeExpense(expense), forDocument: ref)
        }
        try await batch.commit()
    }

    /// Granular 推送（主要路徑）：只寫「這一筆」花費到子集合（權威、per-doc last-write-wins），
    /// 並用 transaction 把這一筆鏡像回舊 expenses[] 陣列（給尚未升級的舊版 client 讀）。
    /// 避免 `pushChanges` 每次推全部所造成的併發互蓋。
    func pushExpense(_ expense: Expense, in group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()

        let expenseId = expense.id.uuidString
        let expenseData = serializeExpense(expense)
        let groupRef = db.collection("groups").document(firestoreId)

        // 1) 子集合文件（權威來源）
        try await groupRef.collection("expenses").document(expenseId).setData(expenseData)

        // 2) 鏡像回舊陣列（最佳努力）：transaction 只替換/插入這一筆，不誤刪其他併發寫入
        _ = try? await db.runTransaction { (txn, errorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(groupRef)
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }
            guard snap.exists else { return nil }
            var arr = (snap.data()?["expenses"] as? [[String: Any]]) ?? []
            if let idx = arr.firstIndex(where: { ($0["id"] as? String) == expenseId }) {
                arr[idx] = expenseData
            } else {
                arr.append(expenseData)
            }
            txn.updateData(["expenses": arr], forDocument: groupRef)
            return nil
        }
    }

    /// 惰性遷移：若共享群組的 expenses 子集合尚為空、但舊 expenses[] 陣列有資料，
    /// 將每筆陣列花費補寫進子集合（doc id = expense.id，冪等可重入）。首次讀取時呼叫。
    func backfillExpensesSubcollectionIfNeeded(for group: Group) async {
        guard let firestoreId = group.firestoreGroupId else { return }
        try? await signInAnonymously()
        let groupRef = db.collection("groups").document(firestoreId)
        do {
            let existing = try await groupRef.collection("expenses").limit(to: 1).getDocuments()
            guard existing.documents.isEmpty else { return } // 已有子集合資料 → 視為已遷移
            let snap = try await groupRef.getDocument()
            guard let arr = snap.data()?["expenses"] as? [[String: Any]], !arr.isEmpty else { return }
            let batch = db.batch()
            for eData in arr {
                guard let id = eData["id"] as? String else { continue }
                batch.setData(eData, forDocument: groupRef.collection("expenses").document(id))
            }
            try await batch.commit()
        } catch {
            // 非關鍵；下次讀取再試
        }
    }

    /// 只推送 group 文件層級欄位（名稱/結算/基準幣/成員），用 updateData 不觸碰 expenses
    /// （陣列與子集合都不動），避免成員/結算等變動順手重寫花費而 clobber 併發編輯。
    func pushGroupMeta(for group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        let members = group.members.map { member -> [String: Any] in
            var m: [String: Any] = ["id": member.id.uuidString, "name": member.name]
            if let uid = member.claimedByUid { m["claimedByUid"] = uid }
            return m
        }
        try await db.collection("groups").document(firestoreId).updateData([
            "name": group.name,
            "isSettled": group.isSettled,
            "baseCurrencyCode": group.baseCurrencyCode,
            "members": members
        ])
    }

    /// 永久移除花費：rules 禁止 client 硬刪文件（防惡意刪庫），改寫 isPurged 墓碑——
    /// 新版 client 合併時看到即刪本地且永不重建；同時從舊陣列鏡像移除。
    /// 已知限制：尚未更新的舊版 client 看不懂墓碑，若之後重推該筆會使其復活
    /// （再刪一次即可；等大家更新後自然收斂）。
    func purgeExpense(expenseId: String, groupFirestoreId: String) async {
        guard FirebaseApp.app() != nil else { return }
        try? await signInAnonymously()
        let groupRef = db.collection("groups").document(groupFirestoreId)
        // setData(merge:) 而非 updateData：尚未惰性遷移的花費沒有子集合文件，merge 可一併建立墓碑
        try? await groupRef.collection("expenses").document(expenseId)
            .setData(["id": expenseId, "isPurged": true, "isDeleted": true], merge: true)
        _ = try? await db.runTransaction { txn, _ in
            guard let snap = try? txn.getDocument(groupRef),
                  var expenses = snap.data()?["expenses"] as? [[String: Any]] else { return nil }
            expenses.removeAll { ($0["id"] as? String) == expenseId }
            txn.updateData(["expenses": expenses], forDocument: groupRef)
            return nil
        }
    }

    /// 只推送 name/isSettled/baseCurrencyCode，完全不碰 members 陣列——
    /// 給「成員沒變」的路徑（列表結清/改名）用，避免整包覆寫洗掉併發的認領/新成員。
    func pushGroupScalars(for group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        try await db.collection("groups").document(firestoreId).updateData([
            "name": group.name,
            "isSettled": group.isSettled,
            "baseCurrencyCode": group.baseCurrencyCode
        ])
    }

    /// 原子認領成員：用 transaction 只改「這一位」成員的 claimedByUid，避免兩人同時認領
    /// 不同成員時整個 members 陣列覆寫互蓋。找不到該成員時 upsert（支援「新增成員後即認領」）。
    func pushMemberClaim(_ member: Member, uid: String, in group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        let memberIdStr = member.id.uuidString
        let name = member.name
        let groupRef = db.collection("groups").document(firestoreId)

        _ = try await db.runTransaction { (txn, errorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(groupRef)
            } catch let err as NSError {
                errorPointer?.pointee = err
                return nil
            }
            guard snap.exists else { return nil }
            var members = (snap.data()?["members"] as? [[String: Any]]) ?? []
            if let idx = members.firstIndex(where: { ($0["id"] as? String) == memberIdStr }) {
                members[idx]["claimedByUid"] = uid
            } else {
                members.append(["id": memberIdStr, "name": name, "claimedByUid": uid])
            }
            txn.updateData(["members": members], forDocument: groupRef)
            return nil
        }
    }

    /// One-shot pull（雙讀：group 文件 + expenses 子集合）into local SwiftData.
    func pullChanges(for group: Group, modelContext: ModelContext) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        let groupRef = db.collection("groups").document(firestoreId)

        // Force server fetch to bypass potentially stale cache
        let doc = try await groupRef.getDocument(source: .server)
        guard doc.exists, let data = doc.data() else {
            throw SharingError.groupNotFound
        }
        // 子集合抓不到就讓整個 pull 失敗（caller 顯示錯誤、可重試），
        // 不能只用舊陣列合併——鏡像可能落後，會把較新的編輯退回舊值。
        let subSnap = try await groupRef.collection("expenses").getDocuments(source: .server)
        let subDocs = subSnap.documents.map { $0.data() }

        await MainActor.run {
            mergeGroupMeta(data, into: group, modelContext: modelContext)
            let unified = unifiedExpenses(
                subcollection: subDocs,
                legacyArray: data["expenses"] as? [[String: Any]] ?? []
            )
            mergeExpenses(unified, into: group, modelContext: modelContext)
            try? modelContext.save()
        }
        await backfillExpensesSubcollectionIfNeeded(for: group)
    }

    /// Starts a real-time snapshot listener that merges remote changes into local SwiftData.
    @MainActor
    func listenToChanges(for group: Group, modelContext: ModelContext) -> SharingSubscription? {
        guard let firestoreId = group.firestoreGroupId else { return nil }
        let groupRef = db.collection("groups").document(firestoreId)

        // 一次性惰性遷移：把舊陣列補進子集合，讓其他新版 client 也能改用子集合
        Task { await self.backfillExpensesSubcollectionIfNeeded(for: group) }

        // 雙讀：group 文件（meta+members+舊陣列）與 expenses 子集合各一個 listener；
        // 任一變動就以「子集合為權威、舊陣列補漏」重新合併進 SwiftData。
        let state = SyncState()
        let apply: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if let gdata = state.groupData {
                self.mergeGroupMeta(gdata, into: group, modelContext: modelContext)
            }
            // 子集合快照未到前不合併花費：此時只有舊陣列（鏡像為盡力寫入，可能落後），
            // 先合併會把較新的編輯暫時退回舊值；等權威的子集合快照到齊再一起合併。
            guard let subDocs = state.subDocs else {
                try? modelContext.save()
                return
            }
            let unified = self.unifiedExpenses(
                subcollection: subDocs,
                legacyArray: state.groupData?["expenses"] as? [[String: Any]] ?? []
            )
            self.mergeExpenses(unified, into: group, modelContext: modelContext)
            try? modelContext.save()
        }

        // Skip local echoes — our own optimistic writes would re-enter merge and
        // fight SwiftUI list animations, causing UICollectionView batch-update crashes.
        let groupReg = groupRef.addSnapshotListener(includeMetadataChanges: false) { snapshot, _ in
            guard let snapshot, snapshot.exists, let data = snapshot.data() else { return }
            if snapshot.metadata.hasPendingWrites { return }
            Task { @MainActor in state.groupData = data; apply() }
        }
        let subReg = groupRef.collection("expenses")
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, _ in
                guard let snapshot else { return }
                if snapshot.metadata.hasPendingWrites { return }
                let docs = snapshot.documents.map { $0.data() }
                Task { @MainActor in state.subDocs = docs; apply() }
            }
        return SharingSubscription { groupReg.remove(); subReg.remove() }
    }

    /// 合併 group 文件層級資料：名稱、結算狀態、基準幣、成員。（expenses 改由 mergeExpenses 處理）
    @MainActor
    private func mergeGroupMeta(_ data: [String: Any], into group: Group, modelContext: ModelContext) {
        group.name = data["name"] as? String ?? group.name
        group.isSettled = data["isSettled"] as? Bool ?? group.isSettled
        if let remoteBase = data["baseCurrencyCode"] as? String, group.baseCurrencyCode != remoteBase {
            group.baseCurrencyCode = remoteBase
        }

        // Merge members (add new, update existing, remove unreferenced locals)
        var remoteMemberIDs: Set<UUID> = []
        if let membersData = data["members"] as? [[String: Any]] {
            for mData in membersData {
                guard let idStr = mData["id"] as? String, let uuid = UUID(uuidString: idStr),
                      let name = mData["name"] as? String else { continue }
                remoteMemberIDs.insert(uuid)
                let claim = mData["claimedByUid"] as? String
                if let existing = group.members.first(where: { $0.id == uuid }) {
                    existing.name = name
                    existing.claimedByUid = claim
                } else {
                    let member = Member(name: name)
                    member.id = uuid
                    member.claimedByUid = claim
                    modelContext.insert(member)
                    group.members.append(member)
                }
            }
            let orphaned = group.members.filter { !remoteMemberIDs.contains($0.id) }
            for member in orphaned {
                let stillReferenced = group.expenses.contains { expense in
                    expense.paidBy == member || expense.splits.contains { $0.member == member }
                }
                if !stillReferenced {
                    group.members.removeAll { $0.id == member.id }
                    modelContext.delete(member)
                }
            }
        }
    }

    /// 雙讀統一：子集合為權威來源，舊 expenses[] 陣列補上子集合沒有的項目
    /// （如舊版 client 新增、尚未惰性遷移的群組）。
    private func unifiedExpenses(subcollection: [[String: Any]], legacyArray: [[String: Any]]) -> [[String: Any]] {
        var byId: [String: [String: Any]] = [:]
        for e in legacyArray { if let id = e["id"] as? String { byId[id] = e } }
        for e in subcollection { if let id = e["id"] as? String { byId[id] = e } }   // 子集合覆蓋陣列（權威）
        return Array(byId.values)
    }

    /// 合併花費（新增/更新含 splits）。expensesData 為雙讀統一後的花費清單。
    @MainActor
    private func mergeExpenses(_ expensesData: [[String: Any]], into group: Group, modelContext: ModelContext) {
        let memberMap = Dictionary(uniqueKeysWithValues: group.members.map { ($0.id, $0) })

        for eData in expensesData {
            guard let idStr = eData["id"] as? String, let uuid = UUID(uuidString: idStr) else { continue }
            // 墓碑:被永久移除的花費 → 刪本地、絕不重建
            // (rules 禁止 client 硬刪文件,永久刪除改用 isPurged 標記)
            if eData["isPurged"] as? Bool == true {
                if let existing = group.expenses.first(where: { $0.id == uuid }) {
                    group.expenses.removeAll { $0.id == uuid }
                    modelContext.delete(existing)
                }
                continue
            }
            guard let title = eData["title"] as? String,
                  let totalStr = eData["totalAmount"] as? String,
                  let total = Decimal(string: totalStr) else { continue }
            let payerIdStr = eData["payerId"] as? String ?? ""
            let payerId = UUID(uuidString: payerIdStr)
            let payer = payerId.flatMap { memberMap[$0] }
            let archived = eData["isDeleted"] as? Bool ?? false

            if let existing = group.expenses.first(where: { $0.id == uuid }) {
                    // Last-write-wins 防護：遠端這份比本地已知的舊（如落後的鏡像陣列），跳過，
                    // 免得把較新的編輯退回舊值。只在兩邊都有 updatedAt 時比較——遠端沒有
                    // 時間戳可能是舊版 client 的合法新編輯，仍須照舊合併。
                    if let localUpdated = existing.updatedAt,
                       let remoteUpdated = (eData["updatedAt"] as? Timestamp)?.dateValue(),
                       remoteUpdated < localUpdated {
                        continue
                    }
                    if existing.title != title { existing.title = title }
                    if existing.totalAmount != total { existing.totalAmount = total }
                    if existing.paidBy?.id != payer?.id { existing.paidBy = payer }
                    if existing.archived != archived { existing.archived = archived }
                    let newDate = (eData["date"] as? Timestamp)?.dateValue()
                    if existing.date != newDate { existing.date = newDate }
                    let newNote: String? = {
                        if let note = eData["note"] as? String { return note.isEmpty ? nil : note }
                        return nil
                    }()
                    if existing.note != newNote { existing.note = newNote }
                    let newDeletedAt = (eData["deletedAt"] as? Timestamp)?.dateValue()
                    if existing.deletedAt != newDeletedAt { existing.deletedAt = newDeletedAt }

                    let newOriginalCode = eData["originalCurrencyCode"] as? String
                    if existing.originalCurrencyCode != newOriginalCode {
                        existing.originalCurrencyCode = newOriginalCode
                    }
                    let newOriginalAmount: Decimal? = {
                        if let str = eData["originalAmount"] as? String { return Decimal(string: str) }
                        return nil
                    }()
                    if existing.originalAmount != newOriginalAmount {
                        existing.originalAmount = newOriginalAmount
                    }
                    let newExchangeRate: Decimal? = {
                        if let str = eData["exchangeRate"] as? String { return Decimal(string: str) }
                        return nil
                    }()
                    if existing.exchangeRate != newExchangeRate {
                        existing.exchangeRate = newExchangeRate
                    }
                    let newIsEvenSplit = eData["isEvenSplit"] as? Bool
                    if existing.isEvenSplit != newIsEvenSplit {
                        existing.isEvenSplit = newIsEvenSplit
                    }
                    let newUpdatedAt = (eData["updatedAt"] as? Timestamp)?.dateValue()
                    if existing.updatedAt != newUpdatedAt { existing.updatedAt = newUpdatedAt }
                    let newEditor = eData["lastEditorName"] as? String
                    if existing.lastEditorName != newEditor { existing.lastEditorName = newEditor }

                    // Only rebuild splits if they actually differ (avoids expensive churn)
                    if !splitsMatch(existing: existing.splits, remote: eData["splits"] as? [[String: Any]] ?? []) {
                        let splitsCopy = Array(existing.splits)
                        existing.splits.removeAll()
                        for split in splitsCopy { modelContext.delete(split) }
                        appendSplits(from: eData, to: existing, memberMap: memberMap, modelContext: modelContext)
                    }
                } else {
                    // 即使遠端 payerId 對不到本地成員也保留花費（paidBy 暫為 nil，結算會略過），
                    // 待成員同步後由後續 merge 補上 paidBy，避免靜默丟失遠端花費。
                    let expense = Expense(title: title, totalAmount: total, paidBy: payer)
                    expense.id = uuid
                    expense.archived = archived
                    if let dateTs = eData["date"] as? Timestamp { expense.date = dateTs.dateValue() }
                    if let note = eData["note"] as? String, !note.isEmpty { expense.note = note }
                    if let createdTs = eData["createdAt"] as? Timestamp { expense.createdAt = createdTs.dateValue() }
                    if let delTs = eData["deletedAt"] as? Timestamp { expense.deletedAt = delTs.dateValue() }
                    expense.originalCurrencyCode = eData["originalCurrencyCode"] as? String
                    if let oaStr = eData["originalAmount"] as? String { expense.originalAmount = Decimal(string: oaStr) }
                    if let rateStr = eData["exchangeRate"] as? String { expense.exchangeRate = Decimal(string: rateStr) }
                    expense.isEvenSplit = eData["isEvenSplit"] as? Bool
                    if let ua = eData["updatedAt"] as? Timestamp { expense.updatedAt = ua.dateValue() }
                    expense.lastEditorName = eData["lastEditorName"] as? String
                    modelContext.insert(expense)
                    group.expenses.append(expense)
                    appendSplits(from: eData, to: expense, memberMap: memberMap, modelContext: modelContext)
                }
            }
        }

    private func splitsMatch(existing: [ExpenseSplit], remote: [[String: Any]]) -> Bool {
        guard existing.count == remote.count else { return false }
        let localSet: Set<String> = Set(existing.compactMap { s in
            guard let mid = s.member?.id.uuidString else { return nil }
            return "\(s.id.uuidString)|\(mid)|\(s.amount)"
        })
        let remoteSet: Set<String> = Set(remote.compactMap { r -> String? in
            guard let sid = r["id"] as? String,
                  let mid = r["memberId"] as? String,
                  let amt = r["amount"] as? String else { return nil }
            return "\(sid)|\(mid)|\(amt)"
        })
        return localSet == remoteSet
    }

    @MainActor
    private func appendSplits(
        from eData: [String: Any],
        to expense: Expense,
        memberMap: [UUID: Member],
        modelContext: ModelContext
    ) {
        guard let splitsData = eData["splits"] as? [[String: Any]] else { return }
        for sData in splitsData {
            guard let sid = sData["id"] as? String, let splitUUID = UUID(uuidString: sid),
                  let amtStr = sData["amount"] as? String, let amt = Decimal(string: amtStr),
                  let memIdStr = sData["memberId"] as? String, let memId = UUID(uuidString: memIdStr),
                  let member = memberMap[memId] else { continue }
            let split = ExpenseSplit(member: member, amount: amt)
            split.id = splitUUID
            modelContext.insert(split)
            expense.splits.append(split)
        }
    }

    // MARK: - Activity Log

    func logActivity(
        for group: Group,
        action: ActivityAction,
        target: String,
        details: String? = nil
    ) async {
        guard let groupId = group.firestoreGroupId else { return }
        let actorName = await MainActor.run { claimedMember(in: group)?.name ?? "匿名" }
        await logActivity(
            groupId: groupId,
            actorName: actorName,
            action: action,
            target: target,
            details: details
        )
    }

    func logActivity(
        groupId: String,
        actorName: String,
        action: ActivityAction,
        target: String,
        details: String? = nil
    ) async {
        guard FirebaseApp.app() != nil else { return }
        try? await signInAnonymously()
        let actorId = currentUserId ?? ""
        var payload: [String: Any] = [
            "actorName": actorName,
            "actorId": actorId,
            "action": action.rawValue,
            "target": target,
            "timestamp": FieldValue.serverTimestamp()
        ]
        if let details, !details.isEmpty {
            payload["details"] = details
        }
        _ = try? await db.collection("groups").document(groupId)
            .collection("activities").addDocument(data: payload)
    }

    /// 群組最新一筆活動時間（帳本列表未讀紅點用）；讀不到一律回 nil 不視為未讀。
    func latestActivityDate(groupId: String) async -> Date? {
        guard FirebaseApp.app() != nil else { return nil }
        try? await signInAnonymously()
        let snap = try? await db.collection("groups").document(groupId)
            .collection("activities")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments()
        return (snap?.documents.first?.data()["timestamp"] as? Timestamp)?.dateValue()
    }

    @MainActor
    func listenToActivities(
        groupId: String,
        onUpdate: @escaping ([ActivityEntry]) -> Void
    ) -> SharingSubscription {
        let reg = db.collection("groups").document(groupId)
            .collection("activities")
            .order(by: "timestamp", descending: true)
            .limit(to: 200)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { Self.parseActivity(id: $0.documentID, data: $0.data()) }
                Task { @MainActor in onUpdate(entries) }
            }
        return SharingSubscription { reg.remove() }
    }

    /// 一次性抓最新活動（背景通知檢查用，不掛 listener）。
    func recentActivities(groupId: String, limit: Int) async -> [ActivityEntry] {
        guard FirebaseApp.app() != nil else { return [] }
        let snap = try? await db.collection("groups").document(groupId)
            .collection("activities")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return (snap?.documents ?? []).compactMap { Self.parseActivity(id: $0.documentID, data: $0.data()) }
    }

    private static func parseActivity(id: String, data: [String: Any]) -> ActivityEntry? {
        guard let actorName = data["actorName"] as? String,
              let actionStr = data["action"] as? String,
              let action = ActivityAction(rawValue: actionStr),
              let target = data["target"] as? String else { return nil }
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        let details = data["details"] as? String
        return ActivityEntry(
            id: id,
            actorName: actorName,
            actorId: data["actorId"] as? String ?? "",
            action: action,
            target: target,
            details: (details?.isEmpty ?? true) ? nil : details,
            timestamp: timestamp
        )
    }

    // MARK: - Serialization

    private func serializeGroup(_ group: Group, ownerId: String, inviteCode: String) -> [String: Any] {
        var data: [String: Any] = [
            "name": group.name,
            "createdAt": Timestamp(date: group.createdAt),
            "isSettled": group.isSettled,
            "ownerId": ownerId,
            "localGroupId": group.id.uuidString,
            "inviteCode": inviteCode,
            "baseCurrencyCode": group.baseCurrencyCode
        ]

        data["members"] = group.members.map { member -> [String: Any] in
            var m: [String: Any] = ["id": member.id.uuidString, "name": member.name]
            if let uid = member.claimedByUid { m["claimedByUid"] = uid }
            return m
        }

        data["expenses"] = group.expenses.map { serializeExpense($0) }

        return data
    }

    /// 單筆花費序列化。子集合文件 `groups/{id}/expenses/{eid}` 與舊 `expenses[]` 陣列元素
    /// 共用同一結構（雙寫過渡期兩處皆寫）。
    private func serializeExpense(_ expense: Expense) -> [String: Any] {
        var eDict: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "totalAmount": "\(expense.totalAmount)",
            "payerId": expense.paidBy?.id.uuidString ?? "",
            "createdAt": Timestamp(date: expense.createdAt),
            "isDeleted": expense.archived
        ]
        if let date = expense.date { eDict["date"] = Timestamp(date: date) }
        if let note = expense.note { eDict["note"] = note }
        if let deletedAt = expense.deletedAt { eDict["deletedAt"] = Timestamp(date: deletedAt) }
        if let oc = expense.originalCurrencyCode { eDict["originalCurrencyCode"] = oc }
        if let oa = expense.originalAmount { eDict["originalAmount"] = "\(oa)" }
        if let rate = expense.exchangeRate { eDict["exchangeRate"] = "\(rate)" }
        if let ev = expense.isEvenSplit { eDict["isEvenSplit"] = ev }
        if let ua = expense.updatedAt { eDict["updatedAt"] = Timestamp(date: ua) }
        if let ed = expense.lastEditorName { eDict["lastEditorName"] = ed }
        eDict["splits"] = expense.splits.map { split in
            [
                "id": split.id.uuidString,
                "memberId": split.member?.id.uuidString ?? "",
                "amount": "\(split.amount)"
            ]
        }
        return eDict
    }

    private func deserializeGroup(from data: [String: Any], firestoreId: String, inviteCode: String) throws -> Group {
        let name = data["name"] as? String ?? ""
        let baseCode = data["baseCurrencyCode"] as? String ?? "TWD"
        let group = Group(name: name, baseCurrencyCode: baseCode)

        if let idStr = data["localGroupId"] as? String, let uuid = UUID(uuidString: idStr) {
            group.id = uuid
        }
        group.isSettled = data["isSettled"] as? Bool ?? false
        group.firestoreGroupId = firestoreId
        group.firebaseOwnerId = data["ownerId"] as? String
        group.inviteCode = inviteCode
        if let ts = data["createdAt"] as? Timestamp { group.createdAt = ts.dateValue() }

        var memberMap: [UUID: Member] = [:]
        if let membersData = data["members"] as? [[String: Any]] {
            for mData in membersData {
                guard let idStr = mData["id"] as? String, let uuid = UUID(uuidString: idStr),
                      let mname = mData["name"] as? String else { continue }
                let member = Member(name: mname)
                member.id = uuid
                member.claimedByUid = mData["claimedByUid"] as? String
                group.members.append(member)
                memberMap[uuid] = member
            }
        }

        if let expensesData = data["expenses"] as? [[String: Any]] {
            for eData in expensesData {
                guard let idStr = eData["id"] as? String, let uuid = UUID(uuidString: idStr),
                      let title = eData["title"] as? String,
                      let totalStr = eData["totalAmount"] as? String,
                      let total = Decimal(string: totalStr),
                      let payerIdStr = eData["payerId"] as? String,
                      let payerId = UUID(uuidString: payerIdStr),
                      let payer = memberMap[payerId] else { continue }

                let expense = Expense(title: title, totalAmount: total, paidBy: payer)
                expense.id = uuid
                expense.archived = eData["isDeleted"] as? Bool ?? false
                if let dateTs = eData["date"] as? Timestamp { expense.date = dateTs.dateValue() }
                if let note = eData["note"] as? String { expense.note = note }
                if let createdTs = eData["createdAt"] as? Timestamp { expense.createdAt = createdTs.dateValue() }
                if let delTs = eData["deletedAt"] as? Timestamp { expense.deletedAt = delTs.dateValue() }
                expense.originalCurrencyCode = eData["originalCurrencyCode"] as? String
                if let oaStr = eData["originalAmount"] as? String { expense.originalAmount = Decimal(string: oaStr) }
                if let rateStr = eData["exchangeRate"] as? String { expense.exchangeRate = Decimal(string: rateStr) }
                expense.isEvenSplit = eData["isEvenSplit"] as? Bool
                if let ua = eData["updatedAt"] as? Timestamp { expense.updatedAt = ua.dateValue() }
                expense.lastEditorName = eData["lastEditorName"] as? String

                if let splitsData = eData["splits"] as? [[String: Any]] {
                    for sData in splitsData {
                        guard let sid = sData["id"] as? String, let splitUUID = UUID(uuidString: sid),
                              let amtStr = sData["amount"] as? String, let amt = Decimal(string: amtStr),
                              let memIdStr = sData["memberId"] as? String, let memId = UUID(uuidString: memIdStr),
                              let member = memberMap[memId] else { continue }
                        let split = ExpenseSplit(member: member, amount: amt)
                        split.id = splitUUID
                        expense.splits.append(split)
                    }
                }

                group.expenses.append(expense)
            }
        }

        return group
    }
}

// MARK: - Subscription Handle

/// 雙讀 listener 的快取狀態：group 文件與 expenses 子集合各保留最新一份，
/// 任一更新時重新合併（僅於 MainActor 讀寫）。
final class SyncState {
    var groupData: [String: Any]?
    var subDocs: [[String: Any]]?
}

final class SharingSubscription {
    private var cancel: (() -> Void)?
    init(cancel: @escaping () -> Void) { self.cancel = cancel }
    func stop() {
        cancel?()
        cancel = nil
    }
    deinit {
        cancel?()
    }
}

// MARK: - Activity Types

enum ActivityAction: String, Codable, Sendable {
    case sharedGroup = "shared_group"
    case joinedGroup = "joined_group"
    case addedMember = "added_member"
    case removedMember = "removed_member"
    case addedExpense = "added_expense"
    case editedExpense = "edited_expense"
    case renamedExpense = "renamed_expense"
    case deletedExpense = "deleted_expense"
    case restoredExpense = "restored_expense"
    case settledGroup = "settled_group"
    case unsettledGroup = "unsettled_group"
}

extension ActivityAction {
    /// 動作的顯示文案（活動頁列表與本地通知共用）。
    var displayText: String {
        switch self {
        case .sharedGroup: return "分享了帳目"
        case .joinedGroup: return "加入了帳目"
        case .addedMember: return "加入了成員"
        case .removedMember: return "移除了成員"
        case .addedExpense: return "新增了花費"
        case .editedExpense: return "編輯了花費"
        case .renamedExpense: return "改了花費名稱"
        case .deletedExpense: return "刪除了花費"
        case .restoredExpense: return "還原了花費"
        case .settledGroup: return "標記為結清"
        case .unsettledGroup: return "取消結清"
        }
    }
}

struct ActivityEntry: Identifiable, Hashable, Sendable {
    let id: String
    let actorName: String
    let actorId: String
    let action: ActivityAction
    let target: String
    let details: String?
    let timestamp: Date
}

/// 每裝置的「看過此帳本活動」時間戳（未讀紅點）。存 UserDefaults 不進 SwiftData——
/// 已讀是裝置層級的狀態，不該跟著帳本資料同步到其他裝置。
enum ActivitySeenStore {
    private static func key(_ groupId: String) -> String { "activitySeen.\(groupId)" }

    static func lastSeen(groupId: String) -> Date? {
        UserDefaults.standard.object(forKey: key(groupId)) as? Date
    }

    static func markSeen(groupId: String) {
        UserDefaults.standard.set(Date(), forKey: key(groupId))
    }

    // 背景通知的去重標記：記到「已通知過的最新活動時間」，下次背景檢查
    // 只對更晚的活動再發通知，避免同一批動態重複打擾。
    static func lastNotified(groupId: String) -> Date? {
        UserDefaults.standard.object(forKey: "activityNotified.\(groupId)") as? Date
    }

    static func markNotified(groupId: String, upTo date: Date) {
        UserDefaults.standard.set(date, forKey: "activityNotified.\(groupId)")
    }
}

// MARK: - Errors

enum SharingError: LocalizedError {
    case notAuthenticated
    case inviteCodeNotFound
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "請確認網路連線後再試"
        case .inviteCodeNotFound: return "找不到此邀請碼，請確認輸入是否正確"
        case .groupNotFound: return "找不到共享的帳目"
        }
    }
}
