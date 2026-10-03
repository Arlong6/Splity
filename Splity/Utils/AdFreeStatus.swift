import Foundation
import StoreKit
import FirebaseCore
import FirebaseFirestore

/// 「這個人要不要看廣告」的唯一判定點。三個來源任一成立就免廣告：
///
/// 1. 測試環境（xctest / `IS_UI_TESTING`）：UI 測試與上架截圖不能出現廣告，也不能被插頁卡住。
/// 2. StoreKit：買過「移除廣告」（非消耗型）。這是唯一跨裝置、跨重裝都有效的憑證。
/// 3. Firestore `adFree/{uid}`：開發者在 Console 手動加的朋友名單。匿名 uid 刪 App 重裝就會變，
///    所以這只是「名單」不是「憑證」，要重加就重加。
///
/// 三個來源都先快取到 UserDefaults，App 一啟動就能用上次的結果決定要不要載廣告，
/// 不用等網路；之後 `refresh()` 再用最新結果覆蓋。
@Observable
final class AdFreeStatus {
    static let shared = AdFreeStatus()

    private static let purchasedKey = "AdFree_purchased"
    private static let remoteKey = "AdFree_remote"

    static let isTestEnvironment = Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
        || UserDefaults.standard.bool(forKey: "IS_UI_TESTING")

    private(set) var isPurchased: Bool
    private(set) var isRemoteAdFree: Bool
    private(set) var product: Product?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPurchased = defaults.bool(forKey: Self.purchasedKey)
        isRemoteAdFree = defaults.bool(forKey: Self.remoteKey)
    }

    var isAdFree: Bool {
        Self.resolve(isTest: Self.isTestEnvironment, purchased: isPurchased, remote: isRemoteAdFree)
    }

    /// 純邏輯，獨立出來給測試用。
    static func resolve(isTest: Bool, purchased: Bool, remote: Bool) -> Bool {
        isTest || purchased || remote
    }

    // MARK: - 更新

    /// 依序：StoreKit 現有權益 → Firestore 名單 → 商品資訊。任何一步失敗都不影響其他步。
    func refresh(uid: String?) async {
        await refreshEntitlements()
        await refreshRemote(uid: uid)
        await loadProductIfNeeded()
    }

    func refreshEntitlements() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == AdConfig.removeAdsProductID, transaction.revocationDate == nil {
                purchased = true
            }
        }
        setPurchased(purchased)
    }

    func refreshRemote(uid: String?) async {
        guard let uid, FirebaseApp.app() != nil else { return }
        do {
            let snapshot = try await Firestore.firestore().document("adFree/\(uid)").getDocument()
            isRemoteAdFree = snapshot.exists
            defaults.set(snapshot.exists, forKey: Self.remoteKey)
        } catch {
            // 沒網路或規則拒絕：維持上次快取，不動。
        }
    }

    func loadProductIfNeeded() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [AdConfig.removeAdsProductID]).first
    }

    /// 監聽 StoreKit 的交易更新（例如家人共享、退款、在別台裝置買）。App 啟動後叫一次即可。
    func listenForTransactions() {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    // MARK: - 購買

    enum PurchaseOutcome { case purchased, cancelled, pending }

    func purchase() async throws -> PurchaseOutcome {
        await loadProductIfNeeded()
        guard let product else { throw PurchaseError.productUnavailable }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            await transaction.finish()
            setPurchased(true)
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// 給畫面用的購買：回傳要顯示給使用者的訊息，使用者自己取消則回傳 nil（不打擾）。
    /// 橫幅入口與關於頁共用，兩邊的提示保證一致。
    func purchaseWithMessage() async -> String? {
        do {
            switch try await purchase() {
            case .purchased: return localized("已移除廣告，謝謝支持！")
            case .pending: return localized("購買待核准，完成後會自動生效。")
            case .cancelled: return nil
            }
        } catch {
            return localized("購買失敗") + "\n" + error.localizedDescription
        }
    }

    /// 回傳還原後是否已擁有「移除廣告」。
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refreshEntitlements()
        return isPurchased
    }

    enum PurchaseError: LocalizedError {
        case productUnavailable, unverified
        var errorDescription: String? {
            switch self {
            case .productUnavailable: return localized("目前無法取得商品資訊，請稍後再試。")
            case .unverified: return localized("無法驗證這筆購買。")
            }
        }
    }

    private func setPurchased(_ value: Bool) {
        isPurchased = value
        defaults.set(value, forKey: Self.purchasedKey)
    }
}
