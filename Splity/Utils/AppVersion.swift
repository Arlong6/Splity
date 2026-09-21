import Foundation

/// App 版號，集中在一處讀取。
///
/// 在這之前 `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"`
/// 這串字面值分別寫在 `ReviewPrompt` 與 `AppUpdateChecker` 裡；帳目列表底部要顯示版本時
/// 會出現第三份。集中之後只有這個檔案知道 Info.plist 的 key 叫什麼。
///
/// 參數收的是 info dictionary 而不是 `Bundle`：`Bundle.infoDictionary` 是唯讀的，
/// 造不出帶自訂值的假 Bundle，收字典才測得到缺欄位與型別不符的情況。
enum AppVersion {

    /// 對使用者顯示的版號，例如 `1.8.2`。
    ///
    /// 讀不到時回 `"0"`——沿用 `ReviewPrompt` 與 `AppUpdateChecker` 原本的 fallback，
    /// 因為 `AppUpdateChecker.compareVersions` 會拿它跟商店版號比大小，回空字串會讓比較失準。
    static func short(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        info?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Build 號，例如 `18`。讀不到時回 `nil`，由呼叫端決定要不要顯示。
    static func build(info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return nil }
        return build
    }

    /// 顯示給使用者看的字串，例如 `Splity 1.8.2 (18)`。
    ///
    /// 帶上 build 號是為了支援：同一個版號可能對應多個 build（被退件後重新上傳就會），
    /// 只有版號的話分不出使用者手上到底是哪一包。沒有 build 號時省略括號，不要留空括號。
    static func display(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = short(info: info)
        guard let build = build(info: info) else { return "Splity \(version)" }
        return "Splity \(version) (\(build))"
    }
}
