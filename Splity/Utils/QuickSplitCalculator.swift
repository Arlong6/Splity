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
    /// 先出金額合計
    let total: Decimal
    /// 已指定應付的合計
    let assignedTotal: Decimal
    /// 扣掉已指定的應付後，要給其他人平分的餘額
    let remaining: Decimal
    /// 沒有指定應付、要平分餘額的人數
    let autoCount: Int
    /// 平分餘額後每人應付（已依幣別進位）
    let autoShare: Decimal
    /// 每個人最終的應付金額
    let shares: [UUID: Decimal]
    let transfers: [Transfer]

    var participantCount: Int { participants.count }

    /// 全部的人都指定了應付、但合計不等於總額時，沒有人能吸收差額 → 結不平，不可儲存。
    var isBalanced: Bool { autoCount > 0 || remaining == 0 }

    /// 已指定的應付超過總額，平分的餘額變成負數（多半是打錯）。
    var isOverAssigned: Bool { autoCount > 0 && remaining < 0 }

    func share(for participant: QuickSplitParticipant) -> Decimal {
        shares[participant.id] ?? 0
    }
}

enum QuickSplitCalculator {

    /// 應付留空的人平分「總額 − 已指定應付合計」；留 0 代表不用付。
    /// 每個人的淨額 = 先出 − 應付，交給共用的 greedy 核心配對轉帳。
    /// 進位造成應付合計與總額有落差時，把先出的債權等比例縮放，
    /// 讓沒先出錢的人付的金額恰好等於畫面上顯示的應付。
    static func compute(participants raw: [QuickSplitParticipant], currencyCode: String) -> QuickSplitResult {
        let participants = raw.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let total = participants.reduce(Decimal(0)) { $0 + $1.paid }
        let assignedTotal = participants.compactMap(\.share).reduce(Decimal(0), +)
        let autoCount = participants.filter { $0.share == nil }.count
        let remaining = total - assignedTotal
        let autoShare = autoCount > 0
            ? Decimal.round(remaining / Decimal(autoCount), in: currencyCode)
            : 0

        var shares: [UUID: Decimal] = [:]
        for p in participants {
            shares[p.id] = p.share.map { Decimal.round($0, in: currencyCode) } ?? autoShare
        }

        func result(_ transfers: [QuickSplitResult.Transfer]) -> QuickSplitResult {
            QuickSplitResult(
                participants: participants, total: total, assignedTotal: assignedTotal,
                remaining: remaining, autoCount: autoCount, autoShare: autoShare,
                shares: shares, transfers: transfers
            )
        }

        // 結不平時不產生轉帳；畫面改為提示差額，儲存鈕停用。
        guard !participants.isEmpty, total > 0, autoCount > 0 || remaining == 0 else {
            return result([])
        }

        let shareTotal = participants.reduce(Decimal(0)) { $0 + (shares[$1.id] ?? 0) }
        let creditScale = shareTotal / total
        let balances = participants.map { (id: $0.id, balance: $0.paid * creditScale - (shares[$0.id] ?? 0)) }
        let byId = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0) })

        let transfers = SettlementCalculator.settle(balances: balances, currencyCode: currencyCode)
            .compactMap { t -> QuickSplitResult.Transfer? in
                guard let from = byId[t.from], let to = byId[t.to] else { return nil }
                return QuickSplitResult.Transfer(from: from, to: to, amount: t.amount)
            }

        return result(transfers)
    }
}
