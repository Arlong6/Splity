import Foundation

/// 插頁廣告的頻率規則。寫法比照 `ReviewPrompt`：純 UserDefaults 邏輯、可注入 `now` 與 suite，方便測。
///
/// 三道門檻：
/// 1. 安裝（或更新到有廣告的版本）後 `gracePeriod` 內不顯示——別在第一印象就塞全螢幕廣告；
/// 2. 累積看過 `viewsPerAd` 次結算明細才顯示一次；
/// 3. 兩次顯示至少間隔 `minimumInterval`。
///
/// `consumeShowOpportunity()` 回傳 true 就會把計數歸零並記下時間，所以呼叫端要先確定
/// 廣告已經載好、真的要播，再來消費這次機會。
enum InterstitialPolicy {
    private static let viewsKey = "InterstitialPolicy_settlementViews"
    private static let lastShownKey = "InterstitialPolicy_lastShownDate"
    private static let firstLaunchKey = "InterstitialPolicy_firstLaunchDate"

    static let viewsPerAd = 3
    static let minimumInterval: TimeInterval = 10 * 60
    static let gracePeriod: TimeInterval = 24 * 60 * 60

    /// 第一次啟動時記下時間，之後不再改。App 啟動廣告流程時呼叫。
    static func recordFirstLaunchIfNeeded(now: Date = Date(), defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: firstLaunchKey) == nil else { return }
        defaults.set(now, forKey: firstLaunchKey)
    }

    /// 結算明細頁出現時呼叫。
    static func recordSettlementViewed(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: viewsKey) + 1, forKey: viewsKey)
    }

    static func settlementViews(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: viewsKey)
    }

    static func consumeShowOpportunity(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: "IS_UI_TESTING") else { return false }

        guard let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date else {
            // 還沒記過首次啟動：現在記下，這次不播。
            defaults.set(now, forKey: firstLaunchKey)
            return false
        }
        guard now.timeIntervalSince(firstLaunch) >= gracePeriod else { return false }
        guard defaults.integer(forKey: viewsKey) >= viewsPerAd else { return false }
        if let lastShown = defaults.object(forKey: lastShownKey) as? Date {
            guard now.timeIntervalSince(lastShown) >= minimumInterval else { return false }
        }

        defaults.set(now, forKey: lastShownKey)
        defaults.set(0, forKey: viewsKey)
        return true
    }
}
