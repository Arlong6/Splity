import Foundation
import SwiftData
import SwiftUI

@Observable
final class ExpenseEditViewModel {
    let group: Group
    var existingExpense: Expense?

    // Form fields
    var title = ""
    var totalAmountString = ""
    var selectedPayer: Member?
    var date = Date()
    var hasDate = false
    var note = ""

    // 幣別 / 匯率（金額一律以「使用者輸入幣別」表示，存檔前再換算）
    var selectedCurrencyCode: String
    /// 自動由 Frankfurter 抓 5 日最低匯率，不開放使用者編輯。
    var lockedRate: Decimal? = nil
    var isFetchingRate: Bool = false
    var rateFetchFailed: Bool = false

    // Split config（金額用「使用者輸入幣別」表示）
    var isEvenSplit = true
    var selectedMemberIDs: Set<UUID> = []
    var customAmounts: [UUID: String] = [:]

    var members: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    var totalAmount: Decimal? {
        Decimal.parseAmount(totalAmountString)
    }

    var exchangeRate: Decimal? { lockedRate }

    var isForeign: Bool {
        selectedCurrencyCode != group.baseCurrencyCode
    }

    /// 預覽用：換算後的基準幣金額。
    var convertedTotal: Decimal? {
        guard let total = totalAmount else { return nil }
        if !isForeign { return total }
        guard let rate = lockedRate, rate > 0 else { return nil }
        return total * rate
    }

    var selectedMembers: [Member] {
        members.filter { selectedMemberIDs.contains($0.id) }
    }

    /// 每人均攤金額（使用者輸入幣別）= ceil(total / n)
    var evenSplitAmount: Decimal? {
        guard let total = totalAmount, !selectedMemberIDs.isEmpty else { return nil }
        let n = Decimal(selectedMemberIDs.count)
        let scale = Decimal.currencyFractionDigits(selectedCurrencyCode)
        var result = Decimal()
        var divided = total / n
        NSDecimalRound(&result, &divided, scale, .up)
        return result
    }

    var customAmountsSum: Decimal {
        customAmounts.values.compactMap { Decimal.parseAmount($0) }.reduce(0, +)
    }

    var hasAnyCustomInput: Bool {
        customAmounts.values.contains { !$0.isEmpty }
    }

    /// 把基準幣的拆帳金額還原成原始輸入幣別，並把進位殘值補到金額最大的那一筆，
    /// 使加總精確等於原始總額。
    ///
    /// 寫入時每筆 split 都已依基準幣進位，除回匯率後的加總幾乎不可能剛好等於原始總額
    /// （例：TWD 帳本、USD 21 元自訂 10.5/10.5、匯率 31.623 → 存 333/333 →
    /// 還原成 10.5303… 兩筆加總 21.0606 ≠ 21）。差額補在最大的一筆上，
    /// 代價是該筆可能與當初輸入差一個最小貨幣單位。
    static func restoreForeignSplits(
        baseAmounts: [(id: UUID, amount: Decimal)],
        rate: Decimal,
        originalTotal: Decimal,
        currencyCode: String
    ) -> [UUID: Decimal] {
        guard rate > 0, !baseAmounts.isEmpty else { return [:] }

        var restored = baseAmounts.map {
            (id: $0.id, amount: Decimal.round($0.amount / rate, in: currencyCode))
        }
        let sum = restored.reduce(Decimal(0)) { $0 + $1.amount }
        let residual = originalTotal - sum
        if residual != 0,
           let target = restored.indices.max(by: { restored[$0].amount < restored[$1].amount }) {
            restored[target].amount += residual
        }
        return Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0.amount) })
    }

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let total = totalAmount, total > 0 else { return false }
        guard selectedPayer != nil else { return false }
        guard !selectedMemberIDs.isEmpty else { return false }

        if !isEvenSplit {
            guard customAmountsSum == total else { return false }
        }

        // 外幣必須要有取得的匯率
        if isForeign {
            guard let rate = lockedRate, rate > 0 else { return false }
        }

        return true
    }

    init(group: Group, expense: Expense? = nil) {
        self.group = group
        self.existingExpense = expense
        self.selectedCurrencyCode = group.baseCurrencyCode
        // 新增花費時套用本裝置為此帳本設定的記帳預設幣種（如旅行時預設外幣）；
        // 編輯既有花費維持其原幣種（下方 if let expense 分支會覆寫）
        if expense == nil, let preferred = GroupPrefs.defaultInputCurrency(for: group.id) {
            self.selectedCurrencyCode = preferred
        }

        if let expense {
            title = expense.title
            // 既有花費若為外幣，回填使用者輸入幣別 + 原幣金額；否則用基準幣 totalAmount
            if expense.isForeignCurrency,
               let originalCode = expense.originalCurrencyCode,
               let originalAmt = expense.originalAmount,
               let rate = expense.exchangeRate {
                selectedCurrencyCode = originalCode
                totalAmountString = "\(originalAmt)"
                lockedRate = rate
            } else {
                totalAmountString = "\(expense.totalAmount)"
            }
            selectedPayer = expense.paidBy
            if let d = expense.date {
                date = d
                hasDate = true
            }
            note = expense.note ?? ""

            // 既有 splits 是基準幣；若是外幣花費需要除以匯率把 customAmounts 還原成原幣
            let restoreRate: Decimal = expense.isForeignCurrency ? (expense.exchangeRate ?? 1) : 1
            let amounts = expense.splits.compactMap { $0.amount }
            // 優先用明確保存的拆帳模式；舊資料（nil）才退回以「金額是否相等」推斷
            let inferredEven = !amounts.isEmpty && amounts.allSatisfy { $0 == amounts.first }
            isEvenSplit = expense.isEvenSplit ?? inferredEven

            if expense.isForeignCurrency, restoreRate > 0, let originalAmt = expense.originalAmount {
                // 外幣：splits 是「已進位的基準幣」，單純除回匯率加總不會等於原始總額，
                // isValid 的 customAmountsSum == total 因此永遠不成立 → 儲存鈕鎖死、無法重新編輯。
                let pairs = expense.splits.compactMap { split -> (id: UUID, amount: Decimal)? in
                    guard let member = split.member else { return nil }
                    selectedMemberIDs.insert(member.id)
                    return (member.id, split.amount)
                }
                let restored = Self.restoreForeignSplits(
                    baseAmounts: pairs,
                    rate: restoreRate,
                    originalTotal: originalAmt,
                    currencyCode: expense.originalCurrencyCode ?? selectedCurrencyCode
                )
                for (id, amount) in restored {
                    customAmounts[id] = "\(amount)"
                }
            } else {
                for split in expense.splits {
                    if let member = split.member {
                        selectedMemberIDs.insert(member.id)
                        customAmounts[member.id] = "\(split.amount)"
                    }
                }
            }
        } else {
            for member in group.members {
                selectedMemberIDs.insert(member.id)
            }
            selectedPayer = FirebaseSharingManager.shared.claimedMember(in: group) ?? group.members.first
        }
    }

    func toggleMember(_ member: Member) {
        if selectedMemberIDs.contains(member.id) {
            selectedMemberIDs.remove(member.id)
            customAmounts.removeValue(forKey: member.id)
        } else {
            selectedMemberIDs.insert(member.id)
            customAmounts[member.id] = ""
        }
    }

    var allMembersSelected: Bool {
        !members.isEmpty && selectedMemberIDs.count == members.count
    }

    /// 全選/全不選交替。全選時保留已選成員原本輸入的自訂金額。
    func toggleSelectAll() {
        if allMembersSelected {
            selectedMemberIDs.removeAll()
            customAmounts.removeAll()
        } else {
            for member in members where !selectedMemberIDs.contains(member.id) {
                selectedMemberIDs.insert(member.id)
                customAmounts[member.id] = ""
            }
        }
    }

    /// 切到外幣時自動抓「過去 5 日最低匯率」鎖定。失敗會把 rateFetchFailed 設成 true。
    @MainActor
    func refreshExchangeRate() async {
        if !isForeign {
            lockedRate = nil
            rateFetchFailed = false
            return
        }
        isFetchingRate = true
        rateFetchFailed = false
        defer { isFetchingRate = false }
        do {
            let rate = try await CurrencyService.shared.fetchLatestRate(
                from: selectedCurrencyCode,
                to: group.baseCurrencyCode
            )
            lockedRate = rate
        } catch {
            lockedRate = nil
            rateFetchFailed = true
        }
    }

    /// 儲存成功回傳 nil，失敗回傳錯誤訊息
    func save(modelContext: ModelContext, pushToCloud: Bool = false) -> String? {
        guard isValid,
              let total = totalAmount,
              let payer = selectedPayer else { return "資料不完整，請確認所有欄位已填寫" }

        // 計算實際存進 SwiftData 的基準幣金額 + metadata
        let rate: Decimal? = isForeign ? lockedRate : nil
        let baseTotal: Decimal = isForeign ? (total * (rate ?? 1)) : total
        let originalCode: String? = isForeign ? selectedCurrencyCode : nil
        let originalAmt: Decimal? = isForeign ? total : nil

        let wasNew = existingExpense == nil
        let expenseDate: Date? = hasDate ? date : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        let savedExpense: Expense
        if let existing = existingExpense {
            existing.title = title.trimmingCharacters(in: .whitespaces)
            existing.totalAmount = baseTotal
            existing.paidBy = payer
            existing.date = expenseDate
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote
            existing.originalCurrencyCode = originalCode
            existing.originalAmount = originalAmt
            existing.exchangeRate = rate

            for split in existing.splits {
                modelContext.delete(split)
            }
            existing.splits = []

            let newSplits = createSplits(originalTotal: total, rate: rate)
            for split in newSplits {
                modelContext.insert(split)
            }
            existing.splits.append(contentsOf: newSplits)
            savedExpense = existing
        } else {
            let expense = Expense(
                title: title.trimmingCharacters(in: .whitespaces),
                totalAmount: baseTotal,
                paidBy: payer,
                date: expenseDate,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            expense.originalCurrencyCode = originalCode
            expense.originalAmount = originalAmt
            expense.exchangeRate = rate
            modelContext.insert(expense)
            group.expenses.append(expense)

            let splits = createSplits(originalTotal: total, rate: rate)
            for split in splits {
                modelContext.insert(split)
            }
            expense.splits.append(contentsOf: splits)
            savedExpense = expense
        }
        savedExpense.isEvenSplit = isEvenSplit
        savedExpense.updatedAt = Date()
        savedExpense.lastEditorName = FirebaseSharingManager.shared.claimedMember(in: group)?.name

        do {
            try modelContext.save()
            if pushToCloud || group.isShared {
                let savedTitle = title.trimmingCharacters(in: .whitespaces)
                let baseCode = group.baseCurrencyCode
                let amountText = baseTotal.formatted(.currency(code: baseCode))
                let detailsText: String = {
                    if let oc = originalCode, let oa = originalAmt {
                        return "\(amountText)（\(oa.formatted(.currency(code: oc)))）"
                    }
                    return amountText
                }()
                let sharedGroup = group
                Task {
                    await FirebaseSharingManager.shared.pushInBackground {
                        try await FirebaseSharingManager.shared.pushExpense(savedExpense, in: sharedGroup)
                    }
                    await FirebaseSharingManager.shared.logActivity(
                        for: sharedGroup,
                        action: wasNew ? .addedExpense : .editedExpense,
                        target: savedTitle,
                        details: detailsText
                    )
                }
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private func createSplits(originalTotal: Decimal, rate: Decimal?) -> [ExpenseSplit] {
        var splits: [ExpenseSplit] = []
        let scale = Decimal.currencyFractionDigits(group.baseCurrencyCode)

        if isEvenSplit {
            let sortedSelected = selectedMembers.sorted { $0.name < $1.name }
            let n = sortedSelected.count
            // 用基準幣金額平分（避免「先平分原幣再換算」累積誤差比基準幣 ceil 還大）
            let baseTotal = (rate.map { originalTotal * $0 }) ?? originalTotal
            var perPerson = Decimal()
            var divided = baseTotal / Decimal(n)
            NSDecimalRound(&perPerson, &divided, scale, .up)

            for member in sortedSelected {
                splits.append(ExpenseSplit(member: member, amount: perPerson))
            }
        } else {
            for member in selectedMembers {
                let amountStr = customAmounts[member.id] ?? "0"
                let originalSplit = Decimal.parseAmount(amountStr) ?? 0
                let rawBase: Decimal = (rate.map { originalSplit * $0 }) ?? originalSplit
                // 進位到基準幣小數位，避免外幣換算後存入非法精度（例如 TWD 出現 4 位小數）
                let baseSplit = Decimal.round(rawBase, in: group.baseCurrencyCode)
                splits.append(ExpenseSplit(member: member, amount: baseSplit))
            }
        }

        return splits
    }
}
