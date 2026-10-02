import XCTest

/// 廣告流程的煙霧測試：真的初始化 AdMob（用 Google 測試 ID），走 ATT 對話框、等橫幅出現、看「關於」頁的移除廣告區塊。
///
/// 刻意**不帶** `-IS_UI_TESTING`：帶了 `AdFreeStatus` 會判成測試環境而完全不載廣告。
/// 需要網路（Firebase 匿名登入、AdMob 測試廣告）。截圖同時附在 XCTest 結果與 `SHOT_DIR`（環境變數）目錄。
final class AdsSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UIResetDefaults",
            "-hasSeenOnboarding", "YES",
            "-appLanguage", "zh-Hant", "-AppleLanguages", "(zh-Hant)",
        ]
        app.launch()
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }

    func testAttPromptBannerAndRemoveAdsSection() throws {
        // 1. ATT 對話框（系統 alert 屬於 SpringBoard）
        let attAlert = springboard.alerts.firstMatch
        XCTAssertTrue(attAlert.waitForExistence(timeout: 30), "ATT 對話框沒有出現")
        screenshot("splity_01_att_prompt")
        let allow = attAlert.buttons.matching(NSPredicate(format: "label CONTAINS[c] '允許' OR label CONTAINS[c] 'Allow'")).firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()

        // 2. 橫幅：AdBanner 的 accessibilityLabel 是「廣告」，SDK 初始化 + 測試廣告載入要幾秒
        let banner = app.descendants(matching: .any).matching(NSPredicate(format: "label == '廣告'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 60), "列表底部沒有出現橫幅")
        // 容器出現不代表廣告畫好了；等 Google 測試廣告的標記進到階層再截圖。
        // 測試素材文案每次不同（有時是 "You've loaded a test ad"，有時是 mediation 假廣告），
        // 但都會帶 "Test mode" 標籤。
        let testAd = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'test mode' OR label CONTAINS[c] 'test ad'"))
            .firstMatch
        XCTAssertTrue(testAd.waitForExistence(timeout: 60), "橫幅沒有載入測試廣告")
        screenshot("splity_02_banner")

        // 3. 橫幅上方的「移除廣告」直接打開關於頁（App Review 曾找不到列表最底的入口）
        let bannerLink = app.buttons["bannerRemoveAds"]
        XCTAssertTrue(bannerLink.waitForExistence(timeout: 10), "橫幅上方沒有移除廣告入口")
        bannerLink.tap()
        let restore = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '還原購買'")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "關於頁沒有還原購買")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '移除廣告'")).firstMatch.exists)
        screenshot("splity_03_about_remove_ads")
    }
}
