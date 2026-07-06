import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID = UUID()
    var title: String = ""
    var totalAmount: Decimal = 0
    var date: Date? = nil
    var note: String? = nil
    var createdAt: Date = Date()

    var paidBy: Member?

    @Relationship(deleteRule: .cascade, minimumModelCount: 0, inverse: \ExpenseSplit.expense)
    var splits: [ExpenseSplit] = []

    var group: Group?

    @Attribute(originalName: "isDeleted")
    var archived: Bool = false
    var deletedAt: Date? = nil

    /// 原幣別代碼（ISO 4217）。nil 代表此筆花費就是群組基準幣別。
    var originalCurrencyCode: String? = nil
    /// 原幣金額。nil 代表此筆花費就是基準幣別輸入。
    var originalAmount: Decimal? = nil
    /// 原幣 → 基準幣的匯率。`totalAmount = originalAmount × exchangeRate`。
    var exchangeRate: Decimal? = nil

    var isForeignCurrency: Bool { originalCurrencyCode != nil }

    init(title: String, totalAmount: Decimal, paidBy: Member?, date: Date? = nil, note: String? = nil) {
        self.id = UUID()
        self.title = title
        self.totalAmount = totalAmount
        self.paidBy = paidBy
        self.date = date
        self.note = note
        self.createdAt = Date()
    }
}
