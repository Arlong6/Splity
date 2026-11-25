import XCTest

/// 花費分類：新增時依品項名稱自動選分類、存檔後帳本出現「分類統計」、統計畫面列出各類與未分類。
/// 中英文各走一次（英文確認沒有漏翻）。截圖設 SCREENSHOT_DIR 時另存成 PNG。
final class CategoryUITests: XCTestCase {

    private struct Copy {
        let language: String
        let skip, addExpense, itemName, amount, save, stats, transport, uncategorized, suggestion: String
        let title: String
    }

    private let zh = Copy(language: "zh-Hant", skip: "跳過", addExpense: "新增花費", itemName: "品項名稱",
                          amount: "金額", save: "儲存", stats: "分類統計", transport: "交通",
                          uncategorized: "未分類", suggestion: "分類不合用？告訴我們", title: "加油")
    private let en = Copy(language: "en", skip: "Skip", addExpense: "Add Expense", itemName: "Item Name",
                          amount: "Amount", save: "Save", stats: "Category Breakdown", transport: "Transport",
                          uncategorized: "Uncategorized", suggestion: "Categories not working for you? Tell us",
                          title: "taxi")

    @MainActor func testCategoryFlowChinese() throws { try runFlow(zh) }
    @MainActor func testCategoryFlowEnglish() throws { try runFlow(en) }

    @MainActor
    private func runFlow(_ c: Copy) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // 6 筆「花費i」：名稱猜不到分類，統計裡會是「未分類」
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults", "-SeedLargeSheet", "-SeedSheetCount", "6",
                               "-appLanguage", c.language, "-AppleLanguages", "(\(c.language))"]
        app.launch()

        if app.buttons[c.skip].waitForExistence(timeout: 8) {
            app.buttons[c.skip].tap()
        }
        let groupRow = app.staticTexts["PerfTest"].firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: UITestTimeout.appear))
        groupRow.tap()

        let add = app.buttons[c.addExpense].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: UITestTimeout.appear))
        add.tap()

        let picker = app.descendants(matching: .any)["categoryPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: UITestTimeout.appear))
        XCTAssertTrue(picker.label.contains(c.uncategorized), "還沒填名稱時應是未分類，實際：\(picker.label)")

        app.textFields[c.itemName].focusAndType("\(c.title)\n", c.itemName)
        XCTAssertTrue(picker.label.contains(c.transport), "輸入「\(c.title)」後應自動選交通，實際：\(picker.label)")
        app.textFields[c.amount].firstMatch.focusAndType("300", c.amount)
        shot("\(c.language)-01-edit-auto-category")

        let save = app.buttons[c.save].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let statsButton = app.buttons["categoryStatsButton"].firstMatch
        XCTAssertTrue(statsButton.waitForExistence(timeout: UITestTimeout.appear))
        XCTAssertTrue(app.staticTexts[c.title].exists)
        XCTAssertTrue(app.images[c.transport].exists, "列表上新花費前應有交通圖示（無障礙標籤為分類名）")
        shot("\(c.language)-02-list-with-icon")

        statsButton.tap()
        XCTAssertTrue(app.navigationBars[c.stats].waitForExistence(timeout: UITestTimeout.appear))
        // 統計清單每列合併成一個無障礙元素（「交通, NT$300, 27%」），用包含比對
        XCTAssertTrue(element(app, containing: c.transport).exists)
        XCTAssertTrue(element(app, containing: c.uncategorized).exists)
        XCTAssertTrue(app.buttons[c.suggestion].exists)
        shot("\(c.language)-03-stats")
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
