import Foundation

/// 統計畫面上的一列：一個分類（nil＝未分類）的合計與占比。
struct CategoryTotal: Identifiable {
    let category: ExpenseCategory?
    /// 結算幣別金額（大家合計）。
    let amount: Decimal
    /// 占總額的百分比，四捨五入到整數，只供顯示（各列加總不一定剛好 100）。
    let percent: Int

    var id: String { category?.rawValue ?? "uncategorized" }
}

/// 帳本的分類統計。只算沒被刪除的花費，用 `displayCategory` 歸類（沒存分類的舊花費用猜的）。
enum CategoryStats {

    /// 依金額由大到小；「未分類」永遠放最後；合計不大於 0 的分類不列。
    static func totals(for expenses: [Expense]) -> [CategoryTotal] {
        var sums: [ExpenseCategory?: Decimal] = [:]
        for expense in expenses where !expense.archived {
            sums[expense.displayCategory, default: 0] += expense.totalAmount
        }
        let positive = sums.filter { $0.value > 0 }
        let grand = positive.values.reduce(Decimal(0), +)
        guard grand > 0 else { return [] }

        let order = ExpenseCategory.allCases
        let sorted = positive.sorted { lhs, rhs in
            switch (lhs.key, rhs.key) {
            case (nil, _): return false
            case (_, nil): return true
            case let (l?, r?):
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return order.firstIndex(of: l)! < order.firstIndex(of: r)!
            }
        }
        return sorted.map { key, amount in
            CategoryTotal(category: key, amount: amount, percent: percent(amount, of: grand))
        }
    }

    /// 統計畫面有沒有東西可顯示，等同 `!totals(for:).isEmpty`，但不必逐筆猜分類。
    /// 帳本頁每次重畫都會問，大帳本要便宜。
    static func hasStats(for expenses: [Expense]) -> Bool {
        expenses.contains { !$0.archived && $0.totalAmount > 0 }
    }

    static func grandTotal(_ totals: [CategoryTotal]) -> Decimal {
        totals.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private static func percent(_ amount: Decimal, of total: Decimal) -> Int {
        var raw = amount / total * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
