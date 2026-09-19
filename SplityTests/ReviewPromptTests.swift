import Testing
import Foundation
@testable import Splity

/// `ReviewPrompt` 的節流規則測試。
///
/// 為什麼要有這些測試：整條評分路徑（列表滑動 →「標記為結清」→ 系統評分面板）在
/// UI 測試裡一次都沒被走過，而且系統面板本來就不能在自動化測試裡驗。
/// 好在節流本身是純資料邏輯，用獨立的 UserDefaults suite 就能完整覆蓋。
///
/// 每個測試都用自己的 suite，絕不碰 `.standard`。
private func withTestDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "ReviewPromptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Suite("評分提示節流")
struct ReviewPromptTests {

    // MARK: - 門檻

    @Test("只結清一本帳還不會問")
    func belowThresholdDoesNotPrompt() {
        withTestDefaults { defaults in
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 1)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == false)
        }
    }

    @Test("結清兩本不同的帳就會問")
    func reachingThresholdPrompts() {
        withTestDefaults { defaults in
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 2)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == true)
        }
    }

    @Test("沒問過任何一次就不受間隔限制")
    func firstPromptIgnoresInterval() {
        withTestDefaults { defaults in
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            // 同一天連續兩次結算，第二次就該問——間隔門檻只在「問過之後」才生效。
            #expect(ReviewPrompt.consumeRequestOpportunity(now: Date(), version: "1.8.2", defaults: defaults) == true)
        }
    }

    // MARK: - 同一版只問一次

    @Test("同一個版本只問一次")
    func sameVersionPromptsOnce() {
        withTestDefaults { defaults in
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == true)

            // 同一版又結清了幾本也不再問
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == false)
        }
    }

    // MARK: - 取消結清 → 再結清不會灌水

    @Test("同一本帳反覆結清／取消結清只算一次")
    func resettlingSameGroupCountsOnce() {
        withTestDefaults { defaults in
            let groupId = UUID()
            // 結清 → 取消結清 → 再結清
            ReviewPrompt.recordSettlement(groupId: groupId, defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: groupId, defaults: defaults)
            ReviewPrompt.recordSettlement(groupId: groupId, defaults: defaults)

            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 1)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == false)

            // 換一本帳才算第二次
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 2)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == true)
        }
    }

    // MARK: - 問過之後的節流（次數差 + 120 天）

    @Test("問過之後：換了版本但還不到 120 天，不問")
    func newVersionTooSoonDoesNotPrompt() {
        withTestDefaults { defaults in
            let day0 = Date(timeIntervalSince1970: 1_700_000_000)
            for _ in 0..<2 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day0, version: "1.8.2", defaults: defaults) == true)

            // 又結清兩本、也換了版本，但只過了 119 天
            for _ in 0..<2 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            let day119 = day0.addingTimeInterval(119 * 24 * 60 * 60)
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day119, version: "1.8.3", defaults: defaults) == false)
        }
    }

    @Test("問過之後：過了 120 天但結算次數沒增加夠，不問")
    func notEnoughNewSettlementsDoesNotPrompt() {
        withTestDefaults { defaults in
            let day0 = Date(timeIntervalSince1970: 1_700_000_000)
            for _ in 0..<2 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day0, version: "1.8.2", defaults: defaults) == true)

            let day200 = day0.addingTimeInterval(200 * 24 * 60 * 60)
            // 只多結清一本（門檻是再多兩本）
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day200, version: "1.8.3", defaults: defaults) == false)

            // 補到兩本就過關
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day200, version: "1.8.3", defaults: defaults) == true)
        }
    }

    @Test("問過之後：新版本 + 120 天 + 多結清兩本，才會再問")
    func secondPromptNeedsAllThreeConditions() {
        withTestDefaults { defaults in
            let day0 = Date(timeIntervalSince1970: 1_700_000_000)
            for _ in 0..<2 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day0, version: "1.8.2", defaults: defaults) == true)

            for _ in 0..<2 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            let day121 = day0.addingTimeInterval(121 * 24 * 60 * 60)
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day121, version: "1.8.3", defaults: defaults) == true)

            // 第三次又要重新累積：同版本立刻再問一定是 false
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day121, version: "1.8.3", defaults: defaults) == false)
        }
    }

    @Test("每出一版就問一次的舊行為已經不存在")
    func doesNotPromptOnEveryRelease() {
        withTestDefaults { defaults in
            let day0 = Date(timeIntervalSince1970: 1_700_000_000)
            for _ in 0..<10 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.consumeRequestOpportunity(now: day0, version: "1.7.8", defaults: defaults) == true)

            // 1.8.0 / 1.8.1 在幾週內接連上架，每一版的第一次結算都不該再問
            for (days, version) in [(14, "1.8.0"), (35, "1.8.1")] {
                ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
                ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
                let now = day0.addingTimeInterval(Double(days) * 24 * 60 * 60)
                #expect(
                    ReviewPrompt.consumeRequestOpportunity(now: now, version: version, defaults: defaults) == false,
                    "\(version) 不該再問一次"
                )
            }
        }
    }

    // MARK: - 舊資料遷移

    @Test("舊版的整數計數不會被歸零")
    func legacyIntegerCountIsPreserved() {
        withTestDefaults { defaults in
            // 1.8.2 以前只存這個整數，改用 id 集合後集合是空的
            defaults.set(5, forKey: "ReviewPrompt_settlementCount")
            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 5)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == true)
        }
    }

    @Test("新集合超過舊整數之後以集合為準")
    func newSetOvertakesLegacyCount() {
        withTestDefaults { defaults in
            defaults.set(2, forKey: "ReviewPrompt_settlementCount")
            for _ in 0..<3 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.settlementCount(defaults: defaults) == 3)
        }
    }

    // MARK: - UI 測試旗標

    @Test("UI 測試時不跳評分面板")
    func uiTestingFlagSuppressesPrompt() {
        withTestDefaults { defaults in
            defaults.set(true, forKey: "IS_UI_TESTING")
            for _ in 0..<5 { ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults) }
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == false)
        }
    }

    // MARK: - 機會只在真的要問的時候才消費

    @Test("回傳 false 時不會寫掉這一版的詢問機會")
    func rejectedAttemptDoesNotBurnTheVersion() {
        withTestDefaults { defaults in
            // 次數不足 → 不問，也不該把版本記下來
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == false)
            #expect(defaults.string(forKey: "ReviewPrompt_promptedVersion") == nil)

            // 之後真的達標時仍問得出來
            ReviewPrompt.recordSettlement(groupId: UUID(), defaults: defaults)
            #expect(ReviewPrompt.consumeRequestOpportunity(version: "1.8.2", defaults: defaults) == true)
            #expect(defaults.string(forKey: "ReviewPrompt_promptedVersion") == "1.8.2")
        }
    }
}
