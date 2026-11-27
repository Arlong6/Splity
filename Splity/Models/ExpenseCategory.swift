import Foundation

/// 花費分類。`rawValue` 是存進 SwiftData 與 Firestore 的代碼，**不可改名**；
/// 新增分類只能加在後面，舊版讀到不認得的代碼會當成「其他」顯示（見 `Expense.displayCategory`）。
/// 宣告順序就是選單與統計圖例的順序。
/// 不標 nonisolated：`displayName` 用到的 `localized(...)` 在主執行緒上。
enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food, transport, lodging, fun, shopping, daily, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return localized("餐飲")
        case .transport: return localized("交通")
        case .lodging: return localized("住宿")
        case .fun: return localized("門票娛樂")
        case .shopping: return localized("購物")
        case .daily: return localized("日用品")
        case .other: return localized("其他")
        }
    }

    var symbolName: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .lodging: return "bed.double.fill"
        case .fun: return "ticket.fill"
        case .shopping: return "bag.fill"
        case .daily: return "basket.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// 沒有分類時顯示的名稱。跟「其他」不同：「其他」是明確選的。
    static var uncategorizedName: String { localized("未分類") }

    /// 使用者明確選了「未分類」時存的代碼，**不可改**。
    /// 跟 `nil`（從沒設過，顯示時依名稱猜）要分開，不然改回未分類的花費會再被猜回原本的類別。
    nonisolated static let uncategorizedCode = "none"
}

extension Expense {
    /// 畫面與統計用的分類：有存就用存的（明確未分類是 nil，不認得的代碼當「其他」），
    /// 沒存就依品項名稱猜。只用來顯示，**不寫回** `category`。
    var displayCategory: ExpenseCategory? {
        if let code = category {
            if code == ExpenseCategory.uncategorizedCode { return nil }
            return ExpenseCategory(rawValue: code) ?? .other
        }
        return CategoryGuesser.guess(title: title)
    }
}
