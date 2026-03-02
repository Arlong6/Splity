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

    // Split config
    var isEvenSplit = true
    var selectedMemberIDs: Set<UUID> = []
    var customAmounts: [UUID: String] = [:]

    var members: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    var totalAmount: Decimal? {
        Decimal(string: totalAmountString)
    }

    var selectedMembers: [Member] {
        members.filter { selectedMemberIDs.contains($0.id) }
    }

    /// 每人基本份額 = floor(total / n)，最小份額
    var evenSplitAmount: Decimal? {
        guard let total = totalAmount, !selectedMemberIDs.isEmpty else { return nil }
        let n = Decimal(selectedMemberIDs.count)
        let scale = Decimal.currencyFractionDigits(Locale.current.currency?.identifier ?? "TWD")
        var base = Decimal()
        var divided = total / n
        NSDecimalRound(&base, &divided, scale, .down)
        return base
    }

    /// 部分人需多付的金額 = base + 1 unit；若能整除則為 nil
    var evenSplitUpperAmount: Decimal? {
        guard let total = totalAmount,
              let base = evenSplitAmount,
              !selectedMemberIDs.isEmpty else { return nil }
        guard total != base * Decimal(selectedMemberIDs.count) else { return nil }
        let scale = Decimal.currencyFractionDigits(Locale.current.currency?.identifier ?? "TWD")
        let unit = Decimal(sign: .plus, exponent: -scale, significand: 1)
        return base + unit
    }

    var customAmountsSum: Decimal {
        customAmounts.values.compactMap { Decimal(string: $0) }.reduce(0, +)
    }

    var hasAnyCustomInput: Bool {
        customAmounts.values.contains { !$0.isEmpty }
    }

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let total = totalAmount, total > 0 else { return false }
        guard selectedPayer != nil else { return false }
        guard !selectedMemberIDs.isEmpty else { return false }

        if !isEvenSplit {
            guard customAmountsSum == total else { return false }
        }

        return true
    }

    init(group: Group, expense: Expense? = nil) {
        self.group = group
        self.existingExpense = expense

        if let expense {
            title = expense.title
            totalAmountString = "\(expense.totalAmount)"
            selectedPayer = expense.paidBy
            if let d = expense.date {
                date = d
                hasDate = true
            }
            note = expense.note ?? ""

            let amounts = expense.splits.compactMap { $0.amount }
            let allEqual = !amounts.isEmpty && amounts.allSatisfy { $0 == amounts.first }
            isEvenSplit = allEqual

            for split in expense.splits {
                if let member = split.member {
                    selectedMemberIDs.insert(member.id)
                    customAmounts[member.id] = "\(split.amount)"
                }
            }
        } else {
            for member in group.members {
                selectedMemberIDs.insert(member.id)
            }
            selectedPayer = group.members.first
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

    func save(modelContext: ModelContext) -> Bool {
        guard isValid else { return false }

        let total = totalAmount!
        let expenseDate: Date? = hasDate ? date : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)

        if let existing = existingExpense {
            existing.title = title.trimmingCharacters(in: .whitespaces)
            existing.totalAmount = total
            existing.paidBy = selectedPayer
            existing.date = expenseDate
            existing.note = trimmedNote.isEmpty ? nil : trimmedNote

            for split in existing.splits {
                modelContext.delete(split)
            }
            existing.splits = []

            let newSplits = createSplits(total: total)
            for split in newSplits {
                modelContext.insert(split)
            }
            existing.splits.append(contentsOf: newSplits)
        } else {
            let expense = Expense(
                title: title.trimmingCharacters(in: .whitespaces),
                totalAmount: total,
                paidBy: selectedPayer!,
                date: expenseDate,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            modelContext.insert(expense)
            group.expenses.append(expense)

            let splits = createSplits(total: total)
            for split in splits {
                modelContext.insert(split)
            }
            expense.splits.append(contentsOf: splits)
        }

        return true
    }

    private func createSplits(total: Decimal) -> [ExpenseSplit] {
        var splits: [ExpenseSplit] = []

        if isEvenSplit {
            let sortedSelected = selectedMembers.sorted { $0.name < $1.name }
            let n = sortedSelected.count
            let scale = Decimal.currencyFractionDigits(Locale.current.currency?.identifier ?? "TWD")
            let unit = Decimal(sign: .plus, exponent: -scale, significand: 1) // 1 TWD 或 $0.01

            // base = floor(total / n)
            var base = Decimal()
            var divided = total / Decimal(n)
            NSDecimalRound(&base, &divided, scale, .down)

            // 需要多付 1 unit 的人數 = (total - base×n) / unit
            var remainderCount = Decimal()
            var ratio = (total - base * Decimal(n)) / unit
            NSDecimalRound(&remainderCount, &ratio, 0, .plain)
            let extraCount = Int(NSDecimalNumber(decimal: remainderCount).intValue)

            // 前 extraCount 人付 base+unit，其餘付 base
            // 任意兩人之間最多差 1 unit
            for (index, member) in sortedSelected.enumerated() {
                let amount = index < extraCount ? base + unit : base
                splits.append(ExpenseSplit(member: member, amount: amount))
            }
        } else {
            for member in selectedMembers {
                let amountStr = customAmounts[member.id] ?? "0"
                let amount = Decimal(string: amountStr) ?? 0
                splits.append(ExpenseSplit(member: member, amount: amount))
            }
        }

        return splits
    }
}
