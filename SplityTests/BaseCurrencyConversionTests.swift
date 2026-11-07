import Testing
import SwiftData
import Foundation
@testable import Splity

@MainActor
@Suite("換結算幣別：單筆花費換算")
struct BaseCurrencyConversionTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Group.self, Member.self, Expense.self, ExpenseSplit.self,
                                           configurations: config)
        return ModelContext(container)
    }

    private func expense(total: Decimal, splits: [Decimal], in context: ModelContext) -> Expense {
        let e = Expense(title: "晚餐", totalAmount: total, paidBy: nil)
        context.insert(e)
        for (i, amount) in splits.enumerated() {
            let m = Member(name: "成員\(i)")
            context.insert(m)
            let s = ExpenseSplit(member: m, amount: amount)
            context.insert(s)
            e.splits.append(s)
        }
        return e
    }

    private func amounts(_ e: Expense) -> [Decimal] { e.splits.map(\.amount) }
    private func sum(_ e: Expense) -> Decimal { amounts(e).reduce(0, +) }
    private func spread(_ e: Expense) -> Decimal { amounts(e).max()! - amounts(e).min()! }

    /// 沒更新時間戳的話，別台裝置的 LWW 會跳過這筆，舊金額直接掛上新幣別。
    @Test("換算後更新 updatedAt，其他裝置的合併不會跳過")
    func bumpsUpdatedAt() throws {
        let context = try makeContext()
        let e = expense(total: 1000, splits: [500, 500], in: context)
        let before = Date(timeIntervalSinceNow: -60)
        e.updatedAt = before

        BaseCurrencyConversion.convert(e, from: "TWD", rate: Decimal(string: "0.0316")!, to: "USD")

        #expect(ExpenseMergePolicy.decide(isPurged: false, localUpdatedAt: before,
                                          remoteUpdatedAt: e.updatedAt) == .apply)
        #expect(e.updatedAt! > before)
    }

    @Test("小金額多人換算不會出現負數分攤")
    func noNegativeSplit() throws {
        let context = try makeContext()
        let e = expense(total: 10, splits: Array(repeating: 2, count: 7), in: context)

        BaseCurrencyConversion.convert(e, from: "TWD", rate: Decimal(string: "0.0316")!, to: "USD")

        #expect(amounts(e).allSatisfy { $0 >= 0 })
        #expect(sum(e) == e.totalAmount)
    }

    @Test("進位差額不會全落在最後一人，均分仍相差最多一個最小單位")
    func spreadsResidual() throws {
        let context = try makeContext()
        let e = expense(total: 100, splits: Array(repeating: 15, count: 7), in: context)

        BaseCurrencyConversion.convert(e, from: "TWD", rate: Decimal(string: "0.0316")!, to: "USD")

        #expect(e.totalAmount == Decimal(string: "3.16")!)
        #expect(sum(e) == e.totalAmount)
        #expect(spread(e) <= Decimal(string: "0.01")!)
    }

    @Test("換到日圓這種零小數幣別，總額與分攤都是整數且分攤相差最多 1")
    func zeroDecimalTarget() throws {
        let context = try makeContext()
        let e = expense(total: 1000, splits: [334, 334, 334], in: context)

        BaseCurrencyConversion.convert(e, from: "TWD", rate: Decimal(string: "4.7513")!, to: "JPY")

        #expect(e.totalAmount == 4752)
        #expect(sum(e) == 4752)
        #expect(spread(e) <= 1)
        #expect(amounts(e).allSatisfy { Decimal.round($0, in: "JPY") == $0 })
    }

    @Test("自訂分攤維持原比例")
    func keepsCustomProportion() throws {
        let context = try makeContext()
        let e = expense(total: 100, splits: [75, 25], in: context)

        BaseCurrencyConversion.convert(e, from: "USD", rate: 30, to: "TWD")

        #expect(amounts(e).sorted() == [750, 2250])
    }

    @Test("分攤全為 0 時改為平分")
    func zeroWeightsSplitEvenly() throws {
        let context = try makeContext()
        let e = expense(total: 100, splits: [0, 0], in: context)

        BaseCurrencyConversion.convert(e, from: "USD", rate: 30, to: "TWD")

        #expect(amounts(e) == [1500, 1500])
    }

    @Test("換回原幣時清掉外幣欄位，金額回到原幣")
    func backToSourceClearsForeignFields() throws {
        let context = try makeContext()
        let e = expense(total: 2100, splits: [1050, 1050], in: context)
        e.originalCurrencyCode = "JPY"
        e.originalAmount = 10000
        e.exchangeRate = Decimal(string: "0.21")

        BaseCurrencyConversion.convert(e, from: "JPY", rate: 1, to: "JPY")

        #expect(e.totalAmount == 10000)
        #expect(e.originalCurrencyCode == nil)
        #expect(e.originalAmount == nil)
        #expect(e.exchangeRate == nil)
        #expect(sum(e) == 10000)
    }
}

@MainActor
@Suite("列表頁只推送有改動的欄位")
struct GroupFieldTests {
    private func group() -> Group {
        let g = Group(name: "東京", baseCurrencyCode: "TWD")
        g.isSettled = true
        return g
    }

    @Test("改名只送 name，不把本地過期的幣別與結清狀態蓋回遠端")
    func nameOnly() {
        let payload = GroupField.name.payload(of: group())
        #expect(Set(payload.keys) == ["name"])
        #expect(payload["name"] as? String == "東京")
    }

    @Test("結清只送 isSettled")
    func settledOnly() {
        let payload = GroupField.isSettled.payload(of: group())
        #expect(Set(payload.keys) == ["isSettled"])
        #expect(payload["isSettled"] as? Bool == true)
    }
}
