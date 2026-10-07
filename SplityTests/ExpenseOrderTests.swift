import Testing
import Foundation
@testable import Splity

@Suite("消費排序：依輸入順序")
struct ExpenseOrderTests {
    private func expense(_ title: String, amount: Decimal, createdAt: Date, id: UUID = UUID()) -> Expense {
        let e = Expense(title: title, totalAmount: amount, paidBy: nil)
        e.createdAt = createdAt
        e.id = id
        return e
    }

    @Test("依建立時間由早到晚，與金額無關")
    func ordersByCreatedAtNotAmount() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let big = expense("後輸入的大筆", amount: 9999, createdAt: t0.addingTimeInterval(120))
        let small = expense("先輸入的小筆", amount: 1, createdAt: t0)
        let mid = expense("中間", amount: 500, createdAt: t0.addingTimeInterval(60))
        #expect([big, small, mid].inEntryOrder().map(\.title) == ["先輸入的小筆", "中間", "後輸入的大筆"])
    }

    @Test("同一刻建立時用 id 定序，結果穩定")
    func tieBreaksByID() {
        let t = Date(timeIntervalSince1970: 2_000_000)
        let a = expense("A", amount: 1, createdAt: t, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = expense("B", amount: 2, createdAt: t, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect([b, a].inEntryOrder().map(\.title) == ["A", "B"])
        #expect([a, b].inEntryOrder().map(\.title) == ["A", "B"])
    }
}
