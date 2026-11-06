import XCTest

/// 幣別選單最上方要有「最近使用」：人在國外記帳時，不必每筆都重找當地幣別。
final class RecentCurrenciesUITests: XCTestCase {

    @MainActor
    func testPickedCurrencyListedFirstNextTime() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults", "-SeedLargeSheet", "-SeedSheetCount", "6",
                               "-appLanguage", "zh-Hant", "-AppleLanguages", "(zh-Hant)"]
        app.launch()

        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }
        let groupRow = app.staticTexts["PerfTest"].firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: UITestTimeout.appear))
        groupRow.tap()
        let addExpense = app.buttons["新增花費"].firstMatch
        XCTAssertTrue(addExpense.waitForExistence(timeout: UITestTimeout.appear))
        addExpense.tap()

        let currency = app.buttons["currencyButton"].firstMatch
        XCTAssertTrue(currency.waitForExistence(timeout: UITestTimeout.appear))
        currency.tap()

        // 第一次打開：還沒選過，不該有「最近使用」
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: UITestTimeout.appear))
        XCTAssertFalse(app.staticTexts["最近使用"].exists)

        search.focusAndType("NZD", "搜尋幣別")
        let nzd = app.staticTexts["NZD"].firstMatch
        XCTAssertTrue(nzd.waitForExistence(timeout: UITestTimeout.appear))
        nzd.tap()

        XCTAssertTrue(currency.waitForExistence(timeout: UITestTimeout.appear))
        currency.tap()

        // 第二次打開：「最近使用」在最上面，第一列是 NZD
        let header = app.staticTexts["最近使用"]
        XCTAssertTrue(header.waitForExistence(timeout: UITestTimeout.appear))
        let firstCode = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["NZD", "TWD", "USD"])).firstMatch
        XCTAssertEqual(firstCode.label, "NZD")
        XCTAssertLessThan(header.frame.minY, firstCode.frame.minY)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "recent-currencies"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
