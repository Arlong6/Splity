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

    private func p(_ name: String, _ paid: Decimal) -> QuickSplitParticipant {
        QuickSplitParticipant(name: name, paid: paid)
    }

    @Test("一人先付全額，其他人均分還他（TWD 無條件進位）")
    func singlePayerTWD() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 100), p("B", 0), p("C", 0)], currencyCode: "TWD")
        #expect(r.total == 100)
        #expect(r.perShare == 34)
        #expect(r.transfers.count == 2)
        #expect(r.transfers.allSatisfy { $0.to.name == "A" && $0.amount == 34 })
    }

    @Test("多位付款人：沒先出的人付的總和恰等於每人應付，按墊款比例分給兩位墊款者")
    func multiplePayers() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 60), p("B", 40), p("C", 0)], currencyCode: "TWD")
        #expect(r.perShare == 34)
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
        #expect(r.perShare == Decimal(string: "3.33")!)
        #expect(r.transfers.count == 2)
        #expect(r.transfers.allSatisfy { $0.amount == Decimal(string: "3.33")! })
    }

    @Test("空白姓名的列不列入計算")
    func blankNamesIgnored() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 90), p("B", 0), p("  ", 0), p("C", 0)], currencyCode: "TWD")
        #expect(r.participantCount == 3)
        #expect(r.perShare == 30)
    }

    @Test("總額為 0 時沒有轉帳")
    func zeroTotal() {
        let r = QuickSplitCalculator.compute(participants: [p("A", 0), p("B", 0)], currencyCode: "TWD")
        #expect(r.total == 0)
        #expect(r.perShare == 0)
        #expect(r.transfers.isEmpty)
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
            QuickSplitParticipant(name: "A", paid: Decimal(string: "12.34")!),
            QuickSplitParticipant(name: "B", paid: Decimal(string: "0.1")!),
        ]
        ctx.insert(split)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<QuickSplit>())
        #expect(fetched.count == 1)
        #expect(fetched[0].participants.map(\.name) == ["A", "B"])
        #expect(fetched[0].participants.map(\.paid) == [Decimal(string: "12.34")!, Decimal(string: "0.1")!])
        #expect(fetched[0].total == Decimal(string: "12.44")!)
    }
}
