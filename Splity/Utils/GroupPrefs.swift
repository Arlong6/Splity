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

    // MARK: - 身份認領

    private static func claimDeclinedKey(_ groupId: UUID) -> String {
        "claimDeclined.\(groupId.uuidString)"
    }

    /// 使用者是否已對這個帳本按過「稍後再說」。
    /// 不記住的話，每次進入帳本（連從花費編輯頁返回都算）都會再跳一次認領視窗。
    static func hasDeclinedClaim(for groupId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: claimDeclinedKey(groupId))
    }

    static func setDeclinedClaim(_ declined: Bool, for groupId: UUID) {
        if declined {
            UserDefaults.standard.set(true, forKey: claimDeclinedKey(groupId))
        } else {
            UserDefaults.standard.removeObject(forKey: claimDeclinedKey(groupId))
        }
    }

    /// 帳本被刪除時一併清掉它的偏好，避免 UserDefaults 無限累積。
    static func clearAll(for groupId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(groupId))
        UserDefaults.standard.removeObject(forKey: claimDeclinedKey(groupId))
    }

    static func setDefaultInputCurrency(_ code: String?, for groupId: UUID) {
        if let code {
            UserDefaults.standard.set(code, forKey: key(groupId))
        } else {
            UserDefaults.standard.removeObject(forKey: key(groupId))
        }
    }
}
