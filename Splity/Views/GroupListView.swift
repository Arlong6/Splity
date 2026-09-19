import SwiftUI
import SwiftData
import StoreKit

struct GroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
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
    @State private var path = NavigationPath()
    @State private var showingStoreRescueNotice = false
    @State private var joinSuccess = false
    @State private var saveError: String?
    @State private var updateChecker = AppUpdateChecker.shared
    @State private var groupToDelete: Group?
    @State private var groupToSettle: Group?
    @State private var unreadGroupIds: Set<UUID> = []

    private var activeGroups: [Group] { groups.filter { !$0.isSettled } }
    private var settledGroups: [Group] { groups.filter { $0.isSettled } }

    var body: some View {
        NavigationStack(path: $path) {
            groupList
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingHistory) {
                    HistoryView()
                }
                .navigationDestination(for: Group.self) { group in
                    GroupDetailView(group: group)
                }
                // 快速分帳走明確的 path：用 navigationDestination(isPresented:) 推入後，
                // 子頁的 NavigationLink(value:) 會被標成 selected 卻不 push（實測間歇失效）。
                .navigationDestination(for: QuickSplitRoute.self) { _ in
                    QuickSplitListView()
                }
                .navigationDestination(for: QuickSplit.self) { split in
                    QuickSplitResultView(split: split)
                }
                .onAppear {
                    refreshUnread()
                    // 上次啟動時資料庫打不開、已改名備份：一定要讓使用者知道
                    if StoreRescue.consumeRescueFlag() { showingStoreRescueNotice = true }
                    // 有共享帳本才要通知權限（背景活動通知用）；授權框只會跳一次
                    if groups.contains(where: { $0.isShared }) {
                        ActivityNotifier.requestPermissionIfNeeded()
                    }
                }
                .task { await updateChecker.checkIfNeeded() }
                .alert("無法開啟原本的資料", isPresented: $showingStoreRescueNotice) {
                    Button("好") { showingStoreRescueNotice = false }
                } message: {
                    Text("上次開啟時讀不到你的帳本資料，已保留一份備份並重新建立。如果帳目不見了，先不要刪除 app，聯絡我們還有機會救回。")
                }
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

            // 不建群組的快速分帳 + 加入邀請碼
            Section {
                Button {
                    path.append(QuickSplitRoute.list)
                } label: {
                    Label("快速分帳（不用建群組）", systemImage: "divide.circle")
                        .foregroundStyle(.orange)
                }

                Button {
                    showingJoinCode = true
                } label: {
                    Label("輸入邀請碼加入帳目", systemImage: "ticket")
                        .foregroundStyle(.blue)
                }
                .disabled(isJoining)
            }

            // 空狀態排在列表裡（不用 overlay，否則會蓋住上面的入口卡片）
            if groups.isEmpty {
                Section {
                    ContentUnavailableView(
                        "還沒有帳本",
                        systemImage: "person.3",
                        description: Text("點右上角 + 建立一個新的帳本")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
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
                                Task { await pushMetaIfShared(group, logging: .unsettledGroup) }
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button { path.append(QuickSplitRoute.list) } label: {
                Label("快速分帳", systemImage: "divide.circle")
            }
            Button { showingAddGroup = true } label: {
                Label("新增帳目", systemImage: "plus.circle.fill")
            }
        }
        ToolbarItemGroup(placement: .navigation) {
            Button { showingHistory = true } label: {
                Label("歷史紀錄", systemImage: "clock.arrow.circlepath")
            }
            Menu {
                Button(action: { selectLanguage("zh-Hant") }) {
                    if appLanguage == "zh-Hant" {
                        Label("繁體中文", systemImage: "checkmark")
                    } else {
                        Text("繁體中文")
                    }
                }
                Button(action: { selectLanguage("en") }) {
                    if appLanguage == "en" {
                        Label("English", systemImage: "checkmark")
                    } else {
                        Text("English")
                    }
                }
            } label: {
                Image(systemName: "globe")
                    .accessibilityLabel(localized("語言"))
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
            joinError = localized("邀請碼格式不正確，請輸入 6 碼英數字")
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

    // label 必須是 LocalizedStringKey：宣告成 String 的話 Text(label) 會被當成已在地化的
    // 字面內容直接顯示，英文版就會漏出中文（統計列先前就是這樣）。
    private func statBadge(icon: String, value: String, label: LocalizedStringKey) -> some View {
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
    }

    private func confirmRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let group = groupToRename else { return }
        group.name = trimmed
        groupToRename = nil
        save()
        Task { await pushMetaIfShared(group) }
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
        // 本機存檔失敗就不算結清成功：不計次、也不問評分
        guard save() else { return }
        Task {
            // 共享帳本要等 Firestore 真的收下才算成功。推送被拒（匿名登入失敗、
            // rules 擋下、帳本已被擁有者刪除…）會跳「儲存失敗」，那時絕不能問評分。
            guard await pushMetaIfShared(group, logging: .settledGroup) else { return }
            await askForReviewIfEarned(for: group)
        }
    }

    /// 結算完成是使用者體驗到價值的時刻，也是唯一適合開口要評分的地方。
    /// 計數掛在這條「真的結清成功」的路徑上，不是畫面出現時；跳出前先等幾秒，
    /// 讓帳本移到「已結清」區、使用者看到結果，不要一按完按鈕就攔路。
    ///
    /// 等待期間如果冒出任何錯誤 alert（其他非同步操作也會寫 `saveError`）就放棄：
    /// 在失敗畫面上疊評分面板是製造一星的標準方式，而且系統若因為已有 alert 而不顯示，
    /// 這一版唯一的機會還是會被燒掉。所以「消費機會」放在真正呼叫的前一刻。
    private func askForReviewIfEarned(for group: Group) async {
        ReviewPrompt.recordSettlement(groupId: group.id)
        try? await Task.sleep(for: ReviewPrompt.delay)
        guard saveError == nil else { return }
        guard ReviewPrompt.consumeRequestOpportunity() else { return }
        requestReview()
    }

    /// 共享帳本的列表操作（結清/改名）推送到 Firestore，否則其他成員看不到、
    /// 且下次同步會把本機改動退回遠端舊值。
    /// 回傳「這次操作有沒有真的成功」；非共享帳本沒有遠端這一段，直接算成功。
    @discardableResult
    private func pushMetaIfShared(_ group: Group, logging action: ActivityAction? = nil) async -> Bool {
        guard group.isShared else { return true }
        do {
            try await sharingManager.pushGroupScalars(for: group)
            if let action {
                await sharingManager.logActivity(for: group, action: action, target: group.name)
            }
            return true
        } catch {
            saveError = error.localizedDescription
            return false
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

    /// 切換語言：app 自己的字串立即生效，系統介面（導覽列返回鈕等）下次啟動生效。
    private func selectLanguage(_ identifier: String) {
        AppLanguage.select(identifier)
        appLanguage = identifier
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
        // 帳本刪掉後它的每裝置偏好就沒有意義了，一併清掉避免 UserDefaults 無限累積
        GroupPrefs.clearAll(for: group.id)
        modelContext.delete(group)
        groupToDelete = nil
        save()
    }

    /// 回傳存檔有沒有成功。結清流程要用它決定「這次算不算一筆成功結算」，
    /// 其他呼叫端照舊忽略回傳值。
    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
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

/// 快速分帳的導覽路徑值
enum QuickSplitRoute: Hashable {
    case list
}
