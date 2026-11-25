import Foundation

/// 花費分類在 Firestore 上的寫法。
///
/// 寫入時**一定要寫這個欄位**，沒分類就寫 `NSNull()`：子集合用 `merge: true` 寫入，
/// 如果沒值就不寫，使用者把分類改回「未分類」時雲端的舊分類清不掉，各台手機會不一致。
/// 讀取時 `null`、缺欄位（舊版建立、從沒被新版寫過的花費）都當作沒分類。
/// 不認得的代碼原樣保留，交給 `Expense.displayCategory` 當「其他」顯示。
nonisolated enum ExpenseCategoryCoding {
    static let key = "category"

    static func encode(_ code: String?) -> Any {
        if let code { return code }
        return NSNull()
    }

    static func decode(_ raw: Any?) -> String? {
        guard let code = raw as? String, !code.isEmpty else { return nil }
        return code
    }
}
