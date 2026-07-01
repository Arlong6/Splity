import Foundation
import UIKit

/// Checks the App Store for newer versions and prompts the user to update.
@Observable
final class AppUpdateChecker {

    static let shared = AppUpdateChecker()

    var updateAvailable = false
    private(set) var storeVersion: String?
    private(set) var storeURL: URL?

    private let bundleID = "com.arlongchien.Splity"
    private let checkInterval: TimeInterval = 24 * 60 * 60 // 每天檢查一次
    private let lastCheckKey = "AppUpdateChecker_lastCheck"
    private let skippedVersionKey = "AppUpdateChecker_skippedVersion"

    private init() {}

    /// Check App Store for a newer version. Skips if already checked today.
    func checkIfNeeded() async {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - lastCheck > checkInterval else { return }

        await check()
        UserDefaults.standard.set(now, forKey: lastCheckKey)
    }

    /// Force check regardless of interval.
    func check() async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=tw") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(iTunesLookupResponse.self, from: data)

            guard let result = response.results.first else { return }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let storeVer = result.version

            self.storeVersion = storeVer
            if let storeURL = URL(string: result.trackViewUrl) {
                self.storeURL = storeURL
            }

            if Self.compareVersions(current: currentVersion, store: storeVer) == .orderedAscending {
                // 使用者若已對「這個版本」按過稍後再說，就不再提示（除非有更新的版本上架）
                let skipped = UserDefaults.standard.string(forKey: skippedVersionKey)
                if storeVer != skipped {
                    self.updateAvailable = true
                }
            }
        } catch {
            // Silently fail — non-critical feature
        }
    }

    /// Open the App Store page for this app.
    func openAppStore() {
        guard let url = storeURL else { return }
        UIApplication.shared.open(url)
    }

    /// 使用者選擇「稍後再說」：記住此版本，之後除非有更新版本上架，否則不再打擾。
    func skipCurrentVersion() {
        if let storeVersion {
            UserDefaults.standard.set(storeVersion, forKey: skippedVersionKey)
        }
        updateAvailable = false
    }

    // MARK: - Version Comparison

    static func compareVersions(current: String, store: String) -> ComparisonResult {
        // 容錯解析：App Store 版本字串可能帶有非數字前綴（例如 "V1.6.0"）。
        // 逐段只保留數字並以 0 補位，避免直接 compactMap 丟棄整段造成位置錯位、誤判有新版。
        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let c = components(current)
        let s = components(store)
        let count = max(c.count, s.count)

        for i in 0..<count {
            let cv = i < c.count ? c[i] : 0
            let sv = i < s.count ? s[i] : 0
            if cv < sv { return .orderedAscending }
            if cv > sv { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - iTunes API Response

private struct iTunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [AppStoreResult]
}

private struct AppStoreResult: Decodable {
    let version: String
    let trackViewUrl: String
}
