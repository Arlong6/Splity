import XCTest

/// UI 測試共用的等待秒數。
///
/// UI 測試是平行跑的（多個模擬器 clone），機器忙的時候畫面更新會明顯變慢。
/// 原本散在各處的 10 秒在資源吃緊時會變成假陰性——`testScreenshot_04_GroupWithExpenses`
/// 就是這樣間歇失敗的：單獨重跑約 60 秒會過，平行跑那次花了 100 秒。
/// 放寬等待不會讓測試變慢（等到了就往下走），只會讓「紅燈」重新代表「真的壞了」。
enum UITestTimeout {
    /// 等一個元素出現。
    static let appear: TimeInterval = 20
    /// 等一個元素消失（通常是 sheet / alert 關閉）。
    static let disappear: TimeInterval = 10
}

extension XCUIElement {

    /// 這個元素目前是否持有鍵盤焦點。
    ///
    /// XCUITest 沒有公開 API 可以問這件事，只能用 KVC 取內部屬性。
    /// 這個寫法在 `QuickSplitUITests` 裡已經用了一段時間，是這個專案驗證過可行的做法。
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// 確認鍵盤焦點真的到位之後才輸入文字。
    ///
    /// 直接 `tap()` 再 `typeText()` 會間歇性炸在
    /// `Failed to synthesize event: Neither element nor any descendant has keyboard focus`。
    /// tap 回來不代表焦點已經落到這個 field 上：sheet 可能還在轉場，或 `@FocusState`
    /// 剛把焦點指去別的欄位。點一次拿不到就再點，比放大 timeout 更對症。
    func focusAndType(_ text: String, _ name: String = "輸入框",
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: UITestTimeout.appear),
                      "\(name) 不存在", file: file, line: line)
        for _ in 0..<4 where !hasKeyboardFocus {
            tap()
            _ = waitForExistence(timeout: 1)
        }
        XCTAssertTrue(hasKeyboardFocus, "\(name) 拿不到鍵盤焦點", file: file, line: line)
        typeText(text)
    }
}
