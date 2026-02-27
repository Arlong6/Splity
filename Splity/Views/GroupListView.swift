import SwiftUI
import SwiftData

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Group.createdAt, order: .reverse) private var groups: [Group]

    @AppStorage("appLanguage") private var appLanguage = "zh-Hant"

    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var groupToRename: Group?
    @State private var renameText = ""
    @State private var showingHistory = false

    private var activeGroups: [Group] { groups.filter { !$0.isSettled } }
    private var settledGroups: [Group] { groups.filter { $0.isSettled } }

    var body: some View {
        NavigationStack {
            List {
                // 統計 Header
                Section {
                    statsHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                // 進行中
                if !activeGroups.isEmpty {
                    Section("進行中") {
                        ForEach(activeGroups) { group in
                            NavigationLink(value: group) {
                                groupRow(group)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    let record = HistoryRecord(
                                        groupName: group.name,
                                        memberCount: group.members.count,
                                        expenseCount: group.expenses.count,
                                        action: .deleted
                                    )
                                    modelContext.insert(record)
                                    modelContext.delete(group)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                                Button {
                                    let record = HistoryRecord(
                                        groupName: group.name,
                                        memberCount: group.members.count,
                                        expenseCount: group.expenses.count,
                                        action: .settled
                                    )
                                    modelContext.insert(record)
                                    group.isSettled = true
                                } label: {
                                    Label("已結清", systemImage: "checkmark.seal")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    renameText = group.name
                                    groupToRename = group
                                } label: {
                                    Label("改名", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                // 已結清
                if !settledGroups.isEmpty {
                    Section("已結清") {
                        ForEach(settledGroups) { group in
                            NavigationLink(value: group) {
                                groupRow(group)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    let record = HistoryRecord(
                                        groupName: group.name,
                                        memberCount: group.members.count,
                                        expenseCount: group.expenses.count,
                                        action: .deleted
                                    )
                                    modelContext.insert(record)
                                    modelContext.delete(group)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                                Button {
                                    group.isSettled = false
                                } label: {
                                    Label("取消結清", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    renameText = group.name
                                    groupToRename = group
                                } label: {
                                    Label("改名", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "還沒有帳本",
                        systemImage: "person.3",
                        description: Text("點右上角 + 建立一個新的帳本")
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddGroup = true } label: {
                        Label("新增帳目", systemImage: "plus.circle.fill")
                    }
                }
                ToolbarItemGroup(placement: .navigation) {
                    Button { showingHistory = true } label: {
                        Label("歷史紀錄", systemImage: "clock.arrow.circlepath")
                    }
                    Menu {
                        Button(action: { appLanguage = "zh-Hant" }) {
                            if appLanguage == "zh-Hant" {
                                Label("繁體中文", systemImage: "checkmark")
                            } else {
                                Text("繁體中文")
                            }
                        }
                        Button(action: { appLanguage = "en" }) {
                            if appLanguage == "en" {
                                Label("English", systemImage: "checkmark")
                            } else {
                                Text("English")
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            .navigationDestination(for: Group.self) { group in
                GroupDetailView(group: group)
            }
            .alert("新增帳目", isPresented: $showingAddGroup) {
                TextField("帳目名稱", text: $newGroupName)
                Button("取消", role: .cancel) { newGroupName = "" }
                Button("建立") { addGroup() }
            }
            .alert("重新命名", isPresented: Binding(
                get: { groupToRename != nil },
                set: { if !$0 { groupToRename = nil } }
            )) {
                TextField("帳目名稱", text: $renameText)
                Button("取消", role: .cancel) { groupToRename = nil }
                Button("確認") { confirmRename() }
            } message: {
                Text("請輸入新的帳本名稱")
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Splity")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                statBadge(
                    icon: "folder.fill",
                    value: "\(activeGroups.count)",
                    label: "進行中"
                )
                statBadge(
                    icon: "checkmark.seal.fill",
                    value: "\(settledGroups.count)",
                    label: "已結清"
                )
                statBadge(
                    icon: "yensign",
                    value: "\(groups.reduce(0) { $0 + $1.expenses.count })",
                    label: "筆花費"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Group Row

    private func groupRow(_ group: Group) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(group.isSettled ? Color.green.opacity(0.12) : Color.indigo.opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: group.isSettled ? "checkmark.seal.fill" : "person.3.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(group.isSettled ? .green : .indigo)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(group.isSettled ? .secondary : .primary)
                Text("\(group.members.count) 人・\(group.expenses.count) 筆花費")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func addGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(Group(name: trimmed))
        newGroupName = ""
    }

    private func confirmRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let group = groupToRename else { return }
        group.name = trimmed
        groupToRename = nil
    }
}
