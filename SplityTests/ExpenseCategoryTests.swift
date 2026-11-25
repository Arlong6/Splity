import Testing
import SwiftData
import Foundation
@testable import Splity

private func makeCategoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(
        for: Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self, QuickSplit.self,
        configurations: config
    )
}

// MARK: - 分類清單與關鍵字猜測

@MainActor
struct ExpenseCategoryTests {

    @Test("常見中英文品項猜得出分類")
    func guessesCommonTitles() {
        for title in ["加油", "中油", "停車費", "高鐵", "Uber", "taxi"] {
            #expect(CategoryGuesser.guess(title: title) == .transport, "\(title)")
        }
        for title in ["飯店", "民宿", "Airbnb", "hotel"] {
            #expect(CategoryGuesser.guess(title: title) == .lodging, "\(title)")
        }
        for title in ["晚餐", "咖啡", "dinner"] {
            #expect(CategoryGuesser.guess(title: title) == .food, "\(title)")
        }
        for title in ["門票", "ticket"] {
            #expect(CategoryGuesser.guess(title: title) == .fun, "\(title)")
        }
        #expect(CategoryGuesser.guess(title: "超市") == .daily)
    }

    @Test("猜不到回傳 nil")
    func returnsNilWhenUnknown() {
        #expect(CategoryGuesser.guess(title: "asdf") == nil)
        #expect(CategoryGuesser.guess(title: "") == nil)
        #expect(CategoryGuesser.guess(title: "   ") == nil)
    }

    @Test("忽略大小寫與前後空白，多重命中取最長的關鍵字")
    func normalizesAndPrefersLongest() {
        // 命中 uber（4 字，交通）與 hotel（5 字，住宿）→ 取較長的 hotel
        #expect(CategoryGuesser.guess(title: "  UBER to hotel ") == .lodging)
        #expect(CategoryGuesser.guess(title: "  TAXI\n") == .transport)
        // 「飯店」同時含「飯」（餐飲）與「飯店」（住宿）→ 取較長的住宿
        #expect(CategoryGuesser.guess(title: "飯店") == .lodging)
        // 「停車場」含「停車」，仍是交通
        #expect(CategoryGuesser.guess(title: "停車場") == .transport)
    }

    @Test("短英文字不會在別的單字裡誤中")
    func noFalseHitsInsideWords() {
        // dinner 裡有 inn、business 裡有 bus，都不該被當成住宿或交通
        #expect(CategoryGuesser.guess(title: "dinner") == .food)
        #expect(CategoryGuesser.guess(title: "business") == nil)
    }

    @Test("顯示用分類：有值用值、未知代碼當其他、沒值就猜")
    func displayCategoryRules() {
        let e = Expense(title: "晚餐", totalAmount: 1, paidBy: nil)
        e.category = "lodging"
        #expect(e.displayCategory == .lodging)
        e.category = "pets"
        #expect(e.displayCategory == .other)
        e.category = nil
        #expect(e.displayCategory == .food)
        e.title = "asdf"
        #expect(e.displayCategory == nil)
        // 顯示時不會寫回
        #expect(e.category == nil)
    }

    @Test("每個分類都有名稱與圖示，代碼固定")
    func codesAndNames() {
        #expect(ExpenseCategory.allCases.map(\.rawValue)
                == ["food", "transport", "lodging", "fun", "shopping", "daily", "other"])
        for c in ExpenseCategory.allCases {
            #expect(!c.displayName.isEmpty)
            #expect(!c.symbolName.isEmpty)
        }
        #expect(!ExpenseCategory.uncategorizedName.isEmpty)
    }
}

// MARK: - 記帳表單的分類狀態

@MainActor
struct ExpenseEditCategoryTests {

    private func makeGroup(_ ctx: ModelContext) -> (Group, Member, Member) {
        let group = Group(name: "G"); ctx.insert(group)
        let a = Member(name: "A"); ctx.insert(a); a.group = group; group.members.append(a)
        let b = Member(name: "B"); ctx.insert(b); b.group = group; group.members.append(b)
        return (group, a, b)
    }

    private func makeExisting(_ ctx: ModelContext, title: String, category: String?,
                              payer: Member, group: Group) -> Expense {
        let e = Expense(title: title, totalAmount: 100, paidBy: payer)
        ctx.insert(e)
        let s = ExpenseSplit(member: payer, amount: 100); ctx.insert(s); e.splits.append(s)
        e.category = category
        e.group = group; group.expenses.append(e)
        return e
    }

    @Test("新增時改品項名稱會重新猜")
    func newExpenseGuessesFromTitle() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, _, _) = makeGroup(ctx)
        let vm = ExpenseEditViewModel(group: group)
        #expect(vm.category == nil)
        vm.title = "加油"; vm.titleDidChange()
        #expect(vm.category == .transport)
        vm.title = "晚餐"; vm.titleDidChange()
        #expect(vm.category == .food)
    }

    @Test("手動選過之後改名稱不會覆蓋")
    func manualPickStopsGuessing() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, _, _) = makeGroup(ctx)
        let vm = ExpenseEditViewModel(group: group)
        vm.userPicked(.shopping)
        vm.title = "加油"; vm.titleDidChange()
        #expect(vm.category == .shopping)
        // 手動選「未分類」也算選過
        vm.userPicked(nil)
        vm.title = "晚餐"; vm.titleDidChange()
        #expect(vm.category == nil)
    }

    @Test("編輯已有分類的花費不會被改")
    func existingCategoryNotChanged() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, a, _) = makeGroup(ctx)
        let e = makeExisting(ctx, title: "晚餐", category: "lodging", payer: a, group: group)
        let vm = ExpenseEditViewModel(group: group, expense: e)
        #expect(vm.category == .lodging)
        vm.titleDidChange()
        #expect(vm.category == .lodging)
    }

    @Test("編輯沒分類的舊花費會先填入猜測")
    func nilExistingPrefillsGuess() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, a, _) = makeGroup(ctx)
        let e = makeExisting(ctx, title: "晚餐", category: nil, payer: a, group: group)
        let vm = ExpenseEditViewModel(group: group, expense: e)
        #expect(vm.category == .food)
    }

    @Test("只打開沒按儲存，舊花費仍是 nil")
    func prefillDoesNotWriteWithoutSave() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, a, _) = makeGroup(ctx)
        let e = makeExisting(ctx, title: "晚餐", category: nil, payer: a, group: group)
        let vm = ExpenseEditViewModel(group: group, expense: e)
        vm.title = "加油"; vm.titleDidChange()
        #expect(vm.category == .transport)
        #expect(e.category == nil)
    }

    @Test("存檔會寫入分類，選未分類存成 nil")
    func savePersistsCategory() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, a, _) = makeGroup(ctx)
        let vm = ExpenseEditViewModel(group: group)
        vm.title = "加油"; vm.titleDidChange()
        vm.totalAmountString = "100"
        vm.selectedPayer = a
        #expect(vm.save(modelContext: ctx) == nil)
        let saved = try #require(group.expenses.first { $0.title == "加油" })
        #expect(saved.category == "transport")

        let vm2 = ExpenseEditViewModel(group: group, expense: saved)
        vm2.userPicked(nil)
        #expect(vm2.save(modelContext: ctx) == nil)
        #expect(saved.category == nil)
    }

    @Test("未來版本的分類代碼：顯示成其他，但改別的欄位存檔後原樣保留")
    func unknownCodeSurvivesSave() throws {
        let ctx = ModelContext(try makeCategoryContainer())
        let (group, a, _) = makeGroup(ctx)
        let e = makeExisting(ctx, title: "飼料", category: "pets", payer: a, group: group)
        let vm = ExpenseEditViewModel(group: group, expense: e)
        #expect(vm.category == .other)
        vm.totalAmountString = "200"
        #expect(vm.save(modelContext: ctx) == nil)
        #expect(e.totalAmount == 200)
        #expect(e.category == "pets")
    }
}

// MARK: - 同步欄位編碼

struct ExpenseCategoryCodingTests {

    @Test("nil 寫成 NSNull，有值寫字串")
    func nilEncodesAsNull() {
        #expect(ExpenseCategoryCoding.encode(nil) is NSNull)
        #expect(ExpenseCategoryCoding.encode("food") as? String == "food")
        #expect(ExpenseCategoryCoding.key == "category")
    }

    @Test("null、缺欄位、空字串、非字串都讀成 nil；未知代碼原樣保留")
    func decodesNullAndMissingAsNil() {
        #expect(ExpenseCategoryCoding.decode(NSNull()) == nil)
        #expect(ExpenseCategoryCoding.decode(nil) == nil)
        #expect(ExpenseCategoryCoding.decode("") == nil)
        #expect(ExpenseCategoryCoding.decode(3) == nil)
        #expect(ExpenseCategoryCoding.decode("pets") == "pets")
        #expect(ExpenseCategoryCoding.decode("food") == "food")
    }
}

// MARK: - 統計加總

@MainActor
struct CategoryStatsTests {

    private func expense(_ title: String, _ amount: Decimal, _ category: String?,
                         archived: Bool = false) -> Expense {
        let e = Expense(title: title, totalAmount: amount, paidBy: nil)
        e.category = category
        e.archived = archived
        return e
    }

    @Test("依金額加總、由大到小排，算出百分比")
    func sumsAndSorts() {
        let totals = CategoryStats.totals(for: [
            expense("x", 100, "transport"),
            expense("y", 400, "lodging"),
            expense("z", 300, "food"),
            expense("w", 200, "lodging"),
        ])
        #expect(totals.map(\.category) == [.lodging, .food, .transport])
        #expect(totals.map(\.amount) == [600, 300, 100])
        #expect(totals.map(\.percent) == [60, 30, 10])
        #expect(CategoryStats.grandTotal(totals) == 1000)
        #expect(totals.map(\.id) == ["lodging", "food", "transport"])
    }

    @Test("未分類永遠排最後")
    func uncategorizedLast() {
        let totals = CategoryStats.totals(for: [
            expense("asdf", 900, nil),
            expense("x", 100, "food"),
        ])
        #expect(totals.map(\.category) == [.food, nil])
        #expect(totals.last?.id == "uncategorized")
        #expect(totals.last?.percent == 90)
    }

    @Test("沒存分類的花費用猜測歸類")
    func usesGuessForNil() {
        let totals = CategoryStats.totals(for: [expense("飯店", 500, nil)])
        #expect(totals.map(\.category) == [.lodging])
    }

    @Test("只有已刪除或金額 0 的花費時是空的")
    func emptyWhenOnlyArchivedOrZero() {
        let totals = CategoryStats.totals(for: [
            expense("x", 100, "food", archived: true),
            expense("y", 0, "lodging"),
        ])
        #expect(totals.isEmpty)
        #expect(CategoryStats.grandTotal(totals) == 0)
        #expect(CategoryStats.totals(for: []).isEmpty)
    }
}
