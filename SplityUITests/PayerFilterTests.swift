import XCTest

/// 帳本頁「花費紀錄」的付款人篩選：預設全選；取消勾選某人後，他先付的花費從列表消失、
/// 標題列總額只算剩下的；點「全部」恢復。
final class PayerFilterTests: XCTestCase {

    @MainActor
    func testFilterExpensesByPayer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // 6 筆：花費i 由 成員(i%8+1) 先付、金額 100+10i → 最新的花費6 在列表最上面，是成員7 付的 160，總額 810
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults", "-SeedLargeSheet", "-SeedSheetCount", "6",
                               "-appLanguage", "zh-Hant", "-AppleLanguages", "(zh-Hant)"]
        app.launch()

        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }
        let groupRow = app.staticTexts["PerfTest"].firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 10))
        groupRow.tap()

        // iOS 26 的 Menu 不一定是 .button 類型，不限定類型找
        let filter = app.descendants(matching: .any)["payerFilter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.label.contains("全部"), "預設應該是全選，實際：\(filter.label)")
        XCTAssertTrue(app.staticTexts["花費6"].exists)
        XCTAssertTrue(totalText(app, contains: "810").exists)
        attach("00-default")

        filter.tap()
        let member7 = menuItem(app, "成員7")
        XCTAssertTrue(member7.waitForExistence(timeout: 5))
        attach("01-menu-open")
        member7.tap()
        attach("02-menu-after-uncheck")
        // 選單設定成點了不關，點選單外面收起來
        app.navigationBars.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["花費6"].waitForNonExistence(timeout: 5), "成員7 先付的花費6 應該被藏起來")
        XCTAssertTrue(app.staticTexts["花費5"].exists)
        XCTAssertTrue(filter.label.contains("7"), "篩選中應顯示 7 人，實際：\(filter.label)")
        XCTAssertTrue(totalText(app, contains: "650").exists, "總額應該只算剩下的 650")
        attach("03-filtered")

        filter.tap()
        let all = menuItem(app, "全部")
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        app.navigationBars.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["花費6"].waitForExistence(timeout: 5), "點「全部」後花費6 應該回來")
        XCTAssertTrue(filter.label.contains("全部"))
        XCTAssertTrue(totalText(app, contains: "810").exists)
        attach("04-restored")
    }

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        // 選單裡的 Toggle／Button 類型依系統版本而異；列表上也有「成員7」文字，所以排除 staticText
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND elementType != %d", label, XCUIElement.ElementType.staticText.rawValue))
            .firstMatch
    }

    private func totalText(_ app: XCUIApplication, contains amount: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", amount)).firstMatch
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
