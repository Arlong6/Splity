import Foundation

/// 幣別選單最上方的「最近使用」（存 UserDefaults、不同步、所有帳本共用）。
///
/// 為什麼需要：人在國外時結算幣別常是台幣，每筆花費都要在 30 多個幣別裡重找當地幣。
/// 不自動把新花費預設成上次的幣別——回國後第一筆容易沒注意就記錯；
/// 要固定預設可以用帳本選單裡的「記帳預設幣種」（`GroupPrefs`）。
enum RecentCurrencies {
    static let maxCount = 3
    private static let key = "recentCurrencies"

    /// 最近選過的幣別，新的在前；只回傳目前支援的幣別。
    static func list(defaults: UserDefaults = .standard) -> [String] {
        (defaults.stringArray(forKey: key) ?? [])
            .filter { CurrencyService.allSupported.contains($0) }
    }

    /// 選了某個幣別：移到最前面，超過上限就丟掉最舊的。
    static func record(_ code: String, defaults: UserDefaults = .standard) {
        var codes = list(defaults: defaults).filter { $0 != code }
        codes.insert(code, at: 0)
        defaults.set(Array(codes.prefix(maxCount)), forKey: key)
    }
}
