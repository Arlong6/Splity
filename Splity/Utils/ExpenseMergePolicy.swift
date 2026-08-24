import Foundation

/// 遠端花費合併決策（純邏輯，刻意與 Firestore SDK 解耦以便單元測試）。
///
/// 合併資料有兩個來源：權威的 `groups/{id}/expenses` 子集合，以及留給舊版 client 讀的
/// 舊 `expenses[]` 鏡像陣列（盡力寫入、可能落後）。同一筆花費因此可能以「較舊的版本」
/// 後到，必須靠 last-write-wins 擋掉，否則會把較新的編輯退回舊值。
nonisolated enum ExpenseMergePolicy {

    enum Decision: Equatable {
        /// 遠端標記為永久刪除（墓碑）→ 刪本地、絕不重建。
        case purge
        /// 遠端這份比本地已知的舊 → 跳過，不覆寫。
        case skip
        /// 照常套用（新增或更新）。
        case apply
    }

    /// - Parameters:
    ///   - isPurged: 遠端文件的 `isPurged` 墓碑標記（rules 禁 client 硬刪，永久刪除改用此標記）。
    ///   - localUpdatedAt: 本地已知的最後編輯時間；`nil` = 1.7.5 之前建立、從未寫過時間戳的舊資料。
    ///   - remoteUpdatedAt: 遠端的最後編輯時間；`nil` = 舊版 client 寫的合法編輯。
    static func decide(isPurged: Bool,
                       localUpdatedAt: Date?,
                       remoteUpdatedAt: Date?) -> Decision {
        // 墓碑優先且具決定性：不論時間戳如何都刪，否則舊版 client 重推會讓已刪花費復活。
        if isPurged { return .purge }
        // 只有「兩邊都有時間戳」才能比較。遠端沒有時間戳可能是舊版 client 的合法新編輯，
        // 若一律當成舊的擋掉，舊版使用者的編輯將永遠同步不進來。
        guard let local = localUpdatedAt, let remote = remoteUpdatedAt else { return .apply }
        // 嚴格較舊才擋；相等視為同一份，照常套用（逐欄位比對本身是冪等的）。
        return remote < local ? .skip : .apply
    }
}
