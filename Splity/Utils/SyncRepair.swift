import Foundation

/// 同步時用到的純邏輯，抽出來方便單元測試（不碰 Firestore、不碰 SwiftData）。
nonisolated enum SyncRepair {

    // MARK: - 成員清單合併

    struct MemberSnapshot {
        let id: String
        let name: String
        let claim: String?
    }

    /// 推送成員清單前與遠端合併。members 是整個陣列寫回，直接推本地清單會把
    /// 別台剛加、本機還沒收到的成員洗掉。
    /// - 本地有的：用本地名稱；認領本地優先，本地沒有就保留遠端的。
    /// - 只有遠端有的：保留，除非是本機這次刪掉的（`removedIDs`）。
    static func mergedMembers(
        local: [MemberSnapshot],
        remote: [[String: Any]],
        removedIDs: Set<String>
    ) -> [[String: Any]] {
        var remoteByID: [String: [String: Any]] = [:]
        for m in remote {
            if let id = m["id"] as? String { remoteByID[id] = m }
        }

        var result: [[String: Any]] = local.map { member in
            var m: [String: Any] = ["id": member.id, "name": member.name]
            if let uid = member.claim ?? remoteByID[member.id]?["claimedByUid"] as? String {
                m["claimedByUid"] = uid
            }
            return m
        }

        let localIDs = Set(local.map(\.id))
        for m in remote {
            guard let id = m["id"] as? String,
                  !localIDs.contains(id),
                  !removedIDs.contains(id) else { continue }
            result.append(m)
        }
        return result
    }

    // MARK: - 漏傳花費

    /// 本機有、雲端（子集合＋舊陣列）完全沒有的花費。這些從沒成功上傳過，
    /// 例如當初被 rules 擋下的長小數花費；雲端不會再有任何推送觸發它們，要主動補傳。
    /// `remote` 必須是完整的雲端清單，只拿到一部分時不能呼叫。
    static func unsyncedExpenseIDs(local: [UUID], remote: [[String: Any]]) -> [UUID] {
        let remoteIDs = Set(remote.compactMap { $0["id"] as? String })
        return local.filter { !remoteIDs.contains($0.uuidString) }
    }

    // MARK: - 舊陣列鏡像

    /// 把更新過的花費寫回舊版 client 讀的 expenses[] 陣列：同 id 原地替換，
    /// 沒有的附加在後；其他花費（可能是別人剛寫的）原樣保留。
    static func replacingLegacyExpenses(
        _ array: [[String: Any]],
        with updates: [String: [String: Any]]
    ) -> [[String: Any]] {
        var remaining = updates
        var result = array.map { entry -> [String: Any] in
            guard let id = entry["id"] as? String, let updated = remaining.removeValue(forKey: id) else {
                return entry
            }
            return updated
        }
        for id in remaining.keys.sorted() {
            if let entry = remaining[id] { result.append(entry) }
        }
        return result
    }

    // MARK: - 金額欄位收斂

    private static let amountKeys = ["totalAmount", "originalAmount", "exchangeRate"]

    /// 舊陣列的資料補建到子集合前，把金額欄位整理成 rules 收得下的字串。
    /// 舊版寫入的長小數或數字型別會被 rules 拒收，同一個 batch 的其他花費也會一起失敗。
    static func normalizedAmounts(_ expense: [String: Any]) -> [String: Any] {
        var result = expense
        for key in amountKeys {
            guard let raw = expense[key] else { continue }
            let decimal: Decimal?
            if let string = raw as? String {
                decimal = Decimal(string: string.trimmingCharacters(in: .whitespaces))
            } else if let number = raw as? NSNumber {
                decimal = Decimal(string: number.stringValue)
            } else {
                decimal = nil
            }
            if let decimal, decimal.isFinite {
                result[key] = RemoteAmount.encode(decimal)
            }
        }
        return result
    }

    // MARK: - 結算幣別不一致

    /// 花費存的結算幣別和帳本不一致時，回傳換算要用的來源幣：外幣花費用原幣，
    /// 其他用當時的結算幣。一致或沒有記錄（舊資料）回傳 nil，不換算。
    static func conversionSource(expenseBase: String?, originalCode: String?, groupBase: String) -> String? {
        guard let expenseBase, expenseBase != groupBase else { return nil }
        return originalCode ?? expenseBase
    }

    /// 雲端上一筆花費的幣別與「伺服器寫入時間」。
    struct RemoteExpenseBase {
        let id: UUID
        let base: String?
        let serverWrittenAt: Date?
    }

    /// 雲端上哪些花費要補換算：記的結算幣別和帳本不同，而且是在換幣別「之後」才寫到伺服器的。
    ///
    /// 換幣別那台會把它當下有的花費全部換好再推，那些已經是新幣別，不會被選到。
    /// 被選到的是它當時沒看到的：離線時記的花費，不論是在換幣別之前或之後記的，
    /// 都是連上網才寫進伺服器，寫入時間一定晚於換幣別。
    /// 兩個時間都是伺服器時間，所以手機時鐘不準也不影響。沒有幣別或寫入時間的舊資料不動。
    static func staleBaseExpenseIDs(
        remote: [RemoteExpenseBase],
        groupBase: String,
        changedAt: Date
    ) -> Set<UUID> {
        Set(remote.filter { expense in
            guard let base = expense.base, base != groupBase,
                  let written = expense.serverWrittenAt else { return false }
            return written > changedAt
        }.map(\.id))
    }
}
