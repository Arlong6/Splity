import Testing
import Foundation
@testable import Splity

/// `InterstitialPolicy` 的頻率規則。跟 `ReviewPromptTests` 一樣，每個測試用自己的 UserDefaults suite。
private func withTestDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "InterstitialPolicyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

private let day: TimeInterval = 24 * 60 * 60

@Suite("插頁廣告頻率")
struct InterstitialPolicyTests {
    private func primed(_ defaults: UserDefaults, installedAt: Date, views: Int) {
        InterstitialPolicy.recordFirstLaunchIfNeeded(now: installedAt, defaults: defaults)
        for _ in 0..<views { InterstitialPolicy.recordSettlementViewed(defaults: defaults) }
    }

    @Test("沒記過首次啟動：記下並拒絕")
    func firstCallRecordsLaunchAndDenies() {
        withTestDefaults { d in
            let now = Date()
            #expect(InterstitialPolicy.consumeShowOpportunity(now: now, defaults: d) == false)
            // 之後即使看夠次數，24 小時內仍然不播
            for _ in 0..<5 { InterstitialPolicy.recordSettlementViewed(defaults: d) }
            #expect(InterstitialPolicy.consumeShowOpportunity(now: now + 60, defaults: d) == false)
        }
    }

    @Test("安裝滿 24 小時且看滿 3 次才播，播完歸零")
    func showsAfterGraceAndThreeViews() {
        withTestDefaults { d in
            let installed = Date()
            primed(d, installedAt: installed, views: 2)
            let later = installed + 2 * day
            #expect(InterstitialPolicy.consumeShowOpportunity(now: later, defaults: d) == false)
            InterstitialPolicy.recordSettlementViewed(defaults: d)
            #expect(InterstitialPolicy.consumeShowOpportunity(now: later, defaults: d) == true)
            #expect(InterstitialPolicy.settlementViews(defaults: d) == 0)
        }
    }

    @Test("兩次顯示至少間隔 10 分鐘")
    func respectsMinimumInterval() {
        withTestDefaults { d in
            let installed = Date()
            primed(d, installedAt: installed, views: 3)
            let t0 = installed + 2 * day
            #expect(InterstitialPolicy.consumeShowOpportunity(now: t0, defaults: d) == true)
            primed(d, installedAt: installed, views: 3)
            #expect(InterstitialPolicy.consumeShowOpportunity(now: t0 + 5 * 60, defaults: d) == false)
            #expect(InterstitialPolicy.consumeShowOpportunity(now: t0 + 11 * 60, defaults: d) == true)
        }
    }

    @Test("UI 測試旗標一律拒絕")
    func uiTestingNeverShows() {
        withTestDefaults { d in
            d.set(true, forKey: "IS_UI_TESTING")
            primed(d, installedAt: Date() - 3 * day, views: 10)
            #expect(InterstitialPolicy.consumeShowOpportunity(defaults: d) == false)
        }
    }

    @Test("首次啟動時間只記一次")
    func firstLaunchIsSticky() {
        withTestDefaults { d in
            let first = Date() - 3 * day
            InterstitialPolicy.recordFirstLaunchIfNeeded(now: first, defaults: d)
            InterstitialPolicy.recordFirstLaunchIfNeeded(now: Date(), defaults: d)
            for _ in 0..<3 { InterstitialPolicy.recordSettlementViewed(defaults: d) }
            // 若第二次呼叫覆蓋了時間，這裡會因為還在 24 小時內而拒絕
            #expect(InterstitialPolicy.consumeShowOpportunity(defaults: d) == true)
        }
    }
}
