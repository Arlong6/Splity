import Foundation
import SwiftData

@Model
final class HistoryRecord {
    var id: UUID
    var groupName: String
    var memberCount: Int
    var expenseCount: Int
    var action: HistoryAction
    var date: Date

    enum HistoryAction: String, Codable {
        case settled = "settled"
        case deleted = "deleted"
    }

    init(groupName: String, memberCount: Int, expenseCount: Int, action: HistoryAction) {
        self.id = UUID()
        self.groupName = groupName
        self.memberCount = memberCount
        self.expenseCount = expenseCount
        self.action = action
        self.date = Date()
    }
}
