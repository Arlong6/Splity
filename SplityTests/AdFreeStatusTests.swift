import Testing
import Foundation
@testable import Splity

@Suite("免廣告判定")
struct AdFreeStatusTests {
    @Test("三個來源任一為真即免廣告", arguments: [
        (false, false, false, false),
        (true, false, false, true),
        (false, true, false, true),
        (false, false, true, true),
        (true, true, true, true),
    ])
    func resolve(isTest: Bool, purchased: Bool, remote: Bool, expected: Bool) {
        #expect(AdFreeStatus.resolve(isTest: isTest, purchased: purchased, remote: remote) == expected)
    }

    @Test("啟動時沿用上次快取")
    func loadsCachedFlags() {
        let name = "AdFreeStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "AdFree_remote")
        let status = AdFreeStatus(defaults: defaults)
        #expect(status.isRemoteAdFree == true)
        #expect(status.isPurchased == false)
        #expect(status.isAdFree == true)
    }

    @Test("單元測試環境本身就是免廣告")
    func testEnvironmentIsAdFree() {
        #expect(AdFreeStatus.isTestEnvironment == true)
    }
}
