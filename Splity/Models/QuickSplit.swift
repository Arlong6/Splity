import Foundation
import SwiftData

/// 快速分帳的一位參與者。
/// `paid` 是先出的金額（留空視為 0）；`share` 是這個人要負擔的金額，
/// nil 代表「平分剩下的」，0 代表「不用付」——兩者意義不同，不可互換。
/// 金額以字串編碼，避免 Decimal 經 JSON 的 Double 表示失真。
struct QuickSplitParticipant: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var paid: Decimal
    var share: Decimal?

    init(id: UUID = UUID(), name: String = "", paid: Decimal = 0, share: Decimal? = nil) {
        self.id = id
        self.name = name
        self.paid = paid
        self.share = share
    }

    private enum CodingKeys: String, CodingKey { case id, name, paid, share }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        paid = Decimal(string: try c.decode(String.self, forKey: .paid)) ?? 0
        // share 是後加的欄位；1.8.0 build 15 存下的紀錄沒有這個 key
        share = (try c.decodeIfPresent(String.self, forKey: .share)).flatMap { Decimal(string: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode("\(paid)", forKey: .paid)
        try c.encodeIfPresent(share.map { "\($0)" }, forKey: .share)
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
