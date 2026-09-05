import Foundation

/// 快速分帳的計算結果。
struct QuickSplitResult {
    struct Transfer: Identifiable {
        let id = UUID()
        let from: QuickSplitParticipant
        let to: QuickSplitParticipant
        let amount: Decimal
    }

    /// 只含有名字的參與者
    let participants: [QuickSplitParticipant]
    let total: Decimal
    /// 每人應付（已依幣別進位，僅供顯示）
    let perShare: Decimal
    let transfers: [Transfer]

    var participantCount: Int { participants.count }
}

enum QuickSplitCalculator {

    /// 均分。規則與群組的均分一致：每人應付 = 進位後的份額 S，
    /// 墊款者按墊款比例分配 N×S 的債權（進位差額歸墊款者），
    /// 因此沒先出錢的人付的總額恰為 S，與畫面顯示的「每人應付」一致。
    static func compute(participants raw: [QuickSplitParticipant], currencyCode: String) -> QuickSplitResult {
        let participants = raw.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let total = participants.reduce(Decimal(0)) { $0 + $1.paid }

        guard !participants.isEmpty, total > 0 else {
            return QuickSplitResult(participants: participants, total: total, perShare: 0, transfers: [])
        }

        let count = Decimal(participants.count)
        let share = Decimal.round(total / count, in: currencyCode)
        let creditScale = share * count / total
        let balances = participants.map { (id: $0.id, balance: $0.paid * creditScale - share) }
        let byId = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })

        let transfers = SettlementCalculator.settle(balances: balances, currencyCode: currencyCode)
            .compactMap { t -> QuickSplitResult.Transfer? in
                guard let from = byId[t.from], let to = byId[t.to] else { return nil }
                return QuickSplitResult.Transfer(from: from, to: to, amount: t.amount)
            }

        return QuickSplitResult(
            participants: participants,
            total: total,
            perShare: share,
            transfers: transfers
        )
    }
}
