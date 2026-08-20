import Foundation

/// 每裝置的帳本偏好（存 UserDefaults、不同步）：
/// 記帳輸入的預設幣種——例如台幣帳本去香港旅行，新增花費想預設港幣。
/// 只影響本裝置的輸入預設，不改帳本的結算基準幣，也不影響其他成員。
enum GroupPrefs {
    private static func key(_ groupId: UUID) -> String {
        "defaultInputCurrency.\(groupId.uuidString)"
    }

    /// nil = 跟隨帳本的結算基準幣
    static func defaultInputCurrency(for groupId: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(groupId))
    }

    static func setDefaultInputCurrency(_ code: String?, for groupId: UUID) {
        if let code {
            UserDefaults.standard.set(code, forKey: key(groupId))
        } else {
            UserDefaults.standard.removeObject(forKey: key(groupId))
        }
    }
}
