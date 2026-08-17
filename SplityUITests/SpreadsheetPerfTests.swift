import XCTest

/// 表格開頁時間量測（500 筆 × 8 人，資料由 -SeedLargeSheet 啟動參數植入）。
/// 注意：修正前的視圖樹大到 XCUIElement 查詢會逾時，故不用元素等待，
/// 改「固定時間點截圖」由人工判讀表格何時出現；捲動用座標手勢避免元素快照。
final class SpreadsheetPerfTests: XCTestCase {

    @MainActor
    func testLargeSheetOpenTime() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-IS_UI_TESTING", "YES", "-UIResetDefaults", "-SeedLargeSheet"]
        app.launch()

        if app.buttons["跳過"].waitForExistence(timeout: 8) {
            app.buttons["跳過"].tap()
        }

        let groupRow = app.staticTexts["PerfTest"].firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 10), "seed 的 PerfTest 帳本沒出現")
        groupRow.tap()

        let sheetButton = app.buttons["表格"].firstMatch
        XCTAssertTrue(sheetButton.waitForExistence(timeout: 10))
        sheetButton.tap()
        let start = Date()

        // 進表格後不再做任何元素查詢（大樹快照會逾時），只按時間點拍照
        for checkpoint in [2.0, 5.0, 10.0, 20.0, 30.0] {
            Thread.sleep(until: start.addingTimeInterval(checkpoint))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = String(format: "t+%02.0fs", checkpoint)
            shot.lifetime = .keepAlways
            add(shot)
        }

        // 座標手勢捲動（上捲＋左捲），再拍一張驗凍結窗格對齊
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        Thread.sleep(forTimeInterval: 1)
        center.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        Thread.sleep(forTimeInterval: 2)
        let scrolled = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scrolled.name = "scrolled-frozen-panes"
        scrolled.lifetime = .keepAlways
        add(scrolled)
    }
}
