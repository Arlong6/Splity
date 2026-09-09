import Testing
import SwiftData
import Foundation
@testable import Splity

// MARK: - 泛型結算核心

struct SettlementCoreTests {

    @Test("單一債權人：兩人各還債權人")
    func singleCreditor() {
        let balances: [(id: String, balance: Decimal)] = [("A", 68), ("B", -34), ("C", -34)]
        let t = SettlementCalculator.settle(balances: balances, currencyCode: "TWD")
        #expect(t.count == 2)
        #expect(t.allSatisfy { $0.to == "A" && $0.amount == 34 })
        #expect(Set(t.map(\.from)) == ["B", "C"])
    }

    @Test("金額相同時依輸入順序配對（穩定排序）")
    func tiesFollowInputOrder() {
        let balances: [(id: String, balance: Decimal)] = [("X", -50), ("Y", -50), ("P", 60), ("Q", 40)]
        let t = SettlementCalculator.settle(balances: balances, currencyCode: "TWD")
        // X 先配 P（60）：X→P 50；Y 配 P 剩 10 再配 Q 40
        #expect(t.map { "\($0.from)>\($0.to):\($0.amount)" } == ["X>P:50", "Y>P:10", "Y>Q:40"])
    }

    @Test("小數幣別次分位殘值不會卡死")
    func subCentResidualTerminates() {
        let third = Decimal(10) / Decimal(3)
        let balances: [(id: String, balance: Decimal)] = [("A", 10 - third), ("B", -third), ("C", -third)]
        let t = SettlementCalculator.settle(balances: balances, currencyCode: "USD")
        #expect(t.count == 2)
        #expect(t.allSatisfy { $0.amount == Decimal(string: "3.33")! })
    }

    @Test("零與空輸入不產生轉帳")
    func emptyAndZero() {
        #expect(SettlementCalculator.settle(balances: [(id: "A", balance: 0)], currencyCode: "TWD").isEmpty)
        #expect(SettlementCalculator.settle(balances: [(id: String, balance: Decimal)](), currencyCode: "TWD").isEmpty)
    }

    @Test("hub：多位債權人時集中到最大債權人")
    func hubRoutesThroughLargestCreditor() {
        let balances: [(id: String, balance: Decimal)] = [("A", 60), ("B", 40), ("C", -100)]
        let t = SettlementCalculator.settleViaHub(balances: balances, currencyCode: "TWD")
        #expect(t.map { "\($0.from)>\($0.to):\($0.amount)" } == ["C>A:100", "A>B:40"])
    }
}

// MARK: - 快速分帳計算

struct QuickSplitCalculatorTests {

    private func p(_ name: String, _ paid: Decimal, share: Decimal? = nil) -> QuickSplitParticipant {
        QuickSplitParticipant(name: name, paid: paid, share: share)
    }

    @Test("一人先付全額，其他人均分還他（TWD 無條件進位）")
    func singlePayerTWD() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 100), p("B", 0), p("C", 0)], currencyCode: "TWD")
        #expect(r.total == 100)
        #expect(r.autoShare == 34)
        #expect(r.isBalanced)
        #expect(r.transfers.count == 2)
        #expect(r.transfers.allSatisfy { $0.to.name == "A" && $0.amount == 34 })
    }

    @Test("多位付款人：沒先出的人付的總和恰等於每人應付，按墊款比例分給兩位墊款者")
    func multiplePayers() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 60), p("B", 40), p("C", 0)], currencyCode: "TWD")
        #expect(r.autoShare == 34)
        // A 債權 60×1.02 = 27.2 → 進位 28；B 拿剩下的 6
        let byTo = Dictionary(grouping: r.transfers, by: { $0.to.name }).mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
        #expect(byTo["A"] == 28)
        #expect(byTo["B"] == 6)
        #expect(r.transfers.allSatisfy { $0.from.name == "C" })
        #expect(r.transfers.reduce(Decimal(0)) { $0 + $1.amount } == 34)
    }

    @Test("USD 三人分 10 元：每人 3.33，殘值不產生多餘轉帳")
    func usdResidual() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 10), p("B", 0), p("C", 0)], currencyCode: "USD")
        #expect(r.autoShare == Decimal(string: "3.33")!)
        #expect(r.transfers.count == 2)
        #expect(r.transfers.allSatisfy { $0.amount == Decimal(string: "3.33")! })
    }

    @Test("空白姓名的列不列入計算")
    func blankNamesIgnored() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 90), p("B", 0), p("  ", 0), p("C", 0)], currencyCode: "TWD")
        #expect(r.participantCount == 3)
        #expect(r.autoShare == 30)
    }

    @Test("總額為 0 時沒有轉帳")
    func zeroTotal() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 0), p("B", 0)], currencyCode: "TWD")
        #expect(r.total == 0)
        #expect(r.transfers.isEmpty)
    }

    // MARK: 指定應付

    @Test("兩人各出 100、我指定應付 120：剩下 80 歸另一人，我補 20 給他")
    func assignedShareSplitsRemainder() {
        let r = QuickSplitCalculator.compute(
            participants: [p("我", 100, share: 120), p("你", 100)],
            currencyCode: "TWD"
        )
        #expect(r.total == 200)
        #expect(r.assignedTotal == 120)
        #expect(r.remaining == 80)
        #expect(r.autoCount == 1)
        #expect(r.autoShare == 80)
        #expect(r.isBalanced)
        #expect(r.transfers.count == 1)
        #expect(r.transfers[0].from.name == "我")
        #expect(r.transfers[0].to.name == "你")
        #expect(r.transfers[0].amount == 20)
    }

    @Test("應付填 0 代表不用付；留空的兩人平分全額")
    func zeroShareMeansOwesNothing() {
        let r = QuickSplitCalculator.compute(
            participants: [p("A", 900), p("B", 0), p("陪坐", 0, share: 0)],
            currencyCode: "TWD"
        )
        #expect(r.autoCount == 2)
        #expect(r.autoShare == 450)
        #expect(r.share(for: r.participants.first { $0.name == "陪坐" }!) == 0)
        #expect(r.transfers.count == 1)
        #expect(r.transfers[0].from.name == "B")
        #expect(r.transfers[0].to.name == "A")
        #expect(r.transfers[0].amount == 450)
    }

    @Test("應付 0 與留空意義不同：留空的人要分攤，填 0 的人不用")
    func nilShareDiffersFromZero() {
        let auto = QuickSplitCalculator.compute(
            participants: [p("A", 100), p("B", 0)], currencyCode: "TWD"
        )
        let zero = QuickSplitCalculator.compute(
            participants: [p("A", 100), p("B", 0, share: 0)], currencyCode: "TWD"
        )
        #expect(auto.transfers.count == 1)   // B 分攤 50，要還 A
        #expect(zero.transfers.isEmpty)      // B 不用付，A 自己吸收
    }

    @Test("所有人都指定應付且合計等於總額 → 平衡，照指定的算")
    func allAssignedBalanced() {
        let r = QuickSplitCalculator.compute(
            participants: [p("A", 200, share: 50), p("B", 0, share: 150)],
            currencyCode: "TWD"
        )
        #expect(r.autoCount == 0)
        #expect(r.isBalanced)
        #expect(r.transfers.count == 1)
        #expect(r.transfers[0].from.name == "B")
        #expect(r.transfers[0].to.name == "A")
        #expect(r.transfers[0].amount == 150)
    }

    @Test("所有人都指定應付但合計不等於總額 → 結不平，不產生轉帳")
    func allAssignedUnbalanced() {
        let r = QuickSplitCalculator.compute(
            participants: [p("A", 1000, share: 300), p("B", 0, share: 300), p("C", 0, share: 300)],
            currencyCode: "TWD"
        )
        #expect(r.autoCount == 0)
        #expect(r.remaining == 100)
        #expect(!r.isBalanced)
        #expect(r.transfers.isEmpty)
    }

    @Test("指定的應付超過總額：標記為超額，餘額為負仍照算")
    func overAssigned() {
        let r = QuickSplitCalculator.compute(
            participants: [p("A", 100, share: 150), p("B", 0)],
            currencyCode: "TWD"
        )
        #expect(r.isOverAssigned)
        #expect(r.remaining == -50)
        #expect(r.autoShare == -50)
        #expect(r.isBalanced)
    }
}

// MARK: - 序列化

struct QuickSplitModelTests {

    @Test("participants 以 JSON 存取，金額 round-trip 不失真")
    func participantsRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: QuickSplit.self, configurations: config)
        let ctx = ModelContext(container)

        let split = QuickSplit(title: "晚餐", currencyCode: "USD")
        split.participants = [
            QuickSplitParticipant(name: "A", paid: Decimal(string: "12.34")!, share: Decimal(string: "20.5")!),
            QuickSplitParticipant(name: "B", paid: Decimal(string: "0.1")!),
        ]
        ctx.insert(split)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<QuickSplit>())
        #expect(fetched.count == 1)
        #expect(fetched[0].participants.map(\.name) == ["A", "B"])
        #expect(fetched[0].participants.map(\.paid) == [Decimal(string: "12.34")!, Decimal(string: "0.1")!])
        #expect(fetched[0].participants.map(\.share) == [Decimal(string: "20.5")!, nil])
        #expect(fetched[0].total == Decimal(string: "12.44")!)
    }
}

// MARK: - 舊紀錄相容

struct QuickSplitLegacyDecodeTests {

    /// 1.8.0 build 15 存下的 JSON 沒有 share 欄位，解碼後必須是 nil（平分），不是 0。
    @Test("缺少 share 欄位的舊紀錄解碼為 nil")
    func legacyJSONWithoutShare() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","name":"A","paid":"100"}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([QuickSplitParticipant].self, from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].paid == 100)
        #expect(decoded[0].share == nil)
    }
}
