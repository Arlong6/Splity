import XCTest

/// 新增花費時「儲存」灰掉要說明原因。曾有使用者回報「無法再增加新的花費」，
/// 卻看不出是哪個欄位擋住。
final class SaveBlockerReasonTests: XCTestCase {

    @MainActor
    func testReasonShownUntilFormIsComplete() throws {
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
        let add = app.buttons["新增花費"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: UITestTimeout.appear))
        add.tap()

        let save = app.buttons["儲存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: UITestTimeout.appear))
        XCTAssertFalse(save.isEnabled)

        // 原因在表單最底下；Form 只把畫面內的列放進 accessibility tree，要先捲下去
        // Label 的圖示（「資訊」）也帶同一個 identifier，只抓文字
        let reason = app.staticTexts.matching(identifier: "saveBlockerReason").firstMatch
        scrollUntilVisible(reason, in: app)
        XCTAssertTrue(reason.label.contains("請輸入品項名稱"), "實際：\(reason.label)")
        attach("00-missing-title")

        app.swipeDown(); app.swipeDown()
        // 名稱用一般鍵盤，送出換行就收起來；數字鍵盤沒有「完成」鍵、會蓋住下面的開關，所以金額最後填
        app.textFields["品項名稱"].focusAndType("晚餐\n", "品項名稱")
        scrollUntilVisible(reason, in: app)
        XCTAssertTrue(reason.label.contains("請輸入大於 0 的金額"), "實際：\(reason.label)")

        app.swipeDown(); app.swipeDown()
        // 改成自訂分帳但不填各人金額 → 加總 0，比總額少 100
        let evenSplit = app.switches["平均分帳"].firstMatch
        XCTAssertTrue(evenSplit.waitForExistence(timeout: UITestTimeout.appear))
        // 點 Toggle 整列中間不一定會切換，點右側開關本體
        evenSplit.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.textFields["金額"].firstMatch.focusAndType("100", "金額")
        XCTAssertFalse(save.isEnabled)
        scrollUntilVisible(reason, in: app)
        XCTAssertTrue(reason.label.contains("分帳合計比總額少"), "實際：\(reason.label)")
        attach("01-custom-sum-mismatch")
    }

    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: UITestTimeout.appear), "找不到儲存原因")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
