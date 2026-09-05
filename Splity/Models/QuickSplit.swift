import Foundation
import SwiftData

/// 快速分帳的一位參與者：名字與先出的金額。
/// 金額以字串編碼，避免 Decimal 經 JSON 的 Double 表示失真。
struct QuickSplitParticipant: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var paid: Decimal

    init(id: UUID = UUID(), name: String = "", paid: Decimal = 0) {
        self.id = id
        self.name = name
        self.paid = paid
    }

    private enum CodingKeys: String, CodingKey { case id, name, paid }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let paidString = try c.decode(String.self, forKey: .paid)
        paid = Decimal(string: paidString) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode("\(paid)", forKey: .paid)
    }
}

/// 一次性的快速分帳紀錄。純本機、無關聯、不同步。
/// 結果不另存，隨時由 participants 重算。
@Model
final class QuickSplit {
    var id: UUID = UUID()
    var title: String = ""
    var currencyCode: String = "TWD"
    var date: Date = Date()
    var participantsData: Data = Data()

    init(title: String, currencyCode: String, participants: [QuickSplitParticipant] = []) {
        self.id = UUID()
        self.title = title
        self.currencyCode = currencyCode
        self.date = Date()
        self.participants = participants
    }

    var participants: [QuickSplitParticipant] {
        get { (try? JSONDecoder().decode([QuickSplitParticipant].self, from: participantsData)) ?? [] }
        set { participantsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var total: Decimal {
        participants.reduce(Decimal(0)) { $0 + $1.paid }
    }
}
