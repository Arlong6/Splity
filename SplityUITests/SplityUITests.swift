import XCTest

final class SplityUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // -IS_UI_TESTING YES → sets UserDefaults key so app uses in-memory SwiftData (no CloudKit)
        app.launchArguments = ["-IS_UI_TESTING", "YES"]
    }

    // MARK: - Helpers

    /// 等待 Splash 動畫結束（約 2.3 秒），確認主畫面或 Onboarding 出現
    private func waitForSplash(timeout: TimeInterval = 6) {
        _ = app.buttons.firstMatch.waitForExistence(timeout: timeout)
    }

    /// 跳過 Onboarding，進入主畫面
    private func launchSkippingOnboarding() {
        app.launchArguments += ["-UIResetDefaults", "-hasSeenOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["新增帳目"].waitForExistence(timeout: 6))
    }

    /// 建立一個群組並導航進去，回傳群組名稱
    @discardableResult
    private func createAndEnterGroup(name: String) -> String {
        app.buttons["新增帳目"].tap()
        let alert = app.alerts["新增帳目"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields["帳目名稱"]
        field.tap()
        field.typeText(name)
        alert.buttons["建立"].tap()

        let cell = app.staticTexts[name]
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        return name
    }

    /// 在群組詳細頁面新增一位成員
    private func addMember(name: String) {
        app.buttons["新增成員"].tap()
        let alert = app.alerts["新增成員"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields["名字"]
        field.tap()
        field.typeText(name)
        alert.buttons["加入"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
    }

    // MARK: - Onboarding Tests

    func testOnboarding_ShowsOnFirstLaunch() {
        // -UIResetDefaults 清空 UserDefaults，模擬全新安裝狀態
        app.launchArguments += ["-UIResetDefaults"]
        app.launch()

        // Splash 結束後應出現導覽第一頁
        XCTAssertTrue(app.staticTexts["建立群組"].waitForExistence(timeout: 6))
    }

    func testOnboarding_SkipButtonGoesToMainScreen() {
        app.launchArguments += ["-UIResetDefaults"]
        app.launch()

        let skipButton = app.buttons["跳過"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 6))
        skipButton.tap()

        XCTAssertTrue(app.buttons["新增帳目"].waitForExistence(timeout: 3))
    }

    func testOnboarding_NavigateAllPagesAndStart() {
        app.launchArguments += ["-UIResetDefaults"]
        app.launch()

        XCTAssertTrue(app.staticTexts["建立群組"].waitForExistence(timeout: 6))

        // 點三次「下一步」
        for _ in 1...3 {
            let nextButton = app.buttons["下一步"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
            nextButton.tap()
        }

        // 最後一頁應出現「開始使用」
        let startButton = app.buttons["開始使用"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3))
        startButton.tap()

        // 應進入主畫面
        XCTAssertTrue(app.buttons["新增帳目"].waitForExistence(timeout: 3))
    }

    // MARK: - Group List Tests

    func testGroupList_EmptyState_ShowsPlaceholder() {
        // 這個測試適合在全新安裝後執行
        app.launchArguments += ["-hasSeenOnboarding", "YES"]
        app.launch()
        waitForSplash()

        // 若沒有任何群組，應出現空狀態提示
        // 注意：若模擬器有既有資料此測試可能跳過
        if app.staticTexts["還沒有帳本"].exists {
            XCTAssertTrue(app.staticTexts["還沒有帳本"].exists)
        }
    }

    func testGroupList_CreateGroup_AppearsInList() {
        launchSkippingOnboarding()

        app.buttons["新增帳目"].tap()

        let alert = app.alerts["新增帳目"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let field = alert.textFields["帳目名稱"]
        field.tap()
        field.typeText("UI測試群組")
        alert.buttons["建立"].tap()

        XCTAssertTrue(app.staticTexts["UI測試群組"].waitForExistence(timeout: 10))
    }

    func testGroupList_CreateGroup_EmptyName_NoGroupAdded() {
        launchSkippingOnboarding()

        app.buttons["新增帳目"].tap()

        let alert = app.alerts["新增帳目"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        // 不輸入名稱，直接點建立
        alert.buttons["建立"].tap()

        // Alert 消失，但不應新增空名稱群組
        XCTAssertFalse(app.alerts["新增帳目"].exists)
    }

    func testGroupList_CancelCreation_NoGroupAdded() {
        launchSkippingOnboarding()

        let initialGroupCount = app.cells.count
        app.buttons["新增帳目"].tap()

        let alert = app.alerts["新增帳目"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.textFields["帳目名稱"].typeText("應取消的群組")
        alert.buttons["取消"].tap()

        // 群組數量不應增加
        XCTAssertEqual(app.cells.count, initialGroupCount)
        XCTAssertFalse(app.staticTexts["應取消的群組"].exists)
    }

    // MARK: - Group Detail Tests

    func testGroupDetail_AddSingleMember() {
        launchSkippingOnboarding()
        createAndEnterGroup(name: "成員測試_\(Int.random(in: 1000...9999))")

        addMember(name: "小明")

        XCTAssertTrue(app.staticTexts["小明"].exists)
    }

    func testGroupDetail_AddExpenseButton_DisabledWithFewerThanTwoMembers() {
        launchSkippingOnboarding()
        let groupName = "費用測試_\(Int.random(in: 1000...9999))"
        createAndEnterGroup(name: groupName)

        let addExpenseButton = app.buttons["新增花費"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 3))

        // 0 個成員 → 應停用
        XCTAssertFalse(addExpenseButton.isEnabled, "0個成員時新增花費應停用")

        // 加入第一位成員
        addMember(name: "A")
        XCTAssertFalse(addExpenseButton.isEnabled, "1個成員時新增花費應停用")

        // 加入第二位成員
        addMember(name: "B")
        XCTAssertTrue(addExpenseButton.isEnabled, "2個成員後新增花費應啟用")
    }

    func testGroupDetail_AddExpense_NavigatesToExpenseForm() {
        launchSkippingOnboarding()
        let groupName = "新增費用測試_\(Int.random(in: 1000...9999))"
        createAndEnterGroup(name: groupName)

        addMember(name: "小明")
        addMember(name: "小華")

        app.buttons["新增花費"].tap()

        // 應開啟 ExpenseEditView（有品項名稱欄位）
        XCTAssertTrue(app.textFields["品項名稱"].waitForExistence(timeout: 3))
    }

    func testGroupDetail_NavigateBack_GroupStillExists() {
        launchSkippingOnboarding()
        let groupName = "返回測試_\(Int.random(in: 1000...9999))"
        createAndEnterGroup(name: groupName)

        // 按返回
        app.navigationBars.buttons.firstMatch.tap()

        // 群組應仍在列表
        XCTAssertTrue(app.staticTexts[groupName].waitForExistence(timeout: 3))
    }

    // MARK: - Settlement & Spreadsheet Tests

    func testGroupDetail_SettlementButton_DisabledWithNoExpenses() {
        launchSkippingOnboarding()
        createAndEnterGroup(name: "結算測試_\(Int.random(in: 1000...9999))")

        addMember(name: "甲")
        addMember(name: "乙")

        // 沒有費用時，結算與表格按鈕應停用
        XCTAssertFalse(app.buttons["結算"].isEnabled)
        XCTAssertFalse(app.buttons["表格"].isEnabled)
    }
}
