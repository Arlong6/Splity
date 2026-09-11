import Foundation

/// SwiftData store 的救援邏輯。
///
/// 背景：`ModelConfiguration` 的 `groupContainer` 預設為 `.automatic`，而本 app 有
/// app group entitlement，所以 store 實際落在 **App Group 容器**裡
/// （`<AppGroup>/Library/Application Support/default.store`），不是
/// `URL.applicationSupportDirectory`。舊版救援程式硬寫後者，備份改名永遠找不到檔案，
/// 重試必定同樣失敗 → 靜默退回記憶體容器，該次啟動的所有操作在關閉 app 時全部消失。
///
/// 這裡不改變容器建立方式（改 URL 會讓既有使用者的帳本「消失」），只負責在真的需要
/// 救援時找對檔案、整組搬移、並留下讓使用者知情的旗標。
enum StoreRescue {
    static let appGroupIdentifier = "group.com.arlongchien.Splity"
    private static let recordedURLKey = "storeRescue.lastKnownStoreURL"
    static let didRescueKey = "storeRescue.didRescue"

    /// store 檔案的三個組成：主檔與 write-ahead log。必須整組一起搬，
    /// 只搬一部分會留下 store 與 WAL 不匹配的殘局，比原本更難救。
    static let suffixes = ["", "-wal", "-shm"]

    /// 成功建立容器後記下實際路徑，之後的救援就不必用猜的。
    static func recordStoreURL(_ url: URL?, defaults: UserDefaults = .standard) {
        guard let url else { return }
        defaults.set(url.path, forKey: recordedURLKey)
    }

    /// 依序回傳可能的 store 位置：已記錄的實際路徑優先，其次 app group 容器，
    /// 最後才是 Application Support（沒有 app group entitlement 時的位置）。
    static func candidateURLs(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [URL] {
        var candidates: [URL] = []
        if let recorded = defaults.string(forKey: recordedURLKey) {
            candidates.append(URL(fileURLWithPath: recorded))
        }
        if let groupRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            candidates.append(
                groupRoot
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("default.store")
            )
        }
        candidates.append(URL.applicationSupportDirectory.appendingPathComponent("default.store"))

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    /// 第一個確實存在的 store 檔位置。
    static func existingStoreURL(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> URL? {
        candidateURLs(defaults: defaults, fileManager: fileManager)
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// 把 store 整組改名備份。任何一個檔案搬移失敗就把已搬的搬回去，
    /// 維持「全部搬走或全部留著」，不留下半套狀態。
    /// - Returns: 成功搬移時回傳備份檔名的共同前綴；沒有檔案可搬或失敗時回傳 nil。
    @discardableResult
    static func backupStore(
        at storeURL: URL,
        stamp: Int = Int(Date().timeIntervalSince1970),
        fileManager: FileManager = .default
    ) -> String? {
        let moves: [(from: URL, to: URL)] = suffixes.compactMap { suffix in
            let from = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { return nil }
            return (from, URL(fileURLWithPath: storeURL.path + suffix + ".corrupt-\(stamp).bak"))
        }
        guard !moves.isEmpty else { return nil }

        var done: [(from: URL, to: URL)] = []
        for move in moves {
            do {
                try fileManager.moveItem(at: move.from, to: move.to)
                done.append(move)
            } catch {
                for undo in done.reversed() {
                    try? fileManager.moveItem(at: undo.to, to: undo.from)
                }
                return nil
            }
        }
        return storeURL.path + ".corrupt-\(stamp).bak"
    }

    /// 記下「這次啟動動用過救援」，由畫面顯示一次提示後清除。
    static func markRescued(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: didRescueKey)
    }

    /// 取出並清除救援旗標。
    static func consumeRescueFlag(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: didRescueKey) else { return false }
        defaults.removeObject(forKey: didRescueKey)
        return true
    }
}
