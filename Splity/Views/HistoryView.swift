import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HistoryRecord.date, order: .reverse) private var records: [HistoryRecord]
    @Query(
        filter: #Predicate<Expense> { $0.archived == true },
        sort: \Expense.deletedAt,
        order: .reverse
    ) private var deletedExpenses: [Expense]

    private func currencyCode(for expense: Expense) -> String {
        expense.group?.baseCurrencyCode ?? Locale.current.currency?.identifier ?? "TWD"
    }

    var body: some View {
        NavigationStack {
            List {
                // ── 已刪除的花費 ────────────────────────────────────────────
                if !deletedExpenses.isEmpty {
                    Section {
                        ForEach(deletedExpenses) { expense in
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(expense.title)
                                        .font(.headline)
                                    HStack(spacing: 4) {
                                        Text(expense.totalAmount, format: .currency(code: currencyCode(for: expense)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let deletedAt = expense.deletedAt {
                                            Text("・\(deletedAt, format: .dateTime.month().day())")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                Button("還原") {
                                    expense.archived = false
                                    expense.deletedAt = nil
                                    expense.updatedAt = Date()
                                    if let g = expense.group {
                                        expense.lastEditorName = FirebaseSharingManager.shared.claimedMember(in: g)?.name
                                    }
                                    try? modelContext.save()
                                    if let g = expense.group, g.isShared {
                                        let title = expense.title
                                        Task {
                                            try? await FirebaseSharingManager.shared.pushExpense(expense, in: g)
                                            await FirebaseSharingManager.shared.logActivity(
                                                for: g, action: .restoredExpense, target: title)
                                        }
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.indigo)
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            offsets.forEach { i in
                                let expense = deletedExpenses[i]
                                // 共享帳本要先在雲端立墓碑,否則下次同步又長回來
                                if let g = expense.group, g.isShared, let fid = g.firestoreGroupId {
                                    let eid = expense.id.uuidString
                                    Task {
                                        await FirebaseSharingManager.shared.purgeExpense(
                                            expenseId: eid, groupFirestoreId: fid)
                                    }
                                }
                                modelContext.delete(expense)
                            }
                        }
                    } header: {
                        Text("已刪除的花費")
                    } footer: {
                        Text("左滑可永久刪除")
                    }
                }

                // ── 帳本歷史紀錄 ────────────────────────────────────────────
                if !records.isEmpty {
                    Section("帳本紀錄") {
                        ForEach(records) { record in
                            HStack(spacing: 12) {
                                Image(systemName: record.action == .settled
                                      ? "checkmark.circle.fill"
                                      : "trash.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(record.action == .settled ? .green : .red)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.groupName)
                                        .font(.headline)
                                    Text("\(record.memberCount) 人・\(record.expenseCount) 筆花費")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(record.date, format: .dateTime.year().month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            offsets.forEach { modelContext.delete(records[$0]) }
                        }
                    }
                }
            }
            .overlay {
                if records.isEmpty && deletedExpenses.isEmpty {
                    ContentUnavailableView(
                        "沒有歷史紀錄",
                        systemImage: "clock",
                        description: Text("結清或刪除帳目後會出現紀錄")
                    )
                }
            }
            .navigationTitle("歷史紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("清除全部") {
                            records.forEach { modelContext.delete($0) }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
