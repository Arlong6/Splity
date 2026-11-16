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

    /// 使用者已離開當前畫面、無法就地跳 alert 的背景推送失敗。
    /// 下一個出現的群組畫面負責顯示並清掉，避免「看起來存好了、其實沒同步出去」。
    var pendingSyncError: String?

    /// 本次執行已嘗試補傳過的花費（雲端完全沒有的那些）。只試一次，
    /// 被 rules 擋下的資料不會因為每次合併都重送而無限重試。
    @ObservationIgnored private var repushAttempted: Set<UUID> = []
    /// 正在補換算的花費。快照很密，等匯率時下一個快照又會選到同一筆，避免同一台重複換。
    @ObservationIgnored private var convertingExpenseIDs: Set<UUID> = []
    /// 刪除成員時推送失敗（例如離線）的成員 id（帳本 id → 成員 id）。之後每次推送群組都帶上，
    /// 成功才清掉；不然 mergedMembers 會把遠端還在的成員當成「別台剛加的」保留，刪除就永遠沒送出。
    /// 只存在記憶體：App 重開前沒推送成功就會遺失。
    @ObservationIgnored private var pendingRemovedMembers: [UUID: Set<String>] = [:]

    private init() {}

    /// 執行背景推送；失敗時記下錯誤而不是靜默吞掉。
    @MainActor
    func pushInBackground(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            DiagnosticLog.shared.record("背景上傳失敗：\(DiagnosticLog.describe(error))")
            pendingSyncError = error.localizedDescription
        }
    }

    /// 取出並清除待顯示的背景同步錯誤。
    @MainActor
    func consumePendingSyncError() -> String? {
        defer { pendingSyncError = nil }
        return pendingSyncError
    }

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
        try modelContext.save()
        if group.isShared {
            do {
                try await pushMemberClaim(member, uid: uid, in: group)
            } catch {
                // 推送失敗就收回本地認領：否則畫面顯示認領成功，下一次遠端同步又把它洗掉，
                // 使用者只會看到認領視窗莫名再跳一次，完全不知道發生什麼事。
                member.claimedByUid = nil
                try? modelContext.save()
                throw error
            }
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
        do {
            let result = try await Auth.auth().signInAnonymously()
            currentUserId = result.user.uid
        } catch {
            DiagnosticLog.shared.record("匿名登入失敗：\(DiagnosticLog.describe(error))")
            throw error
        }
    }

    // MARK: - Invite Code

    func generateCode() -> String {
        let charset = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in charset[Int.random(in: 0..<charset.count)] })
    }

    /// 邀請碼有效期：90 天。外流的碼會自然失效，過期後由擁有者在分享面板重新產生。
    static let inviteCodeLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// 產生不重複的邀請碼：碰撞極罕見，仍檢查避免劫持既有碼（配合 rules update:false 雙保險）
    private func uniqueCode() async -> String {
        var code = generateCode()
        for _ in 0..<5 {
            let existing = try? await db.collection("inviteCodes").document(code).getDocument()
            if existing?.exists != true { break }
            code = generateCode()
        }
        return code
    }

    /// Creates invite code for a group. Uploads group data to Firestore if not already shared.
    /// Returns the 6-char invite code.
    func createInviteCode(for group: Group) async throws -> String {
        try await signInAnonymously()
        guard let userId = currentUserId else { throw SharingError.notAuthenticated }

        // 已分享過就直接回傳邀請碼，不重推資料——花費平時已由 pushExpense 逐筆同步，
        // 這裡整包重推反而會把「本機尚未收到的較新遠端編輯」蓋回舊值。
        if let existingCode = group.inviteCode, group.firestoreGroupId != nil {
            // 已過期就直接換一組新的（擁有者本來就有權重新產生，省得他先看到一組無效碼）。
            // expiresAt 為 nil = 1.7.8 之前建立的碼，沒有到期日，永遠沿用。
            if let expiry = group.inviteCodeExpiresAt, expiry <= Date() {
                // 只有擁有者能換碼：加入者本地存的是他當初 join 用的那組，
                // 讓他自動換發只會把擁有者正在流通的碼覆蓋掉，而對方毫無提示。
                guard group.firebaseOwnerId == userId else {
                    throw SharingError.inviteCodeExpired
                }
                return try await regenerateInviteCode(for: group)
            }
            return existingCode
        }

        let code = await uniqueCode()
        let expiresAt = Date().addingTimeInterval(Self.inviteCodeLifetime)

        let groupData = serializeGroup(group, ownerId: userId, inviteCode: code)
        // 原子寫入 group 文件 + 邀請碼，任一失敗都不留孤兒文件
        let docRef = db.collection("groups").document()
        let batch = db.batch()
        batch.setData(groupData, forDocument: docRef)
        batch.setData([
            "groupId": docRef.documentID,
            "groupName": group.name,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt)
        ], forDocument: db.collection("inviteCodes").document(code))
        try await batch.commit()

        await MainActor.run {
            group.firestoreGroupId = docRef.documentID
            group.firebaseOwnerId = userId
            group.inviteCode = code
            group.inviteCodeExpiresAt = expiresAt
        }

        await logActivity(for: group, action: .sharedGroup, target: group.name)
        return code
    }

    /// 重新產生邀請碼（過期後由擁有者觸發）。舊碼文件依規則不可改也不可刪，會留在
    /// Firestore 直到自己過期；group 文件的 `inviteCode` 指向新碼，之後分享的都是新碼。
    @discardableResult
    func regenerateInviteCode(for group: Group) async throws -> String {
        try await signInAnonymously()
        guard let firestoreId = group.firestoreGroupId else {
            // 還沒分享過 → 等同首次建立（不會遞迴回來：早退分支需要 firestoreGroupId 非 nil）
            return try await createInviteCode(for: group)
        }

        let code = await uniqueCode()
        let expiresAt = Date().addingTimeInterval(Self.inviteCodeLifetime)

        let batch = db.batch()
        batch.setData([
            "groupId": firestoreId,
            "groupName": group.name,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt)
        ], forDocument: db.collection("inviteCodes").document(code))
        batch.updateData(["inviteCode": code],
                         forDocument: db.collection("groups").document(firestoreId))
        try await batch.commit()

        await MainActor.run {
            group.inviteCode = code
            group.inviteCodeExpiresAt = expiresAt
        }
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

        // 到期檢查。`expiresAt` 不存在 = 1.7.8 之前建立的碼，沒有到期日，照舊放行。
        // 誠實標注：這是 client 端的把關（rules 無法在讀 groups 時得知用了哪組邀請碼），
        // 擋的是「外流的舊碼被一般使用者拿去加入」，不是有心人直繫 API 的越權讀取。
        let codeExpiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()
        if let codeExpiresAt, codeExpiresAt <= Date() {
            throw SharingError.inviteCodeExpired
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
                existing.inviteCodeExpiresAt = codeExpiresAt
                try modelContext.save()
                return
            }
        }

        let group = try deserializeGroup(from: groupData, firestoreId: groupId, inviteCode: upperCode)
        group.inviteCodeExpiresAt = codeExpiresAt
        modelContext.insert(group)
        for member in group.members { modelContext.insert(member) }
        for expense in group.expenses {
            modelContext.insert(expense)
            for split in expense.splits { modelContext.insert(split) }
        }
        try modelContext.save()
    }

    // MARK: - Sync

    /// 換結算幣別後推送：只更新帳本的幣別欄位與每一筆換算過的花費。
    /// 不整份覆寫帳本文件——那會洗掉別人同時做的成員認領、新成員或舊陣列裡的編輯。
    /// 一併寫入 `baseCurrencyChangedAt`（伺服器時間），讓離線時記帳的裝置判斷哪些花費要自己補換算。
    func pushBaseCurrencyChange(for group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        // 先取出純值再 await（理由同 pushExpense）
        let baseCode = group.baseCurrencyCode
        var updates: [String: [String: Any]] = [:]
        for expense in group.expenses {
            updates[expense.id.uuidString] = serializeExpense(expense)
        }
        try await signInAnonymously()
        let groupRef = db.collection("groups").document(firestoreId)

        // 花費子集合（權威）：merge 保住 isPurged 墓碑
        let ids = updates.keys.sorted()
        let expenseRef = { (id: String) in groupRef.collection("expenses").document(id) }

        // 一個 transaction 最多寫 500 份文件。放得下（幾乎所有帳本）就花費和帳本幣別一起寫，
        // 要嘛全部成功、要嘛全部沒變，不會出現「花費已是新幣別、帳本還是舊幣別」。
        let fitsInOneTransaction = ids.count <= Self.maxExpensesPerAtomicBaseChange
        if !fitsInOneTransaction {
            // 太多筆只能先分批寫花費，這條路不是原子的：之後帳本那步失敗的話，花費已是新幣別、
            // 帳本還是舊幣別。帳本以前換過幣別（有 baseCurrencyChangedAt）時，其他裝置的
            // repairAfterMerge 會把這些花費換回帳本幣別；從沒換過的帳本就只能靠使用者重新換一次。
            for chunkStart in stride(from: 0, to: ids.count, by: 400) {
                let batch = db.batch()
                for id in ids[chunkStart..<min(chunkStart + 400, ids.count)] {
                    batch.setData(Self.withServerWrittenAt(updates[id]!), forDocument: expenseRef(id), merge: true)
                }
                try await batch.commit()
            }
        }

        // 帳本欄位＋舊陣列鏡像：transaction 只替換換算過的那幾筆
        _ = try await db.runTransaction { (txn, errorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(groupRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard snap.exists else { return nil }
            var fields: [String: Any] = [
                "baseCurrencyCode": baseCode,
                "baseCurrencyChangedAt": FieldValue.serverTimestamp()
            ]
            if let legacy = snap.data()?["expenses"] as? [[String: Any]] {
                let known = Set(legacy.compactMap { $0["id"] as? String })
                // 只替換舊陣列原本就有的：子集合時代才新增的花費不必塞回舊陣列
                fields["expenses"] = SyncRepair.replacingLegacyExpenses(
                    legacy, with: updates.filter { known.contains($0.key) })
            }
            if fitsInOneTransaction {
                for id in ids {
                    txn.setData(Self.withServerWrittenAt(updates[id]!), forDocument: expenseRef(id), merge: true)
                }
            }
            txn.updateData(fields, forDocument: groupRef)
            return nil
        }
    }

    /// 換幣別時一起放進同一個 transaction 的花費上限（Firestore 一次最多 500 筆寫入，留帳本文件與餘裕）。
    private static let maxExpensesPerAtomicBaseChange = 450

    /// Granular 推送（主要路徑）：只寫「這一筆」花費到子集合（權威、per-doc last-write-wins），
    /// 並用 transaction 把這一筆鏡像回舊 expenses[] 陣列（給尚未升級的舊版 client 讀）。
    /// 避免每次推全部花費所造成的併發互蓋。
    func pushExpense(_ expense: Expense, in group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        // 先取出純值再 await：等登入時花費可能被刪，讀已刪除的 SwiftData 模型會閃退
        let expenseId = expense.id.uuidString
        let expenseData = serializeExpense(expense)
        try await signInAnonymously()
        let groupRef = db.collection("groups").document(firestoreId)

        // 1) 子集合文件（權威來源）
        // merge：保住可能已存在的 isPurged 墓碑（serializeExpense 不含 isPurged，整包覆蓋會讓永久刪除的花費復活）
        try await groupRef.collection("expenses").document(expenseId)
            .setData(Self.withServerWrittenAt(expenseData), merge: true)

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
            let arr = SyncRepair.replacingLegacyExpenses(
                (snap.data()?["expenses"] as? [[String: Any]]) ?? [],
                with: [expenseId: expenseData]
            )
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
                batch.setData(SyncRepair.normalizedAmounts(eData),
                              forDocument: groupRef.collection("expenses").document(id), merge: true)
            }
            try await batch.commit()
        } catch {
            // 非關鍵；下次讀取再試
        }
    }

    /// 只推送 group 文件層級欄位（名稱/結算/基準幣/成員），用 updateData 不觸碰 expenses
    /// （陣列與子集合都不動），避免成員/結算等變動順手重寫花費而 clobber 併發編輯。
    /// 推送群組層級的欄位（名稱／結清狀態／基準幣／成員清單）。
    ///
    /// members 是整個陣列覆寫，所以必須在同一個 transaction 裡把遠端既有的 `claimedByUid`
    /// 讀回來合併：本地可能還沒收到別人剛用 transaction 寫下的認領，直接推本地狀態會把它抹掉
    /// （加成員／刪成員撞上別人認領時就會發生），對方下次同步就被要求重新認領，毫無提示。
    /// - Parameter removedMemberIDs: 本機這次刪掉的成員。其他遠端有、本機沒有的成員會保留
    ///   （別台剛加、本機還沒收到），不然整個陣列寫回會把它們洗掉。
    func pushGroupMeta(for group: Group, removedMemberIDs: Set<String> = []) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }

        // SwiftData 模型限定 MainActor，先取出純值再 await、再進 transaction 閉包
        let localMembers = group.members.map {
            SyncRepair.MemberSnapshot(id: $0.id.uuidString, name: $0.name, claim: $0.claimedByUid)
        }
        let name = group.name
        let isSettled = group.isSettled
        let baseCurrencyCode = group.baseCurrencyCode
        let groupRef = db.collection("groups").document(firestoreId)
        let groupID = group.id
        try await signInAnonymously()
        let removedIDs = removedMemberIDs.union(pendingRemovedMembers[groupID] ?? [])
        if !removedIDs.isEmpty { pendingRemovedMembers[groupID] = removedIDs }

        _ = try await db.runTransaction { (txn, errorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try txn.getDocument(groupRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let members = SyncRepair.mergedMembers(
                local: localMembers,
                remote: (snap.data()?["members"] as? [[String: Any]]) ?? [],
                removedIDs: removedIDs
            )

            txn.updateData([
                "name": name,
                "isSettled": isSettled,
                "baseCurrencyCode": baseCurrencyCode,
                "members": members
            ], forDocument: groupRef)
            return nil
        }
        // 送出成功才清；中間又有新的待刪成員就留著那些
        if var pending = pendingRemovedMembers[groupID] {
            pending.subtract(removedIDs)
            pendingRemovedMembers[groupID] = pending.isEmpty ? nil : pending
        }
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

    /// 只推送單一欄位，完全不碰 members 陣列——
    /// 給「成員沒變」的路徑（列表結清/改名）用，避免整包覆寫洗掉併發的認領/新成員。
    func pushGroupField(_ field: GroupField, of group: Group) async throws {
        guard let firestoreId = group.firestoreGroupId else { return }
        try await signInAnonymously()
        try await db.collection("groups").document(firestoreId).updateData(field.payload(of: group))
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
            repairAfterMerge(group, remoteExpenses: unified, remoteIsComplete: true,
                             baseChangedAt: Self.baseChangedAt(data))
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
            self.repairAfterMerge(group, remoteExpenses: unified,
                                  remoteIsComplete: !state.subDocsFromCache,
                                  baseChangedAt: Self.baseChangedAt(state.groupData))
        }

        // Skip local echoes — our own optimistic writes would re-enter merge and
        // fight SwiftUI list animations, causing UICollectionView batch-update crashes.
        let groupReg = groupRef.addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
            if let error { Self.logListenerError("帳本", error) }
            guard let snapshot, snapshot.exists, let data = snapshot.data() else { return }
            if snapshot.metadata.hasPendingWrites { return }
            Task { @MainActor in state.groupData = data; apply() }
        }
        let subReg = groupRef.collection("expenses")
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
                if let error { Self.logListenerError("花費", error) }
                guard let snapshot else { return }
                if snapshot.metadata.hasPendingWrites { return }
                let docs = snapshot.documents.map { $0.data() }
                let fromCache = snapshot.metadata.isFromCache
                Task { @MainActor in
                    state.subDocs = docs
                    state.subDocsFromCache = fromCache
                    apply()
                }
            }
        return SharingSubscription { groupReg.remove(); subReg.remove() }
    }

    /// 即時同步的錯誤原本直接丟掉；至少留在問題回報的操作紀錄裡。
    nonisolated private static func logListenerError(_ target: String, _ error: Error) {
        let text = "即時同步失敗（\(target)）：\(DiagnosticLog.describe(error))"
        Task { @MainActor in DiagnosticLog.shared.record(text) }
    }

    /// 合併完雲端資料後的兩項補救，都在背景推送、失敗記進 pendingSyncError：
    /// 1. 本機有、雲端完全沒有的花費補傳（例如當初被 rules 擋下的）。
    /// 2. 別台換了結算幣別、本機離線時在舊幣別下記的花費，換算到新幣別再推送。
    /// 帳本文件上最近一次換結算幣別的伺服器時間；舊版 client 換的沒有這欄。
    nonisolated private static func baseChangedAt(_ groupData: [String: Any]?) -> Date? {
        (groupData?["baseCurrencyChangedAt"] as? Timestamp)?.dateValue()
    }

    /// - Parameters:
    ///   - remoteIsComplete: 這批雲端資料是否完整（來自伺服器）。來自快取時可能缺文件，
    ///     這時不判斷「雲端沒有」，不然會拿本機舊資料蓋掉伺服器上較新的版本。
    ///   - baseChangedAt: 帳本最近一次換結算幣別的伺服器時間。沒有（舊版 client 換的或從沒換過）
    ///     就不補換算，寧可不動也不誤換。
    @MainActor
    private func repairAfterMerge(_ group: Group, remoteExpenses: [[String: Any]],
                                  remoteIsComplete: Bool, baseChangedAt: Date?) {
        guard group.isShared else { return }

        var toRepush: [Expense] = []
        if remoteIsComplete {
            let unsynced = SyncRepair.unsyncedExpenseIDs(
                local: group.expenses.map(\.id), remote: remoteExpenses
            ).filter { !repushAttempted.contains($0) }
            repushAttempted.formUnion(unsynced)
            toRepush = group.expenses.filter { unsynced.contains($0.id) }
        }

        // 每次合併都依雲端資料重新判斷，換算失敗時下一個快照自然會再試
        var toConvert: [Expense] = []
        if let baseChangedAt {
            let stale = SyncRepair.staleBaseExpenseIDs(
                remote: remoteExpenses.compactMap { e in
                    guard let idStr = e["id"] as? String, let id = UUID(uuidString: idStr),
                          e["isPurged"] as? Bool != true else { return nil }
                    return .init(id: id,
                                 base: e["baseCurrencyCode"] as? String,
                                 serverWrittenAt: (e["serverWrittenAt"] as? Timestamp)?.dateValue())
                },
                groupBase: group.baseCurrencyCode,
                changedAt: baseChangedAt
            ).subtracting(convertingExpenseIDs)
            toConvert = group.expenses.filter { stale.contains($0.id) }
            convertingExpenseIDs.formUnion(toConvert.map(\.id))
        }
        // 先取出 id：Task 結束時花費可能已被刪，不能再讀它的屬性
        let convertIDs = toConvert.map(\.id)
        let repushIDs = toRepush.map(\.id)

        guard !toRepush.isEmpty || !toConvert.isEmpty else { return }
        Task { @MainActor in
            var pushed: Set<UUID> = []
            defer { self.convertingExpenseIDs.subtract(convertIDs) }
            for expense in toConvert {
                // 每筆之間會 await；這段時間花費或整本帳本可能被刪掉。
                // 讀已刪除的 SwiftData 模型會閃退，所以每次都先確認還在。
                guard Self.isAlive(group), Self.isAlive(expense) else { continue }
                let base = group.baseCurrencyCode
                guard let source = SyncRepair.conversionSource(
                    expenseBase: expense.baseCurrencyCode,
                    originalCode: expense.originalCurrencyCode,
                    groupBase: base
                ) else { continue } // 已經一致（例如別台換好推過來了），不用再換
                do {
                    let rate = try await CurrencyService.shared.fetchLatestRate(from: source, to: base)
                    // 等匯率時可能被刪掉、被別台改過或帳本又換了幣別；狀態變了就不動，避免蓋掉較新的資料
                    guard Self.isAlive(group), Self.isAlive(expense),
                          group.baseCurrencyCode == base,
                          SyncRepair.conversionSource(
                              expenseBase: expense.baseCurrencyCode,
                              originalCode: expense.originalCurrencyCode,
                              groupBase: base
                          ) == source
                    else { continue }
                    BaseCurrencyConversion.convert(expense, from: source, rate: rate, to: base)
                    try? group.modelContext?.save()
                    DiagnosticLog.shared.record("補換算離線花費：\(source) → \(base)")
                    pushed.insert(expense.id) // 推送會 await，先記 id
                    await self.pushInBackground { try await self.pushExpense(expense, in: group) }
                } catch {
                    // 拿不到匯率：雲端那筆仍是舊幣別，下一次收到快照時會再被選到
                    DiagnosticLog.shared.record("補換算離線花費失敗（\(source) → \(base)），稍後重試：\(DiagnosticLog.describe(error))")
                }
            }
            // 換算成功的已經推過；沒換成（跳過或失敗）的照樣補傳，至少讓別人看得到這筆
            for (expense, id) in zip(toRepush, repushIDs) where !pushed.contains(id) {
                guard Self.isAlive(group), Self.isAlive(expense) else { continue }
                DiagnosticLog.shared.record("補傳雲端沒有的花費")
                await self.pushInBackground { try await self.pushExpense(expense, in: group) }
            }
        }
    }

    /// SwiftData 模型還沒被刪除。已刪除的模型讀屬性會閃退，跨 await 之後要先檢查。
    private static func isAlive(_ model: some PersistentModel) -> Bool {
        model.modelContext != nil && !model.isDeleted
    }

    /// 合併 group 文件層級資料：名稱、結算狀態、基準幣、成員。（expenses 改由 mergeExpenses 處理）
    @MainActor
    private func mergeGroupMeta(_ data: [String: Any], into group: Group, modelContext: ModelContext) {
        group.name = data["name"] as? String ?? group.name
        group.isSettled = data["isSettled"] as? Bool ?? group.isSettled
        // 離線花費的補換算改在 repairAfterMerge 依雲端資料判斷，這裡只更新幣別
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
            let existingExpense = group.expenses.first(where: { $0.id == uuid })

            // 合併決策（墓碑 / last-write-wins）抽在 ExpenseMergePolicy，純邏輯、有單元測試。
            switch ExpenseMergePolicy.decide(
                isPurged: eData["isPurged"] as? Bool == true,
                localUpdatedAt: existingExpense?.updatedAt,
                remoteUpdatedAt: (eData["updatedAt"] as? Timestamp)?.dateValue()
            ) {
            case .purge:
                // 被永久移除的花費 → 刪本地、絕不重建
                // (rules 禁止 client 硬刪文件,永久刪除改用 isPurged 標記)
                if let existing = existingExpense {
                    group.expenses.removeAll { $0.id == uuid }
                    modelContext.delete(existing)
                }
                continue
            case .skip:
                // 遠端這份比本地已知的舊(如落後的鏡像陣列)→ 不把較新的編輯退回舊值
                continue
            case .apply:
                break
            }
            guard let title = eData["title"] as? String,
                  let totalStr = eData["totalAmount"] as? String,
                  let total = RemoteAmount.parse(totalStr) else { continue }
            let payerIdStr = eData["payerId"] as? String ?? ""
            let payerId = UUID(uuidString: payerIdStr)
            let payer = payerId.flatMap { memberMap[$0] }
            let archived = eData["isDeleted"] as? Bool ?? false

            if let existing = existingExpense {
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
                        if let str = eData["originalAmount"] as? String { return RemoteAmount.parse(str) }
                        return nil
                    }()
                    if existing.originalAmount != newOriginalAmount {
                        existing.originalAmount = newOriginalAmount
                    }
                    let newExchangeRate: Decimal? = {
                        if let str = eData["exchangeRate"] as? String { return RemoteAmount.parse(str) }
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
                    let newBase = eData["baseCurrencyCode"] as? String
                    if existing.baseCurrencyCode != newBase { existing.baseCurrencyCode = newBase }

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
                    if let oaStr = eData["originalAmount"] as? String { expense.originalAmount = RemoteAmount.parse(oaStr) }
                    if let rateStr = eData["exchangeRate"] as? String { expense.exchangeRate = RemoteAmount.parse(rateStr) }
                    expense.isEvenSplit = eData["isEvenSplit"] as? Bool
                    if let ua = eData["updatedAt"] as? Timestamp { expense.updatedAt = ua.dateValue() }
                    expense.lastEditorName = eData["lastEditorName"] as? String
                    expense.baseCurrencyCode = eData["baseCurrencyCode"] as? String
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
                  let amtStr = sData["amount"] as? String, let amt = RemoteAmount.parse(amtStr),
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
        let actorName = await MainActor.run { claimedMember(in: group)?.name ?? localized("匿名") }
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

    /// 子集合文件加上伺服器寫入時間（離線排隊的寫入，時間是真正送達伺服器的那一刻）。
    /// 用來判斷花費是不是在換結算幣別之後才上傳的，見 `SyncRepair.staleBaseExpenseIDs`。
    /// 只加在子集合：舊 expenses[] 陣列的元素裡不能放 serverTimestamp。
    nonisolated private static func withServerWrittenAt(_ data: [String: Any]) -> [String: Any] {
        var data = data
        data["serverWrittenAt"] = FieldValue.serverTimestamp()
        return data
    }

    /// 單筆花費序列化。子集合文件 `groups/{id}/expenses/{eid}` 與舊 `expenses[]` 陣列元素
    /// 共用同一結構（雙寫過渡期兩處皆寫）。
    private func serializeExpense(_ expense: Expense) -> [String: Any] {
        var eDict: [String: Any] = [
            "id": expense.id.uuidString,
            "title": expense.title,
            "totalAmount": RemoteAmount.encode(expense.totalAmount),
            "payerId": expense.paidBy?.id.uuidString ?? "",
            "createdAt": Timestamp(date: expense.createdAt),
            "isDeleted": expense.archived
        ]
        if let date = expense.date { eDict["date"] = Timestamp(date: date) }
        if let note = expense.note { eDict["note"] = note }
        if let deletedAt = expense.deletedAt { eDict["deletedAt"] = Timestamp(date: deletedAt) }
        if let oc = expense.originalCurrencyCode { eDict["originalCurrencyCode"] = oc }
        if let oa = expense.originalAmount { eDict["originalAmount"] = RemoteAmount.encode(oa) }
        if let rate = expense.exchangeRate { eDict["exchangeRate"] = RemoteAmount.encode(rate) }
        if let ev = expense.isEvenSplit { eDict["isEvenSplit"] = ev }
        if let ua = expense.updatedAt { eDict["updatedAt"] = Timestamp(date: ua) }
        if let ed = expense.lastEditorName { eDict["lastEditorName"] = ed }
        if let base = expense.baseCurrencyCode { eDict["baseCurrencyCode"] = base }
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
                      let total = RemoteAmount.parse(totalStr),
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
                if let oaStr = eData["originalAmount"] as? String { expense.originalAmount = RemoteAmount.parse(oaStr) }
                if let rateStr = eData["exchangeRate"] as? String { expense.exchangeRate = RemoteAmount.parse(rateStr) }
                expense.isEvenSplit = eData["isEvenSplit"] as? Bool
                if let ua = eData["updatedAt"] as? Timestamp { expense.updatedAt = ua.dateValue() }
                expense.lastEditorName = eData["lastEditorName"] as? String

                if let splitsData = eData["splits"] as? [[String: Any]] {
                    for sData in splitsData {
                        guard let sid = sData["id"] as? String, let splitUUID = UUID(uuidString: sid),
                              let amtStr = sData["amount"] as? String, let amt = RemoteAmount.parse(amtStr),
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
    /// 花費快照是否來自本機快取。快取可能只有部分文件，不能拿來判斷「雲端沒有這筆」。
    var subDocsFromCache = true
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
        case .sharedGroup: return localized("分享了帳目")
        case .joinedGroup: return localized("加入了帳目")
        case .addedMember: return localized("加入了成員")
        case .removedMember: return localized("移除了成員")
        case .addedExpense: return localized("新增了花費")
        case .editedExpense: return localized("編輯了花費")
        case .renamedExpense: return localized("改了花費名稱")
        case .deletedExpense: return localized("刪除了花費")
        case .restoredExpense: return localized("還原了花費")
        case .settledGroup: return localized("標記為結清")
        case .unsettledGroup: return localized("取消結清")
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
    case inviteCodeExpired
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return localized("請確認網路連線後再試")
        case .inviteCodeNotFound: return localized("找不到此邀請碼，請確認輸入是否正確")
        case .inviteCodeExpired: return localized("邀請碼已過期，請向對方索取新的邀請碼")
        case .groupNotFound: return localized("找不到共享的帳目")
        }
    }
}

/// 列表頁可單獨推送的帳本欄位。列表沒有掛 listener，本地其他欄位可能已過期，
/// 所以只送這次改動的欄位，不能把過期的幣別或結清狀態蓋回遠端。
enum GroupField {
    case name
    case isSettled

    func payload(of group: Group) -> [String: Any] {
        switch self {
        case .name: return ["name": group.name]
        case .isSettled: return ["isSettled": group.isSettled]
        }
    }
}
