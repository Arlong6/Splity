import Foundation
import SwiftData

@Model
final class ExpenseSplit {
    var id: UUID
    var amount: Decimal

    var member: Member?
    var expense: Expense?

    init(member: Member, amount: Decimal) {
        self.id = UUID()
        self.amount = amount
        self.member = member
    }
}
