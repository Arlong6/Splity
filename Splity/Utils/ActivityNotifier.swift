import BackgroundTasks
import SwiftData
import UserNotifications

/// 背景刷新 + 本地通知：iOS 週期性喚醒（時機由系統決定，非即時）→ 查各共享帳本
/// 有無新活動 → 發本地通知。免伺服器的延遲通知方案；秒級即時要 FCM（未做）。
enum ActivityNotifier {
    static let taskId = "com.arlongchien.Splity.activityCheck"

    /// 必須在 app 完成啟動前註冊（SplityApp.init 呼叫）。
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            // 先排下一次，確保鏈不中斷（本次成敗都要有下一次）
            scheduleNext()
            let work = Task {
                await checkAndNotify(container: container)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// App 退到背景時呼叫；重複 submit 同 id 會自動取代，不會累積。
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 有共享帳本才要通知權限；系統只會真正跳一次授權框，之後呼叫是 no-op。
    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 核心檢查：對每個共享帳本比對「最新活動 vs 已讀/已通知時間」，
    /// 只對別人的、還沒看過也沒通知過的活動發通知。
    static func checkAndNotify(container: ModelContainer) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        let manager = FirebaseSharingManager.shared
        let groups: [(name: String, fid: String)] = await MainActor.run {
            let ctx = ModelContext(container)
            let all = (try? ctx.fetch(FetchDescriptor<Group>())) ?? []
            return all.compactMap { g in g.firestoreGroupId.map { (g.name, $0) } }
        }
        guard !groups.isEmpty else { return }

        try? await manager.signInAnonymously()
        let myUid = manager.currentUserId

        for group in groups {
            let entries = await manager.recentActivities(groupId: group.fid, limit: 10)
            let cutoff = max(
                ActivitySeenStore.lastSeen(groupId: group.fid) ?? .distantPast,
                ActivitySeenStore.lastNotified(groupId: group.fid) ?? .distantPast
            )
            let fresh = entries.filter { $0.timestamp > cutoff && $0.actorId != myUid }
            guard !fresh.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = group.name
            if fresh.count == 1, let entry = fresh.first {
                content.body = "\(entry.actorName) \(entry.action.displayText)「\(entry.target)」"
            } else {
                content.body = "有 \(fresh.count) 筆新動態"
            }
            content.sound = .default
            // 同帳本固定 id：新通知取代舊的，不洗版
            let request = UNNotificationRequest(
                identifier: "activity-\(group.fid)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)

            if let newest = fresh.map(\.timestamp).max() {
                ActivitySeenStore.markNotified(groupId: group.fid, upTo: newest)
            }
        }
    }
}
