import XCTest

/// 小帳本（整張表在第一屏內）開表後不捲動就要完整畫出來，包含「有人先墊」區塊。
/// 曾回報：該區塊一開始是黑的，要往下滑才出現。
final class SpreadsheetSmallSheetTests: XCTestCase {

    @MainActor
    func testSmallSheetRendersWithoutScrolling() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults", "-SeedLargeSheet", "-SeedSheetCount", "6",
                               "-appLanguage", "zh-Hant", "-AppleLanguages", "(zh-Hant)"]
        app.launch()

        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }
        let groupRow = app.staticTexts["PerfTest"].firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 10))
        groupRow.tap()
        let sheetButton = app.buttons["表格"].firstMatch
        XCTAssertTrue(sheetButton.waitForExistence(timeout: 10))
        sheetButton.tap()

        // 不捲動：最後一列「應付/應收」與「有人先墊」區塊的列都應該已經在畫面上
        XCTAssertTrue(app.staticTexts["應付/應收"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        attach("01-no-scroll")
        // 「有人先墊」每列只有付款人有金額、其他人是 0（6 列 × 多人）。整張表其他地方最多一個 "0"，
        // 所以不捲動就看得到一堆 0，才代表這段真的畫出來了。
        let zeros = app.staticTexts.matching(NSPredicate(format: "label == '0'")).count
        XCTAssertGreaterThanOrEqual(zeros, 10, "「有人先墊」區塊沒有畫出來（只找到 \(zeros) 個 0）")

        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        sleep(1)
        attach("02-after-small-scroll")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
