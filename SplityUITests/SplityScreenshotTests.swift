import XCTest

/// 專門用來產生 App Store 截圖的測試
/// 執行後截圖會存在 Derived Data 的 attachments 資料夾
final class SplityScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults"]
        app.launch()
    }

    // MARK: - Helpers

    private func screenshot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func waitMain() {
        XCTAssertTrue(app.buttons["新增帳目"].waitForExistence(timeout: 8))
    }

    private func skipOnboarding() {
        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }
        waitMain()
    }

    private func createGroup(_ name: String) {
        app.buttons["新增帳目"].tap()
        let alert = app.alerts["新增帳目"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields["帳目名稱"]
        field.tap()
        field.typeText(name)
        alert.buttons["建立"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    private func addMember(_ name: String) {
        app.buttons["新增成員"].tap()
        let alert = app.alerts["新增成員"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields["名字"]
        field.tap()
        field.typeText(name)
        alert.buttons["加入"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    private func addExpense(title: String, amount: String) {
        app.buttons["新增花費"].tap()
        XCTAssertTrue(app.textFields["品項名稱"].waitForExistence(timeout: 10))
        app.textFields["品項名稱"].tap()
        app.textFields["品項名稱"].typeText(title)
        app.textFields["金額"].tap()
        app.textFields["金額"].typeText(amount)
        let saveButton = app.buttons["儲存"]
        saveButton.tap()
        // Wait for the expense form to dismiss
        let predicate = NSPredicate(format: "exists == 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: saveButton)
        _ = XCTWaiter().wait(for: [expectation], timeout: 10)
    }

    // MARK: - Screenshot Tests

    func testScreenshot_01_Onboarding() {
        // App 已重置，應顯示 Onboarding
        XCTAssertTrue(app.staticTexts["建立群組"].waitForExistence(timeout: 8))
        screenshot("01_onboarding_page1")

        app.buttons["下一步"].tap()
        sleep(1)
        screenshot("02_onboarding_page2")

        app.buttons["下一步"].tap()
        sleep(1)
        screenshot("03_onboarding_page3")

        app.buttons["下一步"].tap()
        sleep(1)
        screenshot("04_onboarding_page4")
    }

    func testScreenshot_02_MainWithData() {
        skipOnboarding()

        // 建立兩個群組
        createGroup("🇯🇵 東京旅遊")
        createGroup("🍜 台北聚餐")

        sleep(1)
        screenshot("05_group_list")
    }

    func testScreenshot_03_GroupDetail() {
        skipOnboarding()
        createGroup("🇯🇵 東京旅遊")
        app.staticTexts["🇯🇵 東京旅遊"].tap()

        addMember("小明")
        addMember("小華")
        addMember("阿志")

        sleep(1)
        screenshot("06_group_detail_members")
    }

    func testScreenshot_04_GroupWithExpenses() {
        skipOnboarding()
        createGroup("🇯🇵 東京旅遊")
        app.staticTexts["🇯🇵 東京旅遊"].tap()

        addMember("小明")
        addMember("小華")

        // 選付款人（第一個 Picker）
        addExpense(title: "住宿", amount: "9600")

        sleep(1)
        screenshot("07_group_with_expenses")
    }

    func testScreenshot_05_Settlement() {
        skipOnboarding()
        createGroup("🇯🇵 東京旅遊")
        app.staticTexts["🇯🇵 東京旅遊"].tap()

        addMember("小明")
        addMember("小華")
        addExpense(title: "住宿", amount: "3000")

        let settlementBtn = app.buttons["結算"]
        if settlementBtn.waitForExistence(timeout: 3), settlementBtn.isEnabled {
            settlementBtn.tap()
            sleep(2)
            screenshot("08_settlement")
        }
    }

    func testScreenshot_06_Spreadsheet() {
        skipOnboarding()
        createGroup("🇯🇵 東京旅遊")
        app.staticTexts["🇯🇵 東京旅遊"].tap()

        addMember("小明")
        addMember("小華")
        addMember("阿志")

        addExpense(title: "機票", amount: "12000")
        addExpense(title: "住宿", amount: "9600")
        addExpense(title: "交通", amount: "3200")
        addExpense(title: "餐廳", amount: "2400")

        let spreadsheetBtn = app.buttons["表格"]
        XCTAssertTrue(spreadsheetBtn.waitForExistence(timeout: 3))
        XCTAssertTrue(spreadsheetBtn.isEnabled)
        spreadsheetBtn.tap()

        sleep(2)
        screenshot("09_spreadsheet")
    }
}
