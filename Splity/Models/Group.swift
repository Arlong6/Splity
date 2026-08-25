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
    /// 邀請碼到期時間（1.7.8+）。`nil` = 舊版建立、沒有到期日的邀請碼 → 永不過期（向後相容）。
    var inviteCodeExpiresAt: Date? = nil

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
