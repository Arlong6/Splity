import Testing
import SwiftData
import Foundation
@testable import Splity

// MARK: - Test Helper

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(
        for: Group.self, Member.self, Expense.self, ExpenseSplit.self, HistoryRecord.self,
        configurations: config
    )
}

/// 建立一筆費用並設定 splits，插入 context
private func makeExpense(
    title: String,
    total: Decimal,
    payer: Member,
    splits: [(Member, Decimal)],
    ctx: ModelContext
) -> Expense {
    let expense = Expense(title: title, totalAmount: total, paidBy: payer)
    ctx.insert(expense)
    for (member, amount) in splits {
        let split = ExpenseSplit(member: member, amount: amount)
        ctx.insert(split)
        expense.splits.append(split)
    }
    return expense
}

// MARK: - Even Split Calculation Tests

struct EvenSplitTests {

    /// ceil(100 / 3) = 34 → 每人付 34，sum=102，付款人吸收 2 元差額
    @Test("3人分100元 - 每人34元，付款人淨收68元")
    func split100Among3People() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        let expense = makeExpense(
            title: "晚餐", total: 100, payer: a,
            splits: [(a, 34), (b, 34), (c, 34)],
            ctx: ctx
        )

        let balances = SettlementCalculator.computeNetBalances(expenses: [expense])

        // A 付款：credit=102，自己扣34 → 淨 +68
        #expect(balances[a] == 68)
        // B、C 各欠 34
        #expect(balances[b] == -34)
        #expect(balances[c] == -34)
        // 總和為 0
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }

    /// ceil(10 / 3) = 4 → 每人付 4，sum=12，付款人吸收 2 元差額
    @Test("3人分10元 - 每人4元，付款人淨收8元")
    func split10Among3People() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        let expense = makeExpense(
            title: "飲料", total: 10, payer: a,
            splits: [(a, 4), (b, 4), (c, 4)],
            ctx: ctx
        )

        let balances = SettlementCalculator.computeNetBalances(expenses: [expense])

        #expect(balances[a] == 8)
        #expect(balances[b] == -4)
        #expect(balances[c] == -4)
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }

    /// ceil(100 / 7) = 15 → 每人付 15，sum=105，付款人吸收 5 元差額
    @Test("7人分100元 - 每人15元，付款人淨收90元")
    func split100Among7People() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let members = (1...7).map { i -> Member in
            let m = Member(name: "人\(i)"); ctx.insert(m); return m
        }
        let payer = members[0]

        let expense = makeExpense(
            title: "聚餐", total: 100, payer: payer,
            splits: members.map { ($0, 15) },
            ctx: ctx
        )

        let balances = SettlementCalculator.computeNetBalances(expenses: [expense])

        // payer: credit=105, debit=15 → +90
        #expect(balances[payer] == 90)
        for member in members.dropFirst() {
            #expect(balances[member] == -15)
        }
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }

    /// ceil(1 / 5) = 1 → 每人付 1，sum=5，付款人吸收 4 元差額（極端情況）
    @Test("5人分1元 - 每人1元，付款人淨收4元")
    func split1Among5People() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let members = (1...5).map { i -> Member in
            let m = Member(name: "人\(i)"); ctx.insert(m); return m
        }
        let payer = members[0]

        let expense = makeExpense(
            title: "貼紙", total: 1, payer: payer,
            splits: members.map { ($0, 1) },
            ctx: ctx
        )

        let balances = SettlementCalculator.computeNetBalances(expenses: [expense])

        // payer: credit=5, debit=1 → +4
        #expect(balances[payer] == 4)
        for member in members.dropFirst() {
            #expect(balances[member] == -1)
        }
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }

    /// 剛好整除：ceil(90 / 3) = 30 → 沒有差額
    @Test("3人分90元 - 剛好整除，無進位差額")
    func split90Among3People() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        let expense = makeExpense(
            title: "計程車", total: 90, payer: a,
            splits: [(a, 30), (b, 30), (c, 30)],
            ctx: ctx
        )

        let balances = SettlementCalculator.computeNetBalances(expenses: [expense])

        // 整除：每人 30，payer credit=90, debit=30 → +60
        #expect(balances[a] == 60)
        #expect(balances[b] == -30)
        #expect(balances[c] == -30)
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }
}

// MARK: - Settlement Calculation Tests

struct SettlementTests {

    /// A 墊付所有費用，B 和 C 各欠相同金額
    @Test("一人墊付，兩人各還款")
    func onePayerTwoDebtors() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        // A 墊付 150，B 和 C 各欠 50（A 自己也分 50）
        let expense = makeExpense(
            title: "住宿", total: 150, payer: a,
            splits: [(a, 50), (b, 50), (c, 50)],
            ctx: ctx
        )

        let settlements = SettlementCalculator.calculateSettlements(expenses: [expense])

        #expect(settlements.count == 2)
        #expect(settlements.allSatisfy { $0.to === a })
        #expect(settlements.allSatisfy { $0.amount == 50 })
    }

    /// 多筆費用，各自墊付，互相抵消後只需最少轉帳
    @Test("多筆費用 - 結算後互相抵消")
    func multipleExpensesWithOffset() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)

        // A 墊付 200（A:100, B:100）
        let e1 = makeExpense(
            title: "晚餐", total: 200, payer: a,
            splits: [(a, 100), (b, 100)],
            ctx: ctx
        )
        // B 墊付 200（A:100, B:100）
        let e2 = makeExpense(
            title: "午餐", total: 200, payer: b,
            splits: [(a, 100), (b, 100)],
            ctx: ctx
        )

        let settlements = SettlementCalculator.calculateSettlements(expenses: [e1, e2])

        // 互相抵消，不需要任何轉帳
        #expect(settlements.isEmpty)
    }

    /// 結算金額總和不應超過原始總費用
    @Test("3人多筆費用 - 結算金額正確性")
    func settlementAmountCorrectness() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        // A 墊付 99（3人分，ceil=33）
        let e1 = makeExpense(
            title: "宵夜", total: 99, payer: a,
            splits: [(a, 33), (b, 33), (c, 33)],
            ctx: ctx
        )

        let settlements = SettlementCalculator.calculateSettlements(expenses: [e1])
        let totalSettled = settlements.reduce(Decimal(0)) { $0 + $1.amount }

        // B 付 33 給 A，C 付 33 給 A
        #expect(settlements.count == 2)
        #expect(totalSettled == 66)
    }
}

// MARK: - Hub Settlement Tests

struct HubSettlementTests {

    /// 基本情境：A 墊最多 → 成為 Hub，C/D/E 都付給 A，A 再付給 B
    @Test("Hub 模式：多人墊付，欠錢的人全部付給墊最多的人")
    func hubBasic() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)
        let d = Member(name: "D"); ctx.insert(d)
        let e = Member(name: "E"); ctx.insert(e)
        let members = [a, b, c, d, e]

        // A 墊 4812（4532+280），B 墊 4095，均分5人
        let e1 = makeExpense(title: "費用1", total: 4812, payer: a,
                             splits: members.map { ($0, 4812 / 5) }, ctx: ctx)
        let e2 = makeExpense(title: "費用2", total: 4095, payer: b,
                             splits: members.map { ($0, 4095 / 5) }, ctx: ctx)

        let settlements = SettlementCalculator.calculateHubSettlements(expenses: [e1, e2])

        // A 應為 Hub（墊最多）
        let toA = settlements.filter { $0.to === a }
        let fromA = settlements.filter { $0.from === a }

        // C, D, E 都付給 A（3筆）
        #expect(toA.count == 3)
        #expect(toA.allSatisfy { $0.from === c || $0.from === d || $0.from === e })

        // A 付給 B（1筆）
        #expect(fromA.count == 1)
        #expect(fromA.first?.to === b)

        // 總轉帳金額 = C+D+E 各自的欠款
        let totalToA = toA.reduce(Decimal(0)) { $0 + $1.amount }
        let totalFromA = fromA.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(totalToA - totalFromA > 0) // A 最終淨收款
    }

    /// 只有一個收款人時，Hub 模式結果應與 minimized 相同
    @Test("Hub 模式：只有一個收款人時與最少轉帳相同")
    func hubSingleCreditor() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        let expense = makeExpense(title: "住宿", total: 300, payer: a,
                                  splits: [(a, 100), (b, 100), (c, 100)], ctx: ctx)

        let hub = SettlementCalculator.calculateHubSettlements(expenses: [expense])
        let minimized = SettlementCalculator.calculateSettlements(expenses: [expense])

        // 結果筆數相同
        #expect(hub.count == minimized.count)
        // 所有轉帳金額相同
        let hubTotal = hub.reduce(Decimal(0)) { $0 + $1.amount }
        let minTotal = minimized.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(hubTotal == minTotal)
    }

    /// Hub 模式總轉帳金額應等於所有欠錢人的欠款總和
    @Test("Hub 模式：轉帳總金額正確")
    func hubTotalAmountCorrect() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)
        let d = Member(name: "D"); ctx.insert(d)

        // A 墊 600，B 墊 200，4人均分
        let e1 = makeExpense(title: "費用A", total: 600, payer: a,
                             splits: [(a, 150), (b, 150), (c, 150), (d, 150)], ctx: ctx)
        let e2 = makeExpense(title: "費用B", total: 200, payer: b,
                             splits: [(a, 50), (b, 50), (c, 50), (d, 50)], ctx: ctx)

        let settlements = SettlementCalculator.calculateHubSettlements(expenses: [e1, e2])

        // C 欠 200，D 欠 200，總欠款 400
        let debtorPayments = settlements.filter { $0.from === c || $0.from === d }
        let total = debtorPayments.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(total == 400)
    }
}

// MARK: - Decimal Utility Tests

struct DecimalUtilityTests {

    @Test("TWD 貨幣小數位數為 0")
    func twdFractionDigits() {
        #expect(Decimal.currencyFractionDigits("TWD") == 0)
        #expect(Decimal.currencyFractionDigits("JPY") == 0)
        #expect(Decimal.currencyFractionDigits("KRW") == 0)
    }

    @Test("USD 貨幣小數位數為 2")
    func usdFractionDigits() {
        #expect(Decimal.currencyFractionDigits("USD") == 2)
        #expect(Decimal.currencyFractionDigits("EUR") == 2)
    }

    @Test("ceil 進位計算正確")
    func ceilRounding() {
        // 100 / 3 = 33.333... → ceil to 0 decimal → 34
        var result = Decimal()
        var divided = Decimal(100) / Decimal(3)
        NSDecimalRound(&result, &divided, 0, .up)
        #expect(result == 34)

        // 10 / 3 = 3.333... → ceil → 4
        var result2 = Decimal()
        var divided2 = Decimal(10) / Decimal(3)
        NSDecimalRound(&result2, &divided2, 0, .up)
        #expect(result2 == 4)

        // 100 / 7 = 14.285... → ceil → 15
        var result3 = Decimal()
        var divided3 = Decimal(100) / Decimal(7)
        NSDecimalRound(&result3, &divided3, 0, .up)
        #expect(result3 == 15)

        // 1 / 5 = 0.2 → ceil → 1
        var result4 = Decimal()
        var divided4 = Decimal(1) / Decimal(5)
        NSDecimalRound(&result4, &divided4, 0, .up)
        #expect(result4 == 1)
    }
}

// MARK: - App 更新版本比對

struct VersionCompareTests {

    /// App Store 版本字串帶 "V" 前綴（V1.6.0）時，不應誤判為有新版
    @Test("V 前綴版本與本機相同時判定相等")
    func vPrefixNotNewer() {
        #expect(AppUpdateChecker.compareVersions(current: "1.6.0", store: "V1.6.0") == .orderedSame)
    }

    @Test("真的有新版仍正確判定為較新")
    func realNewer() {
        #expect(AppUpdateChecker.compareVersions(current: "1.6.0", store: "1.6.1") == .orderedAscending)
        #expect(AppUpdateChecker.compareVersions(current: "1.6.0", store: "V1.7.0") == .orderedAscending)
    }

    @Test("本機較新時判定為較新（不提示）")
    func localNewer() {
        #expect(AppUpdateChecker.compareVersions(current: "1.6.1", store: "V1.6.0") == .orderedDescending)
        #expect(AppUpdateChecker.compareVersions(current: "2.0.0", store: "V1.9.9") == .orderedDescending)
    }
}

// MARK: - 金額解析（地區小數分隔符）

struct AmountParsingTests {

    @Test("逗號小數分隔地區的金額不會被截斷")
    func parseCommaDecimal() {
        #expect(Decimal.parseAmount("1,5", decimalSeparator: ",") == Decimal(string: "1.5"))
        #expect(Decimal.parseAmount("10,25", decimalSeparator: ",") == Decimal(string: "10.25"))
        // 即使存檔字串用點號，逗號地區也要能正確解析
        #expect(Decimal.parseAmount("1.5", decimalSeparator: ",") == Decimal(string: "1.5"))
        #expect(Decimal.parseAmount("100", decimalSeparator: ",") == 100)
    }

    @Test("點號地區維持正常解析")
    func parseDotDecimal() {
        #expect(Decimal.parseAmount("1.5", decimalSeparator: ".") == Decimal(string: "1.5"))
        #expect(Decimal.parseAmount("100", decimalSeparator: ".") == 100)
    }

    @Test("空字串或非數字回傳 nil")
    func parseInvalid() {
        #expect(Decimal.parseAmount("", decimalSeparator: ".") == nil)
        #expect(Decimal.parseAmount("   ", decimalSeparator: ".") == nil)
        #expect(Decimal.parseAmount("abc", decimalSeparator: ".") == nil)
    }
}

// MARK: - 結算進位一致性

struct SettlementRoundingTests {

    /// 分數淨額（如外幣換算殘餘）不應被配對成多餘的進位轉帳。
    /// A 付款但不分攤；B、C 各分 0.5 → A 淨 +1.0、B -0.5、C -0.5。
    /// 舊版會對 B、C 各產生一筆 ceil 後 1 元的轉帳（共 2 元，遠超 1 元實際債務）；
    /// 修正後應只有 1 筆、總額 1 元。
    @Test("分數淨額不產生多餘的進位轉帳")
    func fractionalNoSpuriousTransfer() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)
        let c = Member(name: "C"); ctx.insert(c)

        let expense = makeExpense(
            title: "零頭", total: 1, payer: a,
            splits: [(b, Decimal(string: "0.5")!), (c, Decimal(string: "0.5")!)],
            ctx: ctx
        )

        let settlements = SettlementCalculator.calculateSettlements(expenses: [expense], currencyCode: "TWD")

        #expect(settlements.count == 1)
        let total = settlements.reduce(Decimal(0)) { $0 + $1.amount }
        #expect(total == 1)
    }
}

// MARK: - 外幣自訂拆帳進位

struct ForeignCustomSplitTests {

    /// 外幣（USD）自訂拆帳換算回基準幣（TWD, scale 0）後，split 金額應進位為整數，
    /// 不可存入帶小數的非法幣別精度（10.5 × 31.623 = 332.0415 → 333）。
    @Test("外幣自訂拆帳金額會進位到基準幣小數位")
    func foreignCustomSplitRounded() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = Group(name: "日本行", baseCurrencyCode: "TWD")
        ctx.insert(group)
        let a = Member(name: "A"); ctx.insert(a); a.group = group; group.members.append(a)
        let b = Member(name: "B"); ctx.insert(b); b.group = group; group.members.append(b)

        // 用「既有花費」建構 VM 可避開 init 對 Firebase 的呼叫（僅新花費分支會用到）
        let dummy = makeExpense(title: "暫存", total: 1, payer: a, splits: [(a, 1)], ctx: ctx)

        let vm = ExpenseEditViewModel(group: group, expense: dummy)
        vm.title = "拉麵"
        vm.selectedCurrencyCode = "USD"
        vm.lockedRate = Decimal(string: "31.623")
        vm.totalAmountString = "21"
        vm.selectedPayer = a
        vm.selectedMemberIDs = [a.id, b.id]
        vm.isEvenSplit = false
        vm.customAmounts = [a.id: "10.5", b.id: "10.5"]

        let err = vm.save(modelContext: ctx)
        #expect(err == nil)

        let amounts = dummy.splits.map { $0.amount }
        #expect(amounts.count == 2)
        for amt in amounts {
            #expect(amt == Decimal(333))
        }
    }
}

// MARK: - CSV 公式注入防護

struct CSVInjectionTests {

    @Test("以公式字元開頭的成員名稱與品項會被前置單引號中和")
    func csvNeutralizesFormulaInjection() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = Group(name: "測試", baseCurrencyCode: "TWD")
        ctx.insert(group)
        let evil = Member(name: "=HYPERLINK(1)"); ctx.insert(evil); evil.group = group; group.members.append(evil)
        let bob = Member(name: "Bob"); ctx.insert(bob); bob.group = group; group.members.append(bob)

        let e = makeExpense(title: "+SUM(A1)", total: 100, payer: evil,
                            splits: [(evil, 50), (bob, 50)], ctx: ctx)
        e.group = group
        group.expenses.append(e)

        let csv = SpreadsheetExporter.generateCSV(group: group)

        #expect(csv.contains("'=HYPERLINK(1)"))
        #expect(csv.contains("'+SUM(A1)"))
        // 不應出現未中和的原始公式（以逗號界定，避免誤判）
        #expect(!csv.contains(",=HYPERLINK(1)"))
    }
}

// MARK: - 付款人為 nil 的花費（遠端 payer 尚未同步）

struct NilPayerExpenseTests {

    /// 遠端 merge 找不到 payer 時保留花費（paidBy=nil）而非丟棄；結算應安全略過該筆、不崩潰。
    @Test("付款人為 nil 的花費不計入結算且不崩潰")
    func nilPayerSkippedSafely() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a = Member(name: "A"); ctx.insert(a)
        let b = Member(name: "B"); ctx.insert(b)

        let e1 = makeExpense(title: "正常", total: 100, payer: a, splits: [(a, 50), (b, 50)], ctx: ctx)

        // 付款人為 nil（模擬遠端 payerId 尚未對應到本地成員）
        let e2 = Expense(title: "孤兒", totalAmount: 30, paidBy: nil)
        ctx.insert(e2)
        let s2 = ExpenseSplit(member: b, amount: 30); ctx.insert(s2); e2.splits.append(s2)

        let balances = SettlementCalculator.computeNetBalances(expenses: [e1, e2])

        // e2 因 paidBy nil 被略過，只算 e1
        #expect(balances[a] == 50)
        #expect(balances[b] == -50)
        #expect(balances.values.reduce(Decimal(0), +) == 0)
    }
}
