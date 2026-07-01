import Foundation
import WidgetKit

/// 將統計資料寫入 App Group，供 Widget 讀取
struct WidgetDataWriter {

    private static let appGroupID = "group.com.arlongchien.Splity"
    private static let fileName = "splity_widget.json"

    struct Payload: Codable {
        let activeGroupCount: Int
        let totalExpenseCount: Int
    }

    static func update(activeGroupCount: Int, totalExpenseCount: Int) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let fileURL = containerURL.appendingPathComponent(fileName)
        let payload = Payload(activeGroupCount: activeGroupCount, totalExpenseCount: totalExpenseCount)

        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
