import XCTest

/// 借這個 UITest target 驅動另一個 App（Nihongo Manabi）做廣告流程煙霧測試。
/// XCUITest 可以用 bundle id 啟動任何已安裝在同一台模擬器的 App。
/// 前置：Nihongo 已安裝、AsyncStorage manifest 已寫入「onboarding 完成 + AI 對話額度用完」。
/// 這個檔案不屬於 Splity 產品，驗證完可刪；預設不在 CI 跑（沒有 CI）。
final class NihongoAdsSmokeTests: XCTestCase {
    private let nihongo = XCUIApplication(bundleIdentifier: "com.nihongomanabi.app")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func anyElement(_ app: XCUIApplication, labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testRewardedAdOfferedWhenQuotaExhausted() throws {
        continueAfterFailure = true
        nihongo.launch()

        // 1. ATT（onboarding 已完成 → AppInner 掛載後 initAds → ATT）
        let attAlert = springboard.alerts.firstMatch
        XCTAssertTrue(attAlert.waitForExistence(timeout: 40), "ATT 對話框沒有出現")
        screenshot("nihongo_01_att_prompt")
        let allow = attAlert.buttons.matching(NSPredicate(format: "label CONTAINS[c] '允許' OR label CONTAINS[c] 'Allow'")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // 2. 首頁 → AI 會話練習
        let aiCard = anyElement(nihongo, labelContains: "AI 會話練習")
        XCTAssertTrue(aiCard.waitForExistence(timeout: 20), "首頁沒有 AI 會話練習入口")
        aiCard.tap()

        // 3. 額度用完橫幅 + 看廣告按鈕
        XCTAssertTrue(anyElement(nihongo, labelContains: "今日額度用完").waitForExistence(timeout: 15), "沒有顯示額度用完")
        let watchAd = anyElement(nihongo, labelContains: "看廣告多 1 次")
        XCTAssertTrue(watchAd.waitForExistence(timeout: 10), "沒有出現「看廣告多 1 次」按鈕")
        screenshot("nihongo_02_quota_exhausted_watch_ad")

        // 4. 點下去 → 測試激勵影片（全螢幕）。冷啟動第一次載入可能要 20 秒以上。
        watchAd.tap()
        let close = nihongo.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'close' OR label CONTAINS[c] '關閉'"))
            .firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 60), "60 秒內廣告沒有出現")
        sleep(3)
        screenshot("nihongo_03_rewarded_ad_playing")

        // 5. 影片一開始就有關閉鈕，但提早關會沒有獎勵（這是正確行為，上一輪就是這樣失敗的）。
        //    Google 測試影片約 30 秒，等 45 秒讓它播完再關。
        sleep(45)
        screenshot("nihongo_03b_rewarded_ad_finished")
        // 播完後階層裡有兩個「close」：外層原生的 'Close Advertisement'（此時 Disabled）與
        // 素材結算頁裡 enabled 的 'Close'。挑 enabled 的那個點。
        let enabledClose = nihongo.buttons
            .matching(NSPredicate(format: "(label CONTAINS[c] 'close' OR label CONTAINS[c] '關閉') AND enabled == true"))
            .firstMatch
        if enabledClose.waitForExistence(timeout: 5) {
            enabledClose.tap()
        } else if close.exists {
            close.tap()
        }
        // 有些版本關閉時會再問一次「要放棄獎勵嗎」；影片已播完的話不會出現，出現就選繼續看
        let resume = nihongo.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'resume'")).firstMatch
        if resume.waitForExistence(timeout: 3) { resume.tap(); sleep(20); if close.exists { close.tap() } }

        let remaining = anyElement(nihongo, labelContains: "今日剩餘")
        XCTAssertTrue(remaining.waitForExistence(timeout: 20), "看完廣告後額度沒有 +1（沒出現『今日剩餘』）")
        screenshot("nihongo_04_after_reward")
    }
}
