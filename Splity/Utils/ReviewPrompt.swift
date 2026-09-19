import Foundation

/// App Store 評分請求的節流規則。
///
/// 只在「結算完成」之後才問——那是使用者真正拿到價值的時刻，不是打開 app 的時候。
///
/// 三道條件疊在 Apple 自己的「一年最多顯示三次」之上，確保我們不會每出一版就問一次：
/// 1. 至少結清過 `minimumSettlements` 本**不同**的帳本（同一本反覆結清／取消結清只算一次）；
/// 2. 同一個 app 版本最多問一次；
/// 3. 問過一次之後，還要再多結清 `additionalSettlementsBetweenPrompts` 本新帳本，
///    而且距離上次詢問至少 `minimumIntervalBetweenPrompts`（120 天），才會再開口。
///
/// 第 3 點是重點：只靠「換版本就重置」等於每次改版都問一次（本 app 的出版節奏是
/// 1.7.8 → 1.8.0 → 1.8.1），實際節流全丟給系統那層。加上次數差與時間差之後，
/// 一個正常使用者一年最多被我們問一到兩次。
///
/// 不做任何誘導：沒有「你喜歡這個 app 嗎」的前置問卷，也不用獎勵換評分
/// （App Review Guidelines 第 3 節禁止）。呼叫端直接叫系統的評分面板，
/// 使用者給不給、給幾顆星我們都看不到，也無從引導。
enum ReviewPrompt {
    /// 1.8.2 以前：單純累加的整數。保留只為了讀舊值做遷移，不再寫入。
    private static let legacySettlementCountKey = "ReviewPrompt_settlementCount"
    /// 已計數過的帳本 id（字串陣列當集合用）。用集合而不是累加，
    /// 「結清 → 取消結清 → 再結清」同一本帳才不會灌水。
    private static let settledGroupIdsKey = "ReviewPrompt_settledGroupIds"
    private static let promptedVersionKey = "ReviewPrompt_promptedVersion"
    private static let promptedDateKey = "ReviewPrompt_promptedDate"
    private static let promptedAtCountKey = "ReviewPrompt_promptedAtSettlementCount"

    /// 累積結清幾本不同的帳本之後才開口。
    private static let minimumSettlements = 2

    /// 問過一次之後，要再多結清幾本新帳本才考慮再問。
    private static let additionalSettlementsBetweenPrompts = 2

    /// 兩次詢問之間至少要隔多久。
    private static let minimumIntervalBetweenPrompts: TimeInterval = 120 * 24 * 60 * 60

    /// 結算完成後隔多久才跳。一按完按鈕就跳像在攔路，先讓畫面更新完。
    static let delay: Duration = .seconds(2.5)

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 已完成結算的「不同帳本」數。
    ///
    /// 遷移：1.8.2 之前存的是一個只增不減的整數，直接改用集合會讓老使用者歸零。
    /// 取兩者較大值——舊整數當作「以前至少結清過這麼多本」，新集合只會往上加，
    /// 所以升級的人不會退步，新使用者也不受影響。
    static func settlementCount(defaults: UserDefaults = .standard) -> Int {
        let counted = defaults.stringArray(forKey: settledGroupIdsKey)?.count ?? 0
        let legacy = defaults.integer(forKey: legacySettlementCountKey)
        return max(counted, legacy)
    }

    /// 只在真正「結算成功」的路徑上呼叫（帳本被標記為結清、共享帳本也推送成功），
    /// 不要在畫面出現時呼叫。同一個 `groupId` 重複呼叫只算一次。
    static func recordSettlement(groupId: UUID, defaults: UserDefaults = .standard) {
        var ids = Set(defaults.stringArray(forKey: settledGroupIdsKey) ?? [])
        guard ids.insert(groupId.uuidString).inserted else { return }
        defaults.set(Array(ids), forKey: settledGroupIdsKey)
    }

    /// 消費一次詢問機會：符合上面三道條件才回傳 true，並立刻記下版本、日期與當下的
    /// 結算本數。回傳 true 之後就一定要真的叫 `requestReview()`——這個方法會把機會用掉。
    static func consumeRequestOpportunity(
        now: Date = Date(),
        version: String = currentVersion,
        defaults: UserDefaults = .standard
    ) -> Bool {
        // UI 測試不該被系統評分面板攔住（沿用 app 既有的測試旗標）
        guard !defaults.bool(forKey: "IS_UI_TESTING") else { return false }

        let count = settlementCount(defaults: defaults)
        guard count >= minimumSettlements else { return false }
        guard defaults.string(forKey: promptedVersionKey) != version else { return false }

        // 問過一次之後才有「次數差 + 時間差」的門檻；第一次不受這段限制。
        if let lastPrompt = defaults.object(forKey: promptedDateKey) as? Date {
            guard now.timeIntervalSince(lastPrompt) >= minimumIntervalBetweenPrompts else { return false }
            let countAtLastPrompt = defaults.integer(forKey: promptedAtCountKey)
            guard count - countAtLastPrompt >= additionalSettlementsBetweenPrompts else { return false }
        }

        defaults.set(version, forKey: promptedVersionKey)
        defaults.set(now, forKey: promptedDateKey)
        defaults.set(count, forKey: promptedAtCountKey)
        return true
    }
}
