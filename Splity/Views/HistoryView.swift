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

    @State private var actionError: String?

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

                                Button("還原") { restore(expense) }
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
            .alert("還原失敗", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("好") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    /// 還原一筆已刪除的花費。本地儲存與雲端推送任一失敗都要讓使用者知道——
    /// 原本兩者都被 try? 吞掉，使用者會以為還原成功。
    private func restore(_ expense: Expense) {
        expense.archived = false
        expense.deletedAt = nil
        expense.updatedAt = Date()
        if let g = expense.group {
            expense.lastEditorName = FirebaseSharingManager.shared.claimedMember(in: g)?.name
        }
        do {
            try modelContext.save()
        } catch {
            actionError = error.localizedDescription
            return
        }

        guard let g = expense.group, g.isShared else { return }
        let title = expense.title
        Task {
            do {
                try await FirebaseSharingManager.shared.pushExpense(expense, in: g)
            } catch {
                actionError = error.localizedDescription
                return
            }
            await FirebaseSharingManager.shared.logActivity(
                for: g, action: .restoredExpense, target: title)
        }
    }
}
