import Foundation
import SwiftData

@Model
final class ExpenseSplit {
    var id: UUID = UUID()
    var amount: Decimal = 0

    var member: Member?

    var expense: Expense?

    init(member: Member, amount: Decimal) {
        self.id = UUID()
        self.amount = amount
        self.member = member
    }
}
