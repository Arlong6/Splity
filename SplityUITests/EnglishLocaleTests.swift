import XCTest

/// 以英文 locale 走過主要畫面，確認沒有殘留中文。
/// 命令列 xcodebuild 不會把新字串寫回 Localizable.xcstrings，漏翻很容易悄悄發生。
final class EnglishLocaleTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // app 有自己的語言設定（appLanguage），會蓋掉系統語系，
        // 所以要用它來切英文，這也是使用者實際切換的方式。
        app.launchArguments = [
            "-IS_UI_TESTING", "YES", "-UIResetDefaults",
            "-appLanguage", "en",
        ]
        app.launch()
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// 畫面上所有靜態文字與按鈕標籤都不該含中日韓表意文字。
    /// 使用者自己輸入的內容（群組名、成員名）不在此列，測試只用英數字命名。
    private func assertNoChinese(_ context: String) {
        // 導覽列的返回鈕等系統介面只跟裝置語系，不跟 app 內建的語言切換
        // （切換時會一併寫入 AppleLanguages，但要下次啟動才生效），故排除。
        let navBarLabels = Set(app.navigationBars.buttons.allElementsBoundByIndex.map(\.label))
        let texts = (app.staticTexts.allElementsBoundByIndex.map(\.label)
            + app.buttons.allElementsBoundByIndex.map(\.label))
            .filter { !navBarLabels.contains($0) }
        let offenders = texts.filter { label in
            label.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
        }
        if !offenders.isEmpty {
            XCTFail("\(context) 出現未翻譯的中文：" + Set(offenders).sorted().joined(separator: " | "))
        }
    }

    func testEnglishLocaleHasNoChineseText() throws {
        // Onboarding
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        screenshot("en-01-onboarding")
        assertNoChinese("Onboarding")

        while app.buttons["Next"].exists { app.buttons["Next"].tap() }
        screenshot("en-02-onboarding-last")
        assertNoChinese("Onboarding 最後一頁")
        app.buttons["Get Started"].tap()

        // 帳目列表
        XCTAssertTrue(app.buttons["New Group"].waitForExistence(timeout: 8))
        screenshot("en-03-group-list")
        assertNoChinese("帳目列表")

        // 快速分帳
        app.buttons["Quick Split (No Group Needed)"].tap()
        XCTAssertTrue(app.buttons["Start Splitting"].waitForExistence(timeout: 5))
        screenshot("en-04-quick-split-empty")
        assertNoChinese("快速分帳空狀態")

        app.buttons["Start Splitting"].tap()
        XCTAssertTrue(app.staticTexts["Result"].waitForExistence(timeout: 5))
        screenshot("en-05-quick-split-edit")
        assertNoChinese("快速分帳新增頁")
    }
}
