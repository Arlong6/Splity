import Foundation

struct Settlement: Identifiable {
    let id = UUID()
    let from: Member
    let to: Member
    let amount: Decimal
}

/// 泛型轉帳結果：群組結算用 Member 當 ID，快速分帳用參與者 UUID。
struct Transfer<ID: Hashable> {
    let from: ID
    let to: ID
    let amount: Decimal
}

enum SettlementMode {
    case minimized  // 最少轉帳次數
    case hub        // 集中付給一人
}

enum SettlementCalculator {

    static func computeNetBalances(expenses: [Expense]) -> [Member: Decimal] {
        var balances: [Member: Decimal] = [:]

        for expense in expenses {
            guard let payer = expense.paidBy else { continue }

            // 用 splits 加總作為付款人的 credit：
            // 若 ceil 分攤使 sum(splits) > totalAmount，差額為付款人收到的福利，balance 仍然歸零
            let payerCredit = expense.splits.reduce(Decimal(0)) { $0 + ($1.amount) }
            balances[payer, default: 0] += payerCredit

            for split in expense.splits {
                guard let member = split.member else { continue }
                balances[member, default: 0] -= split.amount
            }
        }

        return balances
    }

    /// 最少轉帳次數。Member 淨額 → 泛型核心 → Settlement。
    static func calculateSettlements(expenses: [Expense], currencyCode: String = "TWD") -> [Settlement] {
        let balances = computeNetBalances(expenses: expenses).map { (id: $0.key, balance: $0.value) }
        return settle(balances: balances, currencyCode: currencyCode)
            .map { Settlement(from: $0.from, to: $0.to, amount: $0.amount) }
    }

    /// Hub 模式：所有欠錢的人集中付給墊最多的人，再由那人分給其他墊錢的人
    static func calculateHubSettlements(expenses: [Expense], currencyCode: String = "TWD") -> [Settlement] {
        let balances = computeNetBalances(expenses: expenses).map { (id: $0.key, balance: $0.value) }
        return settleViaHub(balances: balances, currencyCode: currencyCode)
            .map { Settlement(from: $0.from, to: $0.to, amount: $0.amount) }
    }

    // MARK: - 泛型核心（群組結算與快速分帳共用）

    /// 貪婪配對：把淨額為負的人依序配給淨額為正的人，轉帳次數最少。
    /// `balances` 的順序即為金額相同時的配對順序（排序為穩定排序）。
    static func settle<ID: Hashable>(
        balances: [(id: ID, balance: Decimal)],
        currencyCode: String
    ) -> [Transfer<ID>] {
        var debtors: [(id: ID, amount: Decimal)] = []
        var creditors: [(id: ID, amount: Decimal)] = []

        for (id, balance) in balances {
            if balance < 0 {
                debtors.append((id, -balance))
            } else if balance > 0 {
                creditors.append((id, balance))
            }
        }

        debtors.sort { $0.amount > $1.amount }
        creditors.sort { $0.amount > $1.amount }

        var transfers: [Transfer<ID>] = []
        var di = 0, ci = 0

        while di < debtors.count && ci < creditors.count {
            let transfer = min(debtors[di].amount, creditors[ci].amount)
            let displayAmount = Decimal.round(transfer, in: currencyCode)

            if displayAmount > 0 {
                transfers.append(Transfer(from: debtors[di].id, to: creditors[ci].id, amount: displayAmount))

                // 以「顯示金額」扣減（而非未進位的 transfer），讓顯示與內部一致，
                // 避免分數餘額被配對成多餘的進位轉帳。
                debtors[di].amount -= displayAmount
                creditors[ci].amount -= displayAmount
            } else {
                // 小數幣別（USD 等，四捨五入）遇到次分位殘值時 displayAmount 會是 0，
                // 扣 0 兩邊金額都不變、索引也不前進 → 無窮迴圈把主執行緒鎖死。
                // 把較小的一方視為結清，確保每輪至少前進一個索引。
                if debtors[di].amount <= creditors[ci].amount {
                    debtors[di].amount = 0
                } else {
                    creditors[ci].amount = 0
                }
            }

            if debtors[di].amount <= 0 { di += 1 }
            if creditors[ci].amount <= 0 { ci += 1 }
        }

        return transfers
    }

    /// Hub 模式：所有欠錢的人付給淨額最大的人，再由他分給其他墊錢的人。
    /// 只有一位債權人時與 `settle` 相同。
    static func settleViaHub<ID: Hashable>(
        balances: [(id: ID, balance: Decimal)],
        currencyCode: String
    ) -> [Transfer<ID>] {
        var debtors: [(id: ID, amount: Decimal)] = []
        var creditors: [(id: ID, amount: Decimal)] = []

        for (id, balance) in balances {
            if balance < 0 { debtors.append((id, -balance)) }
            else if balance > 0 { creditors.append((id, balance)) }
        }

        guard creditors.count > 1 else {
            return settle(balances: balances, currencyCode: currencyCode)
        }

        creditors.sort { $0.amount > $1.amount }
        let hub = creditors[0]
        var transfers: [Transfer<ID>] = []

        for debtor in debtors {
            let amount = Decimal.round(debtor.amount, in: currencyCode)
            if amount > 0 {
                transfers.append(Transfer(from: debtor.id, to: hub.id, amount: amount))
            }
        }

        for creditor in creditors.dropFirst() {
            let amount = Decimal.round(creditor.amount, in: currencyCode)
            if amount > 0 {
                transfers.append(Transfer(from: hub.id, to: creditor.id, amount: amount))
            }
        }

        return transfers
    }
}

extension Decimal {
    /// 貨幣進位（指定幣別）：整數幣別（台幣等）無條件進位，小數幣別（美元等）四捨五入
    static func round(_ value: Decimal, in currencyCode: String) -> Decimal {
        let scale = currencyFractionDigits(currencyCode)
        let rule: NSDecimalNumber.RoundingMode = scale == 0 ? .up : .plain
        var result = Decimal()
        var mutableValue = value
        NSDecimalRound(&result, &mutableValue, scale, rule)
        return result
    }

    /// 舊版 API；以 device locale 推測幣別。新程式請改用 `round(_:in:)`。
    static func roundForCurrentCurrency(_ value: Decimal) -> Decimal {
        round(value, in: Locale.current.currency?.identifier ?? "TWD")
    }

    /// 解析使用者輸入的金額，尊重指定的小數分隔符號。
    /// （.decimalPad 在以逗號為小數分隔的地區會輸出逗號，直接用 `Decimal(string:)` 會在逗號處
    /// 截斷造成金額被靜默改小，例如 "1,5" → 1。）
    static func parseAmount(_ string: String, decimalSeparator sep: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalized = sep == "." ? trimmed : trimmed.replacingOccurrences(of: sep, with: ".")
        return Decimal(string: normalized)
    }

    /// 以當前地區的小數分隔符號解析金額。
    static func parseAmount(_ string: String) -> Decimal? {
        parseAmount(string, decimalSeparator: Locale.current.decimalSeparator ?? ".")
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
