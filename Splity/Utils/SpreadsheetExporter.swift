import Foundation

enum SpreadsheetExporter {

    static func generateCSV(group: Group) -> String {
        let members = group.members.sorted { $0.name < $1.name }
        let expenses = group.expenses.sorted {
            ($0.date ?? $0.createdAt) < ($1.date ?? $1.createdAt)
        }

        var lines: [String] = []

        // Header row: 品項, [members...], 總價
        let header = (["品項"] + members.map { $0.name } + ["總價"])
            .map(escape).joined(separator: ",")
        lines.append(header)

        // 大家要付的
        lines.append("")
        lines.append(escape("大家要付的"))
        for expense in expenses {
            var cols = [escape(expense.title)]
            for member in members {
                let amount = expense.splits.first { $0.member?.id == member.id }?.amount ?? 0
                cols.append(formatDecimal(amount))
            }
            cols.append(formatDecimal(expense.totalAmount))
            lines.append(cols.joined(separator: ","))
        }

        // 有人先墊
        lines.append("")
        lines.append(escape("有人先墊"))
        for expense in expenses {
            var cols = [escape(expense.title)]
            for member in members {
                let amount: Decimal = expense.paidBy?.id == member.id ? -expense.totalAmount : 0
                cols.append(formatDecimal(amount))
            }
            cols.append(formatDecimal(-expense.totalAmount))
            lines.append(cols.joined(separator: ","))
        }

        // 總花費
        lines.append("")
        let netBalances = SettlementCalculator.computeNetBalances(expenses: expenses)
        var netCols = [escape("總花費")]
        for member in members {
            netCols.append(formatDecimal(-(netBalances[member] ?? 0)))
        }
        netCols.append("0")
        lines.append(netCols.joined(separator: ","))

        // UTF-8 BOM so Excel opens Chinese characters correctly
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"")
                || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        var rounded = Decimal()
        var mutable = value
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
