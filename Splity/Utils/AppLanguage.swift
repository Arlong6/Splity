import Foundation

/// App 內建的語言切換（帳目列表 ⋯ 選單）把選擇存在 UserDefaults 的 `appLanguage`，
/// 並透過 `.environment(\.locale, …)` 套用到 SwiftUI。
///
/// 但這個環境值只影響 SwiftUI 的 `Text`；任何在 View 之外做的在地化
/// （`Locale.current`、`localizedString(forCurrencyCode:)` 等）都看不到它，
/// 使用者切成英文後仍會在那些地方看到中文。這裡提供唯一的語言來源。
enum AppLanguage {
    static let defaultIdentifier = "zh-Hant"

    static var identifier: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? defaultIdentifier
    }

    static var locale: Locale {
        Locale(identifier: identifier)
    }

    /// 切換語言。除了 app 自己的設定，也一併寫入系統的 `AppleLanguages`——
    /// 導覽列的「返回」、鍵盤、分享面板等系統介面只看它，不看 app 的設定；
    /// 這部分要下次啟動才會生效，app 自己的字串則立即切換。
    static func select(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: "appLanguage")
        UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
    }
}

extension Bundle {
    /// 對應使用者在 app 內選的語言的資源 bundle。
    /// 找不到就退回主 bundle（等同系統語系）。
    static var appLanguage: Bundle {
        guard let path = Bundle.main.path(forResource: AppLanguage.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

/// 在 SwiftUI View 之外做在地化時一律用這個，不要用 `String(localized:)`。
///
/// `String(localized:)` 查的是主 bundle 的語系，看不到 app 內建的語言切換
/// （實測：把 app 切成英文後，所有 `String(localized:)` 的字串仍是中文，
/// 因為切換只設了 SwiftUI 的 environment locale）。
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .appLanguage)
}
