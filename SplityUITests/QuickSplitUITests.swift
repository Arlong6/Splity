import XCTest

/// 快速分帳完整流程：入口 → 新增（含指定應付）→ 儲存 → 紀錄清單 → 唯讀結果。
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

    /// 從帳目列表的入口列進入快速分帳
    private func openQuickSplit() {
        let entry = app.buttons["快速分帳（不用建群組）"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "找不到列表入口列")
        entry.tap()
    }

    private func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func type(_ identifier: String, row index: Int, _ text: String) {
        let field = app.textFields.matching(identifier: identifier).element(boundBy: index)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(identifier)[\(index)] 不存在")
        // 剛新增的列會由 @FocusState 主動把焦點搶回姓名欄，點一次不一定拿得到焦點
        for _ in 0..<3 where !hasFocus(field) {
            field.tap()
            _ = field.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(hasFocus(field), "\(identifier)[\(index)] 拿不到鍵盤焦點")
        field.typeText(text)
    }

    private func fillRow(_ index: Int, name: String, paid: String? = nil, share: String? = nil) {
        type("quickSplitName", row: index, name)
        if let paid { type("quickSplitPaid", row: index, paid) }
        if let share { type("quickSplitShare", row: index, share) }
    }

    private func dismissKeyboard() {
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
    }

    /// 小明先出 1000；小華指定應付 400；小美留空。
    /// 剩下 600 由小明與小美平分 → 各 300。小華還 400、小美還 300。
    func testQuickSplitWithAssignedShare() throws {
        skipOnboarding()
        screenshot("01-group-list")

        openQuickSplit()
        XCTAssertTrue(app.buttons["開始分帳"].waitForExistence(timeout: 5))
        screenshot("02-quick-split-empty")

        app.buttons["開始分帳"].tap()
        let titleField = app.textFields["例如：週五晚餐"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("週五晚餐")

        fillRow(0, name: "小明", paid: "1000")
        fillRow(1, name: "小華", share: "400")
        dismissKeyboard()
        app.buttons["新增成員"].tap()
        fillRow(2, name: "小美")
        dismissKeyboard()

        XCTAssertTrue(app.staticTexts["小華 → 小明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["小美 → 小明"].exists)
        screenshot("03-quick-split-edit")

        app.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["儲存"].waitForNonExistence(timeout: 5))

        let cell = app.cells.containing(.staticText, identifier: "週五晚餐").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        screenshot("04-quick-split-list")

        cell.tap()
        XCTAssertTrue(app.staticTexts["平均每人"].waitForExistence(timeout: 8))
        screenshot("05-quick-split-result")
        XCTAssertTrue(app.staticTexts["小華 轉給 小明"].exists)
        XCTAssertTrue(app.staticTexts["小美 轉給 小明"].exists)
    }

    /// 所有人都指定應付但合計不等於總額 → 結不平，儲存必須停用。
    func testUnbalancedAssignedSharesBlockSave() throws {
        skipOnboarding()
        openQuickSplit()
        app.buttons["開始分帳"].tap()
        XCTAssertTrue(app.textFields["例如：週五晚餐"].waitForExistence(timeout: 5))

        fillRow(0, name: "小明", paid: "1000", share: "300")
        fillRow(1, name: "小華", share: "300")
        dismissKeyboard()

        XCTAssertFalse(app.buttons["儲存"].isEnabled, "應付合計 600 ≠ 總額 1000，儲存應停用")
        screenshot("06-quick-split-unbalanced")

        // 新增第三人把差額補平 → 可以儲存
        app.buttons["新增成員"].tap()
        type("quickSplitName", row: 2, "小美")
        // 收起鍵盤再點應付欄，避免鍵盤工具列擋住最後一列
        dismissKeyboard()
        type("quickSplitShare", row: 2, "400")
        dismissKeyboard()
        XCTAssertTrue(app.buttons["儲存"].isEnabled, "應付合計補到 1000 後應可儲存")
    }
}
