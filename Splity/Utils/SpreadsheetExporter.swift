import Foundation

enum SpreadsheetExporter {

    static func generateCSV(group: Group) -> String {
        let members = group.members.sorted { $0.name < $1.name }
        let expenses = group.expenses.filter { !$0.archived }.sorted { $0.totalAmount > $1.totalAmount }
        let baseCode = group.baseCurrencyCode

        var lines: [String] = []

        // 結算幣別說明列
        lines.append([escape("結算幣別"), escape("\(baseCode) (\(CurrencyService.displayName(for: baseCode)))")]
            .joined(separator: ","))
        lines.append("")

        // Header row: 品項, [members...], 總價
        let header = (["品項"] + members.map { $0.name } + ["總價"])
            .map(escape).joined(separator: ",")
        lines.append(header)

        // 大家要付的
        lines.append("")
        lines.append(escape("大家要付的"))
        for expense in expenses {
            // 總價以各成員分攤加總為準：均分採無條件進位時 sum(splits) 可能略大於原始
            // totalAmount，唯有用 sum(splits) 才能讓成員欄位、總價欄與下方淨額列三者勾稽。
            let splitsSum = expense.splits.reduce(Decimal(0)) { $0 + $1.amount }
            var cols = [escape(expense.title)]
            for member in members {
                let amount = expense.splits.first { $0.member?.id == member.id }?.amount ?? 0
                cols.append(formatDecimal(amount, baseCode: baseCode))
            }
            cols.append(formatDecimal(splitsSum, baseCode: baseCode))
            lines.append(cols.joined(separator: ","))
        }

        // 有人先墊
        lines.append("")
        lines.append(escape("有人先墊"))
        for expense in expenses {
            let splitsSum = expense.splits.reduce(Decimal(0)) { $0 + $1.amount }
            var cols = [escape(expense.title)]
            for member in members {
                let amount: Decimal = expense.paidBy?.id == member.id ? -splitsSum : 0
                cols.append(formatDecimal(amount, baseCode: baseCode))
            }
            cols.append(formatDecimal(-splitsSum, baseCode: baseCode))
            lines.append(cols.joined(separator: ","))
        }

        // 總花費
        lines.append("")
        let netBalances = SettlementCalculator.computeNetBalances(expenses: expenses)
        var netCols = [escape("應付/應收")]
        for member in members {
            netCols.append(formatDecimal(-(netBalances[member] ?? 0), baseCode: baseCode))
        }
        netCols.append("0")
        lines.append(netCols.joined(separator: ","))

        // 外幣花費明細（只有外幣才出現）
        let foreign = expenses.filter { $0.isForeignCurrency }
        if !foreign.isEmpty {
            lines.append("")
            lines.append(escape("外幣花費明細"))
            let foreignHeader = (["品項", "原幣別", "原幣金額", "匯率", "換算後"])
                .map(escape).joined(separator: ",")
            lines.append(foreignHeader)
            for expense in foreign {
                let oc = expense.originalCurrencyCode ?? ""
                let oa = expense.originalAmount ?? 0
                let rate = expense.exchangeRate ?? 0
                let cols = [
                    escape(expense.title),
                    escape(oc),
                    formatDecimal(oa, baseCode: oc),
                    formatRate(rate),
                    formatDecimal(expense.totalAmount, baseCode: baseCode)
                ]
                lines.append(cols.joined(separator: ","))
            }
        }

        // UTF-8 BOM so Excel opens Chinese characters correctly
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        var v = value
        // 防 CSV/試算表公式注入：以 = + - @ 開頭的文字欄位前置單引號，避免 Excel/Numbers
        // 把使用者輸入的成員名稱或品項當公式執行（數字欄位走 formatDecimal，不經此函式）。
        if let first = v.first, "=+-@".contains(first) {
            v = "'" + v
        }
        guard v.contains(",") || v.contains("\"")
                || v.contains("\n") || v.contains("\r") else {
            return v
        }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatDecimal(_ value: Decimal, baseCode: String) -> String {
        let scale = Decimal.currencyFractionDigits(baseCode)
        var rounded = Decimal()
        var mutable = value
        NSDecimalRound(&rounded, &mutable, scale, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private static func formatRate(_ rate: Decimal) -> String {
        var rounded = Decimal()
        var mutable = rate
        NSDecimalRound(&rounded, &mutable, 6, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
