import Foundation
import SwiftData

@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""

    /// Firebase Auth UID of the user who "owns" this identity in a shared group.
    /// nil = ghost member (anyone can log expenses on their behalf).
    var claimedByUid: String? = nil

    var group: Group?

    @Relationship(minimumModelCount: 0, inverse: \Expense.paidBy)
    var expensesPaid: [Expense] = []

    @Relationship(deleteRule: .cascade, minimumModelCount: 0, inverse: \ExpenseSplit.member)
    var splits: [ExpenseSplit] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}
