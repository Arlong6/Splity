import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID
    var title: String
    var totalAmount: Decimal
    var date: Date?
    var note: String?
    var createdAt: Date

    var paidBy: Member?

    @Relationship(deleteRule: .cascade, inverse: \ExpenseSplit.expense)
    var splits: [ExpenseSplit] = []

    var group: Group?

    init(title: String, totalAmount: Decimal, paidBy: Member, date: Date? = nil, note: String? = nil) {
        self.id = UUID()
        self.title = title
        self.totalAmount = totalAmount
        self.paidBy = paidBy
        self.date = date
        self.note = note
        self.createdAt = Date()
    }
}
