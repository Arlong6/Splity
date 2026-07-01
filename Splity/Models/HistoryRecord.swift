import Foundation
import SwiftData

@Model
final class HistoryRecord {
    var id: UUID = UUID()
    var groupName: String = ""
    var memberCount: Int = 0
    var expenseCount: Int = 0
    var actionRaw: String = HistoryAction.deleted.rawValue
    var date: Date = Date()

    enum HistoryAction: String, Codable {
        case settled = "settled"
        case deleted = "deleted"
    }

    var action: HistoryAction {
        get { HistoryAction(rawValue: actionRaw) ?? .deleted }
        set { actionRaw = newValue.rawValue }
    }

    init(groupName: String, memberCount: Int, expenseCount: Int, action: HistoryAction) {
        self.id = UUID()
        self.groupName = groupName
        self.memberCount = memberCount
        self.expenseCount = expenseCount
        self.actionRaw = action.rawValue
        self.date = Date()
    }
}
