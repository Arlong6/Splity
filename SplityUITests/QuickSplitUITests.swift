import XCTest

/// 快速分帳完整流程：入口 → 新增 → 儲存 → 紀錄清單 → 唯讀結果。
final class QuickSplitUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults"]
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

    private func skipOnboarding() {
        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }
        XCTAssertTrue(app.buttons["新增帳目"].waitForExistence(timeout: 8))
    }

    private func fillRow(_ index: Int, name: String, paid: String?) {
        let nameField = app.textFields.matching(identifier: "quickSplitName").element(boundBy: index)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        if let paid {
            let paidField = app.textFields.matching(identifier: "quickSplitPaid").element(boundBy: index)
            paidField.tap()
            paidField.typeText(paid)
        }
    }

    func testQuickSplitFlow() throws {
        skipOnboarding()
        screenshot("01-group-list")

        app.buttons["快速分帳"].tap()
        XCTAssertTrue(app.buttons["開始分帳"].waitForExistence(timeout: 5))
        screenshot("02-quick-split-empty")

        app.buttons["開始分帳"].tap()
        let titleField = app.textFields["例如：週五晚餐"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("週五晚餐")

        fillRow(0, name: "小明", paid: "1000")
        fillRow(1, name: "小華", paid: nil)
        // 鍵盤會遮住「新增成員」，先收起來（真人會捲動）
        app.buttons["完成"].tap()
        app.buttons["新增成員"].tap()
        fillRow(2, name: "小美", paid: nil)

        // 即時結果：每人應付 334（TWD 無條件進位），兩筆轉帳
        XCTAssertTrue(app.staticTexts["小華 → 小明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["小美 → 小明"].exists)
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
        screenshot("03-quick-split-edit")

        app.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["儲存"].waitForNonExistence(timeout: 5))

        // 紀錄清單
        XCTAssertTrue(app.staticTexts["週五晚餐"].waitForExistence(timeout: 5))
        screenshot("04-quick-split-list")

        let cell = app.cells.containing(.staticText, identifier: "週五晚餐").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        var navigated = app.staticTexts["每人應付"].waitForExistence(timeout: 8)
        var note = "first tap: \(navigated)"
        if !navigated {
            cell.tap()
            navigated = app.staticTexts["每人應付"].waitForExistence(timeout: 5)
            note += "; second tap: \(navigated); cell=\(cell.debugDescription.prefix(600))"
        }
        screenshot("05-quick-split-result")
        XCTAssertTrue(navigated, note)
        XCTAssertTrue(app.staticTexts["小華 轉給 小明"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["小美 轉給 小明"].exists)
    }
}
