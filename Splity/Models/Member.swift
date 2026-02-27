import Foundation
import SwiftData

@Model
final class Member {
    var id: UUID
    var name: String

    var group: Group?
    var expensesPaid: [Expense] = []
    var splits: [ExpenseSplit] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}
