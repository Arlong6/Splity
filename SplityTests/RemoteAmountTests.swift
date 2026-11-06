import Testing
import Foundation
@testable import Splity

struct RemoteAmountTests {

    @Test("正常金額原樣通過")
    func normalAmounts() {
        #expect(RemoteAmount.parse("0") == 0)
        #expect(RemoteAmount.parse("1234") == 1234)
        #expect(RemoteAmount.parse("1234.56") == Decimal(string: "1234.56")!)
        #expect(RemoteAmount.parse(" 99 ") == 99)
    }

    /// Decimal(string:) 是前綴解析，"12abc" 會被解析成 12 並靜默寫進帳本。
    @Test("尾隨雜訊被拒絕，不做前綴解析")
    func rejectsTrailingJunk() {
        #expect(RemoteAmount.parse("12abc") == nil)
        #expect(RemoteAmount.parse("1,000") == nil)
        #expect(RemoteAmount.parse("1.2.3") == nil)
    }

    @Test("負數被拒絕")
    func rejectsNegative() {
        #expect(RemoteAmount.parse("-5") == nil)
        #expect(RemoteAmount.parse("-1e30") == nil)
    }

    @Test("科學記號被拒絕")
    func rejectsScientificNotation() {
        #expect(RemoteAmount.parse("1e100") == nil)
        #expect(RemoteAmount.parse("1E10") == nil)
    }

    @Test("超過上限被拒絕")
    func rejectsOversized() {
        #expect(RemoteAmount.parse("\(RemoteAmount.maximum)") != nil)
        #expect(RemoteAmount.parse("9999999999999999") == nil)
    }

    @Test("空值、空字串與非字串型別回傳 nil")
    func rejectsEmptyAndWrongTypes() {
        #expect(RemoteAmount.parse(nil) == nil)
        #expect(RemoteAmount.parse("") == nil)
        #expect(RemoteAmount.parse("   ") == nil)
        #expect(RemoteAmount.parse(100) == nil)
        #expect(RemoteAmount.parse(["a"]) == nil)
    }

    @Test("parseOrZero 把不合法的值當 0")
    func parseOrZeroFallsBack() {
        #expect(RemoteAmount.parseOrZero("-5") == 0)
        #expect(RemoteAmount.parseOrZero("12.5") == Decimal(string: "12.5")!)
    }
}

struct GroupPrefsClaimTests {

    @Test("婉拒認領會被記住，清除後恢復")
    func declineIsPersisted() {
        let id = UUID()
        #expect(GroupPrefs.hasDeclinedClaim(for: id) == false)
        GroupPrefs.setDeclinedClaim(true, for: id)
        #expect(GroupPrefs.hasDeclinedClaim(for: id) == true)
        GroupPrefs.setDeclinedClaim(false, for: id)
        #expect(GroupPrefs.hasDeclinedClaim(for: id) == false)
    }

    @Test("不同帳本的婉拒狀態互不影響")
    func declineIsPerGroup() {
        let a = UUID(), b = UUID()
        GroupPrefs.setDeclinedClaim(true, for: a)
        #expect(GroupPrefs.hasDeclinedClaim(for: b) == false)
        GroupPrefs.setDeclinedClaim(false, for: a)
    }

    @Test("刪除帳本會清掉它的所有偏好")
    func clearAllRemovesEverything() {
        let id = UUID()
        GroupPrefs.setDeclinedClaim(true, for: id)
        GroupPrefs.setDefaultInputCurrency("JPY", for: id)
        GroupPrefs.clearAll(for: id)
        #expect(GroupPrefs.hasDeclinedClaim(for: id) == false)
        #expect(GroupPrefs.defaultInputCurrency(for: id) == nil)
    }
}

/// Firestore rules 的 `validAmount`：純小數字串、最多 24 字。超過會整批寫入被拒。
struct RemoteAmountEncodingTests {

    private func passesRules(_ s: String) -> Bool {
        s.count <= RemoteAmount.maxEncodedLength
            && s.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil
    }

    @Test("一般金額原樣輸出")
    func shortValuesUnchanged() {
        #expect(RemoteAmount.encode(Decimal(string: "1234.56")!) == "1234.56")
        #expect(RemoteAmount.encode(1000) == "1000")
        #expect(RemoteAmount.encode(0) == "0")
    }

    @Test("手機裡舊資料的長小數：上傳時收斂到 24 字內，值幾乎不變")
    func longValueFitsRules() throws {
        // 實際案例：VND → TWD 匯率 0.001263、金額 8.99，舊寫法算出 26 字的 totalAmount
        let total = Decimal(string: "8.99")! * Decimal(0.001263)
        #expect("\(total)".count > RemoteAmount.maxEncodedLength)

        let encoded = RemoteAmount.encode(total)
        #expect(passesRules(encoded))
        let decoded = try #require(RemoteAmount.parse(encoded))
        #expect(abs(decoded - total) < Decimal(string: "0.00000000000000000001")!)
    }

    @Test("整數位多時也放得下")
    func longValueWithLargeIntegerPart() {
        let value = Decimal(string: "123456789012.12345678901234567")!
        #expect(passesRules(RemoteAmount.encode(value)))
    }

    @Test("進位造成整數位變多時仍放得下")
    func roundingCarry() {
        let value = Decimal(string: "9.99999999999999999999999999")!
        #expect(passesRules(RemoteAmount.encode(value)))
    }
}

struct ExchangeRateConversionTests {

    @Test("匯率不帶 Double 的二進位尾數")
    func noBinaryNoise() {
        #expect(CurrencyService.decimal(fromRate: 0.001263) == Decimal(string: "0.001263")!)
        #expect("\(CurrencyService.decimal(fromRate: 0.001263))" == "0.001263")
    }

    @Test("很小的匯率（Double 會印成科學記號）也轉得對")
    func tinyRate() {
        #expect(CurrencyService.decimal(fromRate: 0.000038) == Decimal(string: "0.000038")!)
    }

    @Test("修好後實際案例的總額是乾淨的短字串")
    func realCaseTotal() {
        let total = Decimal(string: "8.99")! * CurrencyService.decimal(fromRate: 0.001263)
        #expect("\(total)" == "0.01135437")
    }
}
