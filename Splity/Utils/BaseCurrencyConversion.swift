import Foundation

/// 換結算幣別時，把單筆花費換算到新基準幣。
enum BaseCurrencyConversion {
    /// - Parameters:
    ///   - sourceCode: 這筆花費的來源幣（外幣花費是原幣，本地花費是舊基準幣）
    ///   - rate: 來源幣 → 新基準幣的匯率
    static func convert(_ expense: Expense, from sourceCode: String, rate: Decimal, to newBase: String) {
        let originalAmount = expense.originalAmount ?? expense.totalAmount
        let newTotal = Decimal.round(originalAmount * rate, in: newBase)

        if sourceCode == newBase {
            // 換到新基準幣後此筆不再是外幣
            expense.totalAmount = newTotal
            expense.originalCurrencyCode = nil
            expense.originalAmount = nil
            expense.exchangeRate = nil
        } else {
            expense.totalAmount = newTotal
            expense.originalCurrencyCode = sourceCode
            expense.originalAmount = originalAmount
            expense.exchangeRate = rate
        }

        distribute(newTotal, across: expense.splits, scale: Decimal.currencyFractionDigits(newBase))

        // 其他裝置靠這個時間戳判斷要不要套用；沒更新的話，幣別代碼會換，這筆金額卻留在舊幣別的數字。
        expense.updatedAt = Date()
    }

    /// 依原分攤比例分配總額（最大餘數法）：先無條件捨去到最小貨幣單位，
    /// 剩下的單位給捨去最多的人。加總一定等於總額，每人與比例值的差距小於一個單位。
    /// 原分攤全為 0 時改為平分。
    private static func distribute(_ total: Decimal, across splits: [ExpenseSplit], scale: Int) {
        guard !splits.isEmpty else { return }
        let amounts = splits.map(\.amount)
        let hasWeights = amounts.reduce(0, +) > 0
        let weights = hasWeights ? amounts : amounts.map { _ in Decimal(1) }
        let weightSum = weights.reduce(0, +)

        let exact = weights.map { total * $0 / weightSum }
        var shares = exact.map { value -> Decimal in
            var floored = Decimal()
            var mutable = value
            NSDecimalRound(&floored, &mutable, scale, .down)
            return floored
        }

        let unit = Decimal(sign: .plus, exponent: -scale, significand: 1)
        var leftover = total - shares.reduce(0, +)
        let byLargestRemainder = shares.indices.sorted {
            let lhs = exact[$0] - shares[$0], rhs = exact[$1] - shares[$1]
            return lhs == rhs ? $0 < $1 : lhs > rhs
        }
        for index in byLargestRemainder where leftover >= unit {
            shares[index] += unit
            leftover -= unit
        }

        for (split, share) in zip(splits, shares) { split.amount = share }
    }
}
