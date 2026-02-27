import Foundation
import SwiftData

@Model
final class Group {
    var id: UUID
    var name: String
    var createdAt: Date
    var isSettled: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Member.group)
    var members: [Member] = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.group)
    var expenses: [Expense] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
