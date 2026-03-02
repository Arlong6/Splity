import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var group: Group

    @State private var showingAddMember = false
    @State private var showingAddExpense = false
    @State private var showingSettlement = false
    @State private var showingSpreadsheet = false
    @State private var newMemberName = ""
    @State private var memberDeletionError: String?
    @State private var expenseToDelete: Expense?
    @State private var expenseToRename: Expense?
    @State private var renameExpenseText = ""

    var sortedMembers: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    var sortedExpenses: [Expense] {
        group.expenses.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
    }

    var totalExpenseAmount: Decimal {
        group.expenses.reduce(0) { $0 + $1.totalAmount }
    }

    var netBalances: [Member: Decimal] {
        SettlementCalculator.computeNetBalances(expenses: group.expenses)
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "TWD"
    }

    var body: some View {
        List {
            // MARK: - Members
            Section("成員") {
                ForEach(sortedMembers) { member in
                    memberRow(member)
                }
                .onDelete(perform: deleteMembers)

                Button {
                    showingAddMember = true
                } label: {
                    Label("新增成員", systemImage: "person.badge.plus")
                }
            }

            // MARK: - Expenses
            Section {
                if sortedExpenses.isEmpty {
                    Text("還沒有花費紀錄")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExpenses) { expense in
                        NavigationLink {
                            ExpenseEditView(group: group, expense: expense)
                        } label: {
                            ExpenseRowView(expense: expense)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                expenseToDelete = expense
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                renameExpenseText = expense.title
                                expenseToRename = expense
                            } label: {
                                Label("改名", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("花費紀錄")
                    Spacer()
                    if totalExpenseAmount > 0 {
                        Text(totalExpenseAmount, format: .currency(code: currencyCode))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingSpreadsheet = true } label: {
                    Label("表格", systemImage: "tablecells")
                }
                .disabled(group.expenses.isEmpty)

                Button { showingSettlement = true } label: {
                    Label("結算", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(group.expenses.isEmpty)

                Button { showingAddExpense = true } label: {
                    Label("新增花費", systemImage: "plus")
                }
                .disabled(group.members.count < 2)
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            NavigationStack {
                ExpenseEditView(group: group)
            }
        }
        .sheet(isPresented: $showingSettlement) {
            NavigationStack {
                SettlementView(group: group)
            }
        }
        .sheet(isPresented: $showingSpreadsheet) {
            NavigationStack {
                ExpenseSpreadsheetView(group: group)
            }
        }
        .alert("新增成員", isPresented: $showingAddMember) {
            TextField("名字", text: $newMemberName)
            Button("取消", role: .cancel) { newMemberName = "" }
            Button("加入") { addMember() }
        }
        .alert("無法刪除", isPresented: Binding(
            get: { memberDeletionError != nil },
            set: { if !$0 { memberDeletionError = nil } }
        )) {
            Button("好") { memberDeletionError = nil }
        } message: {
            Text(memberDeletionError ?? "")
        }
        .alert("確定刪除？", isPresented: Binding(
            get: { expenseToDelete != nil },
            set: { if !$0 { expenseToDelete = nil } }
        )) {
            Button("刪除", role: .destructive) {
                if let expense = expenseToDelete {
                    modelContext.delete(expense)
                    expenseToDelete = nil
                }
            }
            Button("取消", role: .cancel) { expenseToDelete = nil }
        } message: {
            Text("「\(expenseToDelete?.title ?? "")」刪除後無法復原")
        }
        .alert("改名", isPresented: Binding(
            get: { expenseToRename != nil },
            set: { if !$0 { expenseToRename = nil } }
        )) {
            TextField("花費名稱", text: $renameExpenseText)
            Button("取消", role: .cancel) { expenseToRename = nil }
            Button("確認") { confirmExpenseRename() }
        }
    }

    // MARK: - Member Row

    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(String(member.name.prefix(1)))
                    .font(.subheadline.bold())
                    .foregroundStyle(.indigo)
            }

            Text(member.name)

            Spacer()

            if !group.expenses.isEmpty {
                let balance = netBalances[member] ?? 0
                if balance == 0 {
                    Text("已平衡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let isPositive = balance > 0
                    let absBalance = Decimal.roundForCurrentCurrency(isPositive ? balance : -balance)
                    Text(absBalance, format: .currency(code: currencyCode))
                        .font(.caption.bold())
                        .foregroundStyle(isPositive ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isPositive ? Color.green : Color.red).opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func addMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !group.members.contains(where: { $0.name == trimmed }) else { return }
        let member = Member(name: trimmed)
        modelContext.insert(member)
        group.members.append(member)
        newMemberName = ""
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = sortedMembers[index]
            let hasExpenses = group.expenses.contains { expense in
                expense.paidBy == member ||
                expense.splits.contains { $0.member == member }
            }
            if hasExpenses {
                memberDeletionError = "\(member.name) 有關聯的花費紀錄，無法刪除。請先刪除相關花費。"
                return
            }
            modelContext.delete(member)
        }
    }

    private func confirmExpenseRename() {
        let trimmed = renameExpenseText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let expense = expenseToRename else { return }
        expense.title = trimmed
        expenseToRename = nil
    }
}

// MARK: - Expense Row

struct ExpenseRowView: View {
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(expense.title)
                    .font(.headline)
                Spacer()
                Text(expense.totalAmount, format: .currency(code: currencyCode))
                    .font(.headline)
            }
            HStack {
                Text("\(expense.paidBy?.name ?? "未知") 先付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let date = expense.date {
                    Text(date, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "TWD"
    }
}
