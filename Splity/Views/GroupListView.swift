import SwiftUI
import SwiftData

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Group.createdAt, order: .reverse) private var groups: [Group]

    @Environment(FirebaseSharingManager.self) private var sharingManager

    @AppStorage("appLanguage") private var appLanguage = "zh-Hant"

    @State private var showingAddGroup = false
    @State private var showingJoinCode = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var newGroupName = ""
    @State private var newGroupBaseCurrency: String = Locale.current.currency?.identifier ?? "TWD"
    @State private var groupToRename: Group?
    @State private var renameText = ""
    @State private var showingHistory = false
    @State private var joinSuccess = false
    @State private var saveError: String?
    @State private var updateChecker = AppUpdateChecker.shared
    @State private var groupToDelete: Group?
    @State private var groupToSettle: Group?
    @State private var unreadGroupIds: Set<UUID> = []

    private var activeGroups: [Group] { groups.filter { !$0.isSettled } }
    private var settledGroups: [Group] { groups.filter { $0.isSettled } }

    var body: some View {
        NavigationStack {
            groupList
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingHistory) {
                    HistoryView()
                }
                .navigationDestination(for: Group.self) { group in
                    GroupDetailView(group: group)
                }
                .onAppear {
                    updateWidget()
                    refreshUnread()
                    // 有共享帳本才要通知權限（背景活動通知用）；授權框只會跳一次
                    if groups.contains(where: { $0.isShared }) {
                        ActivityNotifier.requestPermissionIfNeeded()
                    }
                }
                .task { await updateChecker.checkIfNeeded() }
                .alert("有新版本可用", isPresented: $updateChecker.updateAvailable) {
                    Button("前往更新") { updateChecker.openAppStore() }
                    Button("稍後再說", role: .cancel) { updateChecker.skipCurrentVersion() }
                } message: {
                    Text("Splity \(updateChecker.storeVersion ?? "") 已上架，建議更新以獲得最新功能")
                }
                .sheet(isPresented: $showingAddGroup) {
                    AddGroupSheet(
                        name: $newGroupName,
                        baseCurrency: $newGroupBaseCurrency,
                        onCreate: { addGroup() },
                        onCancel: {
                            newGroupName = ""
                            showingAddGroup = false
                        }
                    )
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
                .alert("儲存失敗", isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )) {
                    Button("好") { saveError = nil }
                } message: {
                    Text(saveError ?? "")
                }
                .alert(groupToDelete?.isShared == true ? "離開帳目？" : "刪除帳目？",
                       isPresented: Binding(
                           get: { groupToDelete != nil },
                           set: { if !$0 { groupToDelete = nil } }
                       )) {
                    Button(groupToDelete?.isShared == true ? "離開" : "刪除",
                           role: .destructive) { confirmDeleteGroup() }
                    Button("取消", role: .cancel) { groupToDelete = nil }
                } message: {
                    if groupToDelete?.isShared == true {
                        Text("從這個裝置移除「\(groupToDelete?.name ?? "")」。其他成員不受影響，之後可用邀請碼重新加入。")
                    } else {
                        Text("「\(groupToDelete?.name ?? "")」會被永久刪除。")
                    }
                }
                .alert("標記為結清？", isPresented: Binding(
                    get: { groupToSettle != nil },
                    set: { if !$0 { groupToSettle = nil } }
                )) {
                    Button("結清") {
                        if let group = groupToSettle { performSettle(group) }
                        groupToSettle = nil
                    }
                    Button("取消", role: .cancel) { groupToSettle = nil }
                } message: {
                    Text("整本帳會標記為結清，所有成員都會看到並收到通知。之後可隨時取消結清。")
                }
                .modifier(JoinCodeAlerts(
                    showingJoinCode: $showingJoinCode,
                    joinCode: $joinCode,
                    joinError: $joinError,
                    joinSuccess: $joinSuccess,
                    isJoining: $isJoining,
                    onJoin: { handleJoinCode() }
                ))
        }
    }

    // MARK: - Group List

    private var groupList: some View {
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

            // 加入邀請碼
            Section {
                Button {
                    showingJoinCode = true
                } label: {
                    Label("輸入邀請碼加入帳目", systemImage: "ticket")
                        .foregroundStyle(.blue)
                }
                .disabled(isJoining)
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
                                groupToDelete = group
                            } label: {
                                Label(group.isShared ? "離開" : "刪除",
                                      systemImage: group.isShared ? "rectangle.portrait.and.arrow.right" : "trash")
                            }
                            Button {
                                // 共享帳本先確認(全員生效的動作);本地帳本直接結清
                                if group.isShared {
                                    groupToSettle = group
                                } else {
                                    performSettle(group)
                                }
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
                                groupToDelete = group
                            } label: {
                                Label(group.isShared ? "離開" : "刪除",
                                      systemImage: group.isShared ? "rectangle.portrait.and.arrow.right" : "trash")
                            }
                            Button {
                                group.isSettled = false
                                save()
                                pushMetaIfShared(group, logging: .unsettledGroup)
                                updateWidget()
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
        .overlay {
            if isJoining {
                ProgressView("加入中…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - Join Code Handling

    private func handleJoinCode() {
        let code = joinCode.trimmingCharacters(in: .whitespaces)
        joinCode = ""
        guard !code.isEmpty else { return }
        let validChars = CharacterSet(charactersIn: "ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let upperCode = code.uppercased()
        guard upperCode.count == 6, upperCode.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            joinError = "邀請碼格式不正確，請輸入 6 碼英數字"
            return
        }
        isJoining = true
        Task {
            do {
                let ctx = modelContext
                try await sharingManager.joinByInviteCode(upperCode, modelContext: ctx)
                joinSuccess = true
            } catch {
                joinError = error.localizedDescription
            }
            isJoining = false
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
                    value: "\(groups.reduce(0) { $0 + $1.expenses.filter { !$0.archived }.count })",
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
                    .fill(group.isSettled ? Color.green.opacity(0.12)
                          : group.isShared ? Color.blue.opacity(0.1)
                          : Color.indigo.opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: group.isSettled ? "checkmark.seal.fill"
                      : group.isShared ? "person.2.fill"
                      : "person.3.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(group.isSettled ? .green
                                    : group.isShared ? .blue
                                    : .indigo)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(group.isSettled ? .secondary : .primary)
                    if group.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if unreadGroupIds.contains(group.id) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("有新活動")
                    }
                }
                Text("\(group.members.count) 人・\(group.expenses.filter { !$0.archived }.count) 筆花費")
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
        modelContext.insert(Group(name: trimmed, baseCurrencyCode: newGroupBaseCurrency))
        newGroupName = ""
        showingAddGroup = false
        save()
        updateWidget()
    }

    private func confirmRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let group = groupToRename else { return }
        group.name = trimmed
        groupToRename = nil
        save()
        pushMetaIfShared(group)
    }

    private func performSettle(_ group: Group) {
        let record = HistoryRecord(
            groupName: group.name,
            memberCount: group.members.count,
            expenseCount: group.expenses.count,
            action: .settled
        )
        modelContext.insert(record)
        group.isSettled = true
        save()
        pushMetaIfShared(group, logging: .settledGroup)
        updateWidget()
    }

    /// 共享帳本的列表操作（結清/改名）推送到 Firestore，否則其他成員看不到、
    /// 且下次同步會把本機改動退回遠端舊值。
    private func pushMetaIfShared(_ group: Group, logging action: ActivityAction? = nil) {
        guard group.isShared else { return }
        Task {
            do {
                try await sharingManager.pushGroupScalars(for: group)
                if let action {
                    await sharingManager.logActivity(for: group, action: action, target: group.name)
                }
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    /// 共享帳本抓最新活動時間，晚於本裝置已讀時間就標紅點。
    private func refreshUnread() {
        for group in groups where group.isShared {
            guard let fid = group.firestoreGroupId else { continue }
            let gid = group.id
            Task {
                guard let latest = await sharingManager.latestActivityDate(groupId: fid) else { return }
                let seen = ActivitySeenStore.lastSeen(groupId: fid) ?? .distantPast
                if latest > seen {
                    unreadGroupIds.insert(gid)
                } else {
                    unreadGroupIds.remove(gid)
                }
            }
        }
    }

    private func confirmDeleteGroup() {
        guard let group = groupToDelete else { return }
        let record = HistoryRecord(
            groupName: group.name,
            memberCount: group.members.count,
            expenseCount: group.expenses.count,
            action: .deleted
        )
        modelContext.insert(record)
        modelContext.delete(group)
        groupToDelete = nil
        save()
        updateWidget()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func updateWidget() {
        WidgetDataWriter.update(
            activeGroupCount: activeGroups.count,
            totalExpenseCount: groups.reduce(0) { $0 + $1.expenses.filter { !$0.archived }.count }
        )
    }
}

// MARK: - Join Code Alerts (extracted to help Swift type-checker)

private struct JoinCodeAlerts: ViewModifier {
    @Binding var showingJoinCode: Bool
    @Binding var joinCode: String
    @Binding var joinError: String?
    @Binding var joinSuccess: Bool
    @Binding var isJoining: Bool
    var onJoin: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("輸入邀請碼", isPresented: $showingJoinCode) {
                TextField("邀請碼", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button("取消", role: .cancel) { joinCode = "" }
                Button("加入") { onJoin() }
            } message: {
                Text("請輸入對方分享的 6 碼邀請碼")
            }
            .alert("加入失敗", isPresented: Binding(
                get: { joinError != nil },
                set: { if !$0 { joinError = nil } }
            )) {
                Button("好") { joinError = nil }
            } message: {
                Text(joinError ?? "")
            }
            .alert("加入成功", isPresented: $joinSuccess) {
                Button("好") { }
            } message: {
                Text("帳目已加入，可在列表中查看")
            }
    }
}

// MARK: - Add Group Sheet

private struct AddGroupSheet: View {
    @Binding var name: String
    @Binding var baseCurrency: String
    var onCreate: () -> Void
    var onCancel: () -> Void

    @State private var showingCurrencyPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("帳目名稱") {
                    TextField("例如：沖繩", text: $name)
                }

                Section {
                    Button {
                        showingCurrencyPicker = true
                    } label: {
                        HStack {
                            Text(CurrencyService.flag(for: baseCurrency))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(baseCurrency)
                                    .foregroundStyle(.primary)
                                Text(CurrencyService.displayName(for: baseCurrency))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("結算幣別")
                } footer: {
                    Text("結算幣別是最後算錢用的幣別。可加入其他幣別的花費，會自動換算成這個幣別。建立後仍可修改。")
                        .font(.caption)
                }
            }
            .navigationTitle("新增帳目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建立") { onCreate() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(selection: $baseCurrency)
            }
        }
    }
}
