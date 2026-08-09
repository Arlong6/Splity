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

    /// 拆帳模式：true=均分、false=自訂。nil=舊資料未記錄（重新編輯時退回以「金額是否相等」推斷）。
    /// 明確保存可避免「自訂但金額剛好相等」被誤判為均分。
    var isEvenSplit: Bool? = nil

    /// 最後一次新增/編輯的時間（nil=舊資料，顯示時退回 createdAt）。
    var updatedAt: Date? = nil
    /// 最後編輯者名稱（共享帳本＝當下認領的成員名；本地或未認領為 nil）。
    var lastEditorName: String? = nil

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
