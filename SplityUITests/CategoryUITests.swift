import XCTest

/// 花費分類：新增時依品項名稱自動選分類、存檔後帳本出現「分類統計」、統計畫面列出各類與未分類。
/// 中英文各走一次（英文確認沒有漏翻）。截圖設 SCREENSHOT_DIR 時另存成 PNG。
final class CategoryUITests: XCTestCase {

    private struct Copy {
        let language: String
        let skip, addExpense, itemName, amount, save, stats, transport, uncategorized, suggestion, done: String
        let title: String
    }

    private let zh = Copy(language: "zh-Hant", skip: "跳過", addExpense: "新增花費", itemName: "品項名稱",
                          amount: "金額", save: "儲存", stats: "分類統計", transport: "交通",
                          uncategorized: "未分類", suggestion: "分類不合用？告訴我們", done: "完成", title: "加油")
    private let en = Copy(language: "en", skip: "Skip", addExpense: "Add Expense", itemName: "Item Name",
                          amount: "Amount", save: "Save", stats: "Category Breakdown", transport: "Transport",
                          uncategorized: "Uncategorized", suggestion: "Categories not working for you? Tell us",
                          done: "Done", title: "taxi")

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
        XCTAssertTrue(pickerText(picker).contains(c.uncategorized), "還沒填名稱時應是未分類，實際：\(pickerText(picker))")

        // 表單剛滑上來時打字可能落空（焦點到了、字卻沒進去），確認欄位真的有字再往下
        let nameField = app.textFields[c.itemName].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: UITestTimeout.appear))
        for _ in 0..<3 where (nameField.value as? String) != c.title {
            nameField.focusAndType(c.title, c.itemName)
            _ = nameField.waitForExistence(timeout: 1)
        }
        XCTAssertEqual(nameField.value as? String, c.title, "品項名稱沒有打進去")
        nameField.typeText("\n")
        // 選到有圖示的分類後，選單的值不一定還在 label／value 裡，改找畫面上的文字
        XCTAssertTrue(element(app, containing: c.transport).waitForExistence(timeout: UITestTimeout.appear),
                      "輸入「\(c.title)」後應自動選交通")
        app.textFields[c.amount].firstMatch.focusAndType("300", c.amount)
        shot("\(c.language)-01-edit-auto-category")

        let save = app.buttons[c.save].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: UITestTimeout.disappear))

        // 統計入口在花費紀錄區最上方，8 位成員下面；List 只放畫面內的列，要捲下去
        let statsButton = app.buttons["categoryStatsButton"].firstMatch
        for _ in 0..<6 where !(statsButton.exists && statsButton.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(statsButton.waitForExistence(timeout: UITestTimeout.appear), "找不到分類統計入口")
        // 入口剛露出來時，下面的花費列還在畫面外，再捲一次
        app.swipeUp()
        shot("\(c.language)-02-list-with-icon")
        // 花費列整列是一個可點元素，文字與圖示的無障礙標籤（分類名）合在它的 label 裡
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", c.title, c.transport)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: UITestTimeout.appear),
                      "列表上新花費那一列應帶交通圖示（無障礙標籤為分類名）")

        for _ in 0..<3 where !statsButton.isHittable { app.swipeDown() }
        statsButton.tap()
        XCTAssertTrue(app.navigationBars[c.stats].waitForExistence(timeout: UITestTimeout.appear))
        // 統計清單每列合併成一個無障礙元素（「交通, NT$300, 27%」），用包含比對
        XCTAssertTrue(element(app, containing: c.transport).exists)
        XCTAssertTrue(element(app, containing: c.uncategorized).exists)
        XCTAssertTrue(app.buttons[c.suggestion].exists)
        shot("\(c.language)-03-stats")

        // 改回未分類：打開剛才那筆，分類選「未分類」存檔，列表那一列不再帶交通圖示
        app.navigationBars[c.stats].buttons[c.done].tap()
        XCTAssertTrue(row.waitForExistence(timeout: UITestTimeout.appear))
        row.tap()
        let editPicker = app.descendants(matching: .any)["categoryPicker"].firstMatch
        XCTAssertTrue(editPicker.waitForExistence(timeout: UITestTimeout.appear))
        editPicker.tap()
        let option = app.buttons[c.uncategorized].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: UITestTimeout.appear), "選單裡找不到未分類")
        option.tap()
        let saveEdit = app.buttons[c.save].firstMatch
        XCTAssertTrue(saveEdit.waitForExistence(timeout: UITestTimeout.appear))
        saveEdit.tap()
        XCTAssertTrue(saveEdit.waitForNonExistence(timeout: UITestTimeout.disappear))
        XCTAssertTrue(row.waitForNonExistence(timeout: UITestTimeout.disappear),
                      "改回未分類後，那一列不應再帶交通的無障礙標籤")
        let plainRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", c.title, "300")).firstMatch
        XCTAssertTrue(plainRow.exists, "那筆花費本身應該還在")
        shot("\(c.language)-04-back-to-uncategorized")
    }

    /// 選單的標題在 label、目前選的值在 value（依系統版本可能合在 label 裡），兩個一起看。
    private func pickerText(_ picker: XCUIElement) -> String {
        "\(picker.label) \((picker.value as? String) ?? "")"
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
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
