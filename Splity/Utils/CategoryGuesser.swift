import Foundation

/// 依品項名稱的關鍵字猜分類。離線、即時，不把內容傳到任何地方。
///
/// 比對方式：名稱去掉前後空白、轉小寫後，看是否「包含」關鍵字。
/// 多個分類都命中時取最長的關鍵字（較精確，例如「飯店」勝過「飯」）；一樣長就照分類清單順序。
///
/// 加關鍵字時注意：比對是子字串，太短的英文字會在別的單字裡誤中
/// （`inn` 在 dinner 裡、`bus` 在 business 裡、`gas` 在 Las Vegas 裡、`spa` 在 Spain 裡、
/// `mall` 在 small 裡），所以不收，或改用較長的詞組。
/// 這份清單改了之後，沒存分類的舊花費顯示結果會跟著變，這是設計上接受的。
enum CategoryGuesser {

    static func guess(title: String) -> ExpenseCategory? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        var best: (length: Int, order: Int, category: ExpenseCategory)?
        for (order, category) in ExpenseCategory.allCases.enumerated() {
            for keyword in keywords[category] ?? [] where text.contains(keyword) {
                let length = keyword.count
                if let current = best,
                   current.length > length || (current.length == length && current.order <= order) {
                    continue
                }
                best = (length, order, category)
            }
        }
        return best?.category
    }

    /// 全部小寫。
    private static let keywords: [ExpenseCategory: [String]] = [
        .food: [
            "早餐", "午餐", "晚餐", "早午餐", "宵夜", "下午茶", "點心", "甜點", "餐廳", "餐",
            "飯", "麵", "拉麵", "便當", "小吃", "夜市", "火鍋", "燒肉", "壽司", "咖啡", "星巴克",
            "飲料", "手搖", "奶茶", "酒", "啤酒", "居酒屋", "吃",
            "food", "breakfast", "brunch", "lunch", "dinner", "supper", "restaurant", "meal",
            "coffee", "cafe", "starbucks", "drinks", "beer", "pizza", "burger", "sushi", "ramen", "snack",
        ],
        .transport: [
            "加油", "油錢", "油資", "油費", "中油", "台塑", "停車", "過路費", "etag", "高鐵", "台鐵",
            "火車", "捷運", "地鐵", "公車", "客運", "巴士", "計程車", "小黃", "機票", "航空", "租車",
            "渡輪", "船票", "交通",
            "uber", "taxi", "lyft", "grab", "train", "flight", "airfare", "parking", "toll",
            "fuel", "gasoline", "petrol", "gas station", "metro", "subway", "car rental", "ferry",
            "bus ticket", "transport",
        ],
        .lodging: [
            "飯店", "酒店", "旅館", "旅店", "民宿", "住宿", "青旅", "渡假村", "度假村", "露營",
            "hotel", "hostel", "motel", "airbnb", "resort", "lodging", "accommodation", "camping",
        ],
        .fun: [
            "門票", "入場", "樂園", "遊樂", "展覽", "博物館", "美術館", "動物園", "水族館", "電影",
            "唱歌", "ktv", "纜車", "體驗", "溫泉", "按摩",
            "ticket", "admission", "museum", "zoo", "aquarium", "movie", "cinema", "disney",
            "theme park", "tour", "karaoke",
        ],
        .shopping: [
            "購物", "伴手禮", "紀念品", "衣服", "鞋", "免稅", "百貨", "outlet",
            "shopping", "souvenir", "gift", "clothes", "duty free", "shopping mall",
        ],
        .daily: [
            "超市", "超商", "便利商店", "全聯", "家樂福", "7-11", "全家", "藥妝", "藥局", "日用品",
            "衛生紙", "雜貨", "生活用品",
            "supermarket", "grocery", "groceries", "pharmacy", "drugstore", "convenience store",
            "toiletries",
        ],
    ]
}
