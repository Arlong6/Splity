import Foundation

/// 從 Firestore 讀進來的金額字串的唯一入口。
///
/// 過去各處直接用 `Decimal(string:)`，它是「前綴解析」而且不做任何範圍檢查——
/// 實測會收下 `"-5"`、`"1e100"`、`"12abc"`（解析成 12）、`"1,000"`（解析成 1）。
/// rules 對金額也沒有約束，所以任何成員（或任何拿到寫入權的程式）寫進
/// `totalAmount: "-1e30"`，就能毒化所有裝置的餘額與結算，而且沒有任何一端會擋。
enum RemoteAmount {
    /// 合理的金額上限。超過這個數量級的不可能是真的記帳資料，
    /// 卻足以讓下游的加總與進位失去意義。
    static let maximum = Decimal(string: "1000000000000")!   // 1 兆

    /// 解析遠端金額；不合理的值回傳 nil，由呼叫端決定跳過或視為 0。
    static func parse(_ raw: Any?) -> Decimal? {
        guard let string = raw as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 只接受純數字格式，擋掉 "12abc"（前綴解析）與 "1e100"（科學記號）
        guard trimmed.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else {
            return nil
        }
        guard let value = Decimal(string: trimmed), value.isFinite else { return nil }
        guard value >= 0, value <= maximum else { return nil }
        return value
    }

    /// 解析不出來就當 0，用於「少一筆比整包壞掉好」的合併路徑。
    static func parseOrZero(_ raw: Any?) -> Decimal {
        parse(raw) ?? 0
    }
}
