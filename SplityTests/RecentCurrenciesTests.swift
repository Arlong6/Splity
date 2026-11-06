import Testing
import Foundation
@testable import Splity

/// 每個測試用自己的 UserDefaults suite，不碰到本機真正的紀錄。
private func withTestDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "RecentCurrenciesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Suite("幣別選單的最近使用")
struct RecentCurrenciesTests {

    @Test("沒選過就是空的，選單不出現這區")
    func emptyByDefault() {
        withTestDefaults { d in
            #expect(RecentCurrencies.list(defaults: d).isEmpty)
        }
    }

    @Test("新選的排最前面")
    func newestFirst() {
        withTestDefaults { d in
            RecentCurrencies.record("NZD", defaults: d)
            RecentCurrencies.record("JPY", defaults: d)
            #expect(RecentCurrencies.list(defaults: d) == ["JPY", "NZD"])
        }
    }

    @Test("再選一次已在清單裡的幣別：移到最前面，不重複")
    func reselectMovesToFront() {
        withTestDefaults { d in
            for code in ["NZD", "JPY", "USD", "NZD"] { RecentCurrencies.record(code, defaults: d) }
            #expect(RecentCurrencies.list(defaults: d) == ["NZD", "USD", "JPY"])
        }
    }

    @Test("最多留 3 個，丟掉最舊的")
    func capsAtThree() {
        withTestDefaults { d in
            for code in ["NZD", "JPY", "USD", "EUR"] { RecentCurrencies.record(code, defaults: d) }
            #expect(RecentCurrencies.list(defaults: d) == ["EUR", "USD", "JPY"])
        }
    }

    @Test("已不支援的幣別不顯示")
    func dropsUnsupportedCodes() {
        withTestDefaults { d in
            d.set(["XXX", "NZD"], forKey: "recentCurrencies")
            #expect(RecentCurrencies.list(defaults: d) == ["NZD"])
        }
    }
}
