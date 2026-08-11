import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FirebaseSharingManager.self) private var sharingManager
    @Bindable var group: Group

    @State private var showingAddMember = false
    @State private var showingAddExpense = false
    @State private var showingSettlement = false
    @State private var showingSpreadsheet = false
    @State private var showingShareSheet = false
    @State private var inviteCode: String?
    @State private var isShareLoading = false
    @State private var showingParticipants = false
    @State private var newMemberName = ""
    @State private var memberDeletionError: String?
    @State private var expenseToDelete: Expense?
    @State private var expenseToRename: Expense?
    @State private var renameExpenseText = ""
    @State private var saveError: String?
    @State private var syncError: String?

    @State private var showingActivityLog = false
    @State private var subscription: SharingSubscription?
    @State private var showingClaimPicker = false
    @State private var claimForShare = false
    @State private var showingChangeBase = false

    var sortedMembers: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    var sortedExpenses: [Expense] {
        group.expenses.filter { !$0.archived }.sorted { $0.totalAmount > $1.totalAmount }
    }

    var totalExpenseAmount: Decimal {
        group.expenses.filter { !$0.archived }.reduce(0) { $0 + $1.totalAmount }
    }

    var netBalances: [Member: Decimal] {
        SettlementCalculator.computeNetBalances(expenses: group.expenses.filter { !$0.archived })
    }

    private var currencyCode: String {
        group.baseCurrencyCode
    }

    var body: some View {
        mainList
            .navigationTitle(group.name)
            .toolbar { toolbarContent }
            .modifier(sheetsModifier)
            .modifier(alertsModifier)
            .onAppear {
                if group.isShared, subscription == nil {
                    subscription = sharingManager.listenToChanges(for: group, modelContext: modelContext)
                }
                if group.isShared, sharingManager.claimedMember(in: group) == nil {
                    claimForShare = false
                    showingClaimPicker = true
                }
            }
            .onDisappear {
                subscription?.stop()
                subscription = nil
            }
    }

    private var mainList: some View {
        List {
            membersSection
            expensesSection
        }
        .refreshable { await refreshFromCloud() }
    }

    private func refreshFromCloud() async {
        guard group.isShared else { return }
        do {
            try await sharingManager.pullChanges(for: group, modelContext: modelContext)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private var membersSection: some View {
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
    }

    @ViewBuilder
    private var expensesSection: some View {
        Section {
            if sortedExpenses.isEmpty {
                Text("還沒有花費紀錄")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedExpenses) { expense in
                    expenseRow(expense)
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

    private func expenseRow(_ expense: Expense) -> some View {
        NavigationLink {
            ExpenseEditView(group: group, expense: expense)
        } label: {
            ExpenseRowView(expense: expense, baseCurrencyCode: group.baseCurrencyCode)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                expenseToDelete = expense
            } label: {
                Label("刪除", systemImage: "trash")
            }
            .tint(.red)
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

    private var sheetsModifier: some ViewModifier {
        GroupDetailSheets(
            group: group,
            sharingManager: sharingManager,
            showingAddExpense: $showingAddExpense,
            showingSettlement: $showingSettlement,
            showingSpreadsheet: $showingSpreadsheet,
            showingShareSheet: $showingShareSheet,
            showingActivityLog: $showingActivityLog,
            showingClaimPicker: $showingClaimPicker,
            claimForShare: $claimForShare,
            showingChangeBase: $showingChangeBase,
            inviteCode: inviteCode,
            onClaimSelected: onClaimSelected
        )
    }

    private var alertsModifier: some ViewModifier {
        GroupDetailAlerts(
            showingAddMember: $showingAddMember,
            newMemberName: $newMemberName,
            memberDeletionError: $memberDeletionError,
            expenseToDelete: $expenseToDelete,
            expenseToRename: $expenseToRename,
            renameExpenseText: $renameExpenseText,
            saveError: $saveError,
            syncError: $syncError,
            onAddMember: addMember,
            onConfirmDelete: confirmExpenseDelete,
            onConfirmRename: confirmExpenseRename
        )
    }

    private func confirmExpenseDelete() {
        guard let expense = expenseToDelete else { return }
        let title = expense.title
        expense.archived = true
        expense.deletedAt = Date()
        // 每條會推送的變更路徑都要 bump updatedAt，否則帶舊時間戳的推送會被
        // 其他裝置的 LWW 合併防護當成舊資料丟棄（刪除被復活）
        expense.updatedAt = Date()
        expense.lastEditorName = sharingManager.claimedMember(in: group)?.name
        expenseToDelete = nil
        saveAndPush(expense)
        logAction(.deletedExpense, target: title)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            shareButton
            Menu {
                Button {
                    showingChangeBase = true
                } label: {
                    Label("結算幣別：\(group.baseCurrencyCode)", systemImage: "dollarsign.arrow.circlepath")
                }
                if group.isShared {
                    Button { showingActivityLog = true } label: {
                        Label("變更紀錄", systemImage: "clock.arrow.circlepath")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Button { showingSpreadsheet = true } label: {
                Label("表格", systemImage: "tablecells")
            }
            .disabled(activeExpensesEmpty)

            Button { showingSettlement = true } label: {
                Label("結算", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(activeExpensesEmpty)

            Button { showingAddExpense = true } label: {
                Label("新增花費", systemImage: "plus")
            }
            .disabled(group.members.count < 2)
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        Button {
            triggerShare()
        } label: {
            if isShareLoading {
                ProgressView()
            } else {
                Label("分享", systemImage: group.isShared ? "person.2.fill" : "person.badge.plus")
            }
        }
        .disabled(group.isSettled)
    }

    private var activeExpensesEmpty: Bool {
        group.expenses.filter { !$0.archived }.isEmpty
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

            if !group.expenses.filter({ !$0.archived }).isEmpty {
                let balance = netBalances[member] ?? 0
                if balance == 0 {
                    Text("已平衡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let isPositive = balance > 0
                    let absBalance = Decimal.round(isPositive ? balance : -balance, in: currencyCode)
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
        save()
        logAction(.addedMember, target: trimmed)
    }

    private func deleteMembers(at offsets: IndexSet) {
        var removedNames: [String] = []
        for index in offsets {
            let member = sortedMembers[index]
            if member.claimedByUid != nil {
                memberDeletionError = "\(member.name) 已綁定身份，無法刪除。"
                return
            }
            // 含「已封存（軟刪除）」花費一起檢查：否則刪掉此成員後，日後從歷史還原該花費
            // 會因 paidBy 被 nullify、splits 被 cascade 刪除而資料毀損。
            let hasExpenses = group.expenses.contains { expense in
                expense.paidBy == member ||
                expense.splits.contains { $0.member == member }
            }
            if hasExpenses {
                memberDeletionError = "\(member.name) 有關聯的花費紀錄（含已刪除），無法刪除。請先永久刪除相關花費。"
                return
            }
            removedNames.append(member.name)
            modelContext.delete(member)
        }
        save()
        for name in removedNames {
            logAction(.removedMember, target: name)
        }
    }

    private func confirmExpenseRename() {
        let trimmed = renameExpenseText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let expense = expenseToRename else { return }
        let oldTitle = expense.title
        expense.title = trimmed
        expense.updatedAt = Date()
        expense.lastEditorName = sharingManager.claimedMember(in: group)?.name
        expenseToRename = nil
        saveAndPush(expense)
        logAction(.renamedExpense, target: trimmed, details: oldTitle == trimmed ? nil : "原：\(oldTitle)")
    }

    private func triggerShare() {
        guard !isShareLoading else { return }
        isShareLoading = true
        Task {
            try? await sharingManager.signInAnonymously()
            await MainActor.run {
                isShareLoading = false
                if sharingManager.claimedMember(in: group) == nil {
                    claimForShare = true
                    showingClaimPicker = true
                } else {
                    performShare()
                }
            }
        }
    }

    private func onClaimSelected() {
        showingClaimPicker = false
        if claimForShare {
            claimForShare = false
            performShare()
        }
    }

    private func performShare() {
        isShareLoading = true
        Task {
            do {
                let code = try await sharingManager.createInviteCode(for: group)
                try? modelContext.save()
                inviteCode = code
                showingShareSheet = true
                if subscription == nil {
                    subscription = sharingManager.listenToChanges(for: group, modelContext: modelContext)
                }
            } catch {
                syncError = error.localizedDescription
            }
            isShareLoading = false
        }
    }

    private func logAction(_ action: ActivityAction, target: String, details: String? = nil) {
        guard group.isShared else { return }
        Task {
            await sharingManager.logActivity(
                for: group,
                action: action,
                target: target,
                details: details
            )
        }
    }

    /// 儲存並推送「群組層級」變更（成員/結算/名稱），不重寫花費，避免 clobber 併發編輯。
    private func save() {
        do {
            try modelContext.save()
            if group.isShared {
                Task {
                    do {
                        try await sharingManager.pushGroupMeta(for: group)
                    } catch {
                        syncError = "同步失敗：\(error.localizedDescription)"
                    }
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 儲存並僅推送「這一筆」花費（granular），用於刪除/改名單筆花費，避免重寫全部花費。
    private func saveAndPush(_ expense: Expense) {
        do {
            try modelContext.save()
            if group.isShared {
                Task {
                    do {
                        try await sharingManager.pushExpense(expense, in: group)
                    } catch {
                        syncError = "同步失敗：\(error.localizedDescription)"
                    }
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Expense Row

struct ExpenseRowView: View {
    let expense: Expense
    let baseCurrencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(expense.title)
                    .font(.headline)
                Spacer()
                Text(expense.totalAmount, format: .currency(code: baseCurrencyCode))
                    .font(.headline)
            }
            HStack {
                Text("\(expense.paidBy?.name ?? "未知") 先付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if expense.isForeignCurrency,
                   let oc = expense.originalCurrencyCode,
                   let oa = expense.originalAmount {
                    Text("・\(oa, format: .currency(code: oc))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let date = expense.date {
                    Text(date, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 編輯者資訊:只在有編輯者(=共享帳本的編輯)時顯示,本地單人帳本保持乾淨
            if let editor = expense.lastEditorName, !editor.isEmpty {
                HStack(spacing: 4) {
                    Text("\(editor) · 編輯")
                    Text(expense.updatedAt ?? expense.createdAt, format: .dateTime.month().day())
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Activity View

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Sheets Modifier

private struct GroupDetailSheets: ViewModifier {
    let group: Group
    let sharingManager: FirebaseSharingManager
    @Binding var showingAddExpense: Bool
    @Binding var showingSettlement: Bool
    @Binding var showingSpreadsheet: Bool
    @Binding var showingShareSheet: Bool
    @Binding var showingActivityLog: Bool
    @Binding var showingClaimPicker: Bool
    @Binding var claimForShare: Bool
    @Binding var showingChangeBase: Bool
    let inviteCode: String?
    var onClaimSelected: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddExpense) {
                NavigationStack { ExpenseEditView(group: group) }
            }
            .sheet(isPresented: $showingSettlement) {
                NavigationStack { SettlementView(group: group) }
                    .environment(sharingManager)
            }
            .sheet(isPresented: $showingSpreadsheet) {
                NavigationStack { ExpenseSpreadsheetView(group: group) }
                    .environment(sharingManager)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let code = inviteCode {
                    InviteShareSheet(groupName: group.name, inviteCode: code)
                }
            }
            .sheet(isPresented: $showingActivityLog) {
                ActivityLogView(group: group)
                    .environment(sharingManager)
            }
            .sheet(isPresented: $showingClaimPicker) {
                MemberClaimView(
                    group: group,
                    onClaim: { _ in onClaimSelected() },
                    onSkip: claimForShare ? nil : { claimForShare = false }
                )
                .environment(sharingManager)
                .interactiveDismissDisabled(claimForShare)
            }
            .sheet(isPresented: $showingChangeBase) {
                ChangeBaseCurrencyView(group: group)
                    .environment(sharingManager)
            }
    }
}

// MARK: - Alerts Modifier

private struct GroupDetailAlerts: ViewModifier {
    @Binding var showingAddMember: Bool
    @Binding var newMemberName: String
    @Binding var memberDeletionError: String?
    @Binding var expenseToDelete: Expense?
    @Binding var expenseToRename: Expense?
    @Binding var renameExpenseText: String
    @Binding var saveError: String?
    @Binding var syncError: String?
    var onAddMember: () -> Void
    var onConfirmDelete: () -> Void
    var onConfirmRename: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("新增成員", isPresented: $showingAddMember) {
                TextField("名字", text: $newMemberName)
                Button("取消", role: .cancel) { newMemberName = "" }
                Button("加入") { onAddMember() }
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
                Button("刪除", role: .destructive) { onConfirmDelete() }
                Button("取消", role: .cancel) { expenseToDelete = nil }
            } message: {
                Text("「\(expenseToDelete?.title ?? "")」將移至已刪除，可在歷史紀錄中還原")
            }
            .alert("改名", isPresented: Binding(
                get: { expenseToRename != nil },
                set: { if !$0 { expenseToRename = nil } }
            )) {
                TextField("花費名稱", text: $renameExpenseText)
                Button("取消", role: .cancel) { expenseToRename = nil }
                Button("確認") { onConfirmRename() }
            }
            .alert("儲存失敗", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .alert("同步失敗", isPresented: Binding(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("好") { syncError = nil }
            } message: {
                Text(syncError ?? "")
            }
    }
}
