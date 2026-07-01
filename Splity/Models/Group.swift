import Foundation
import SwiftData

@Model
final class Group {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var isSettled: Bool = false

    var firestoreGroupId: String? = nil
    var firebaseOwnerId: String? = nil
    var inviteCode: String? = nil

    var baseCurrencyCode: String = "TWD"

    @Relationship(deleteRule: .cascade, minimumModelCount: 0, inverse: \Member.group)
    var members: [Member] = []

    @Relationship(deleteRule: .cascade, minimumModelCount: 0, inverse: \Expense.group)
    var expenses: [Expense] = []

    var isShared: Bool { firestoreGroupId != nil }

    init(name: String, baseCurrencyCode: String = "TWD") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.baseCurrencyCode = baseCurrencyCode
    }
}
