import Foundation

/// 附在「問題回報」信裡的本機操作紀錄。
///
/// 只記「發生了什麼事」，**不記內容**：帳本／花費名稱、金額、成員名字、備註、邀請碼、uid
/// 一律不進來（唯一例外是自訂分帳的加總差額，用來判斷是不是進位問題）。
/// 紀錄只存在本機，使用者按「問題回報」時才附進信裡，由他自己看過、自己決定寄不寄。
///
/// 為什麼需要：使用者回報通常只有一句「不能新增花費」，回信追問多半石沉大海；
/// 有這段就能直接看出卡在哪一步（例如匯率抓不到、自訂分帳加總不符）。
final class DiagnosticLog {

    struct Entry: Codable, Equatable {
        let date: Date
        let message: String
    }

    static let shared = DiagnosticLog(fileURL: URL.applicationSupportDirectory
        .appending(path: "diagnostic-log.json"))

    let fileURL: URL
    let maxEntries: Int
    let maxAge: TimeInterval

    private var cache: [Entry]?

    init(fileURL: URL, maxEntries: Int = 200, maxAge: TimeInterval = 7 * 24 * 3600) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        self.maxAge = maxAge
    }

    /// 記一筆。`message` 由呼叫端組好，**不可以**帶入使用者輸入的文字或金額。
    func record(_ message: String, at date: Date = Date()) {
        var list = pruned(load(), now: date)
        list.append(Entry(date: date, message: message))
        if list.count > maxEntries {
            list.removeFirst(list.count - maxEntries)
        }
        cache = list
        save(list)
    }

    /// 目前保留中的紀錄（舊到新），已去掉過期的。
    func entries(now: Date = Date()) -> [Entry] {
        pruned(load(), now: now)
    }

    /// 信末的「最近操作紀錄」區塊；沒有紀錄時回空字串，信裡就不出現這段。
    func reportSection(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let list = entries(now: now)
        guard !list.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd HH:mm:ss"
        let lines = list.map { "\(formatter.string(from: $0.date)) \($0.message)" }
        return "最近操作紀錄：\n" + lines.joined(separator: "\n")
    }

    /// 錯誤的簡短描述：domain＋代碼＋系統訊息。Firestore 的 `permission-denied`（7）這類代碼
    /// 比在地化訊息好查。系統錯誤訊息不含使用者輸入的內容。
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code) \(ns.localizedDescription)"
    }

    private func pruned(_ list: [Entry], now: Date) -> [Entry] {
        list.filter { now.timeIntervalSince($0.date) <= maxAge }
    }

    private func load() -> [Entry] {
        if let cache { return cache }
        // 讀不到（第一次、檔案壞了）就當沒有紀錄；診斷功能不能反過來讓 App 出錯
        let list = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        cache = list
        return list
    }

    private func save(_ list: [Entry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
