import Foundation

struct Settlement: Identifiable {
    let id = UUID()
    let from: Member
    let to: Member
    let amount: Decimal
}

enum SettlementCalculator {

    static func computeNetBalances(expenses: [Expense]) -> [Member: Decimal] {
        var balances: [Member: Decimal] = [:]

        for expense in expenses {
            guard let payer = expense.paidBy else { continue }

            balances[payer, default: 0] += expense.totalAmount

            for split in expense.splits {
                guard let member = split.member else { continue }
                balances[member, default: 0] -= split.amount
            }
        }

        return balances
    }

    static func calculateSettlements(expenses: [Expense]) -> [Settlement] {
        let balances = computeNetBalances(expenses: expenses)

        var debtors: [(member: Member, amount: Decimal)] = []
        var creditors: [(member: Member, amount: Decimal)] = []

        for (member, balance) in balances {
            if balance < 0 {
                debtors.append((member, -balance))
            } else if balance > 0 {
                creditors.append((member, balance))
            }
        }

        debtors.sort { $0.amount > $1.amount }
        creditors.sort { $0.amount > $1.amount }

        var settlements: [Settlement] = []
        var di = 0, ci = 0

        while di < debtors.count && ci < creditors.count {
            let transfer = min(debtors[di].amount, creditors[ci].amount)
            let displayAmount = Decimal.roundForCurrentCurrency(transfer)

            if displayAmount > 0 {
                settlements.append(Settlement(
                    from: debtors[di].member,
                    to: creditors[ci].member,
                    amount: displayAmount
                ))
            }

            debtors[di].amount -= transfer
            creditors[ci].amount -= transfer

            if debtors[di].amount == 0 { di += 1 }
            if creditors[ci].amount == 0 { ci += 1 }
        }

        return settlements
    }
}

extension Decimal {
    /// 貨幣進位：整數幣別（台幣等）無條件進位，小數幣別（美元等）四捨五入
    static func roundForCurrentCurrency(_ value: Decimal) -> Decimal {
        let code = Locale.current.currency?.identifier ?? "TWD"
        let scale = currencyFractionDigits(code)
        let rule: NSDecimalNumber.RoundingMode = scale == 0 ? .up : .plain
        var result = Decimal()
        var mutableValue = value
        NSDecimalRound(&result, &mutableValue, scale, rule)
        return result
    }

    /// 幣別 → 小數位數（依實際流通慣例，非 ISO 4217 理論值）
    static func currencyFractionDigits(_ code: String) -> Int {
        let zeroCurrencies: Set<String> = [
            "TWD", "JPY", "KRW", "VND", "IDR", "ISK", "HUF",
            "CLP", "PYG", "RWF", "UGX", "BIF", "DJF", "GNF",
            "KMF", "MGA", "VUV", "XAF", "XOF", "XPF"
        ]
        return zeroCurrencies.contains(code) ? 0 : 2
    }

    // 保留供向下相容
    static func roundToTwoPlaces(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutableValue = value
        NSDecimalRound(&result, &mutableValue, 2, .plain)
        return result
    }
}
