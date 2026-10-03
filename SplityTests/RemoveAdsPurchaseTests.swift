import Testing
import Foundation
import StoreKit
import StoreKitTest
@testable import Splity

/// 用 StoreKitTest 在本機跑完整的買斷流程：購買 → 生效 → 還原 → 退款 → 家長核准（Ask to Buy）。
/// 讀的是 repo 根目錄的 `Splity.storekit`，不需要加進 target 資源。
/// SKTestSession 是全域狀態，所以整組必須循序執行。
@Suite("移除廣告買斷流程", .serialized)
@MainActor
struct RemoveAdsPurchaseTests {
    private let session: SKTestSession

    init() throws {
        let config = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Splity.storekit")
        session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.askToBuyEnabled = false
        // 不要碰 failTransactionsEnabled：實測只要設過（連設成 false 也算），之後的購買都回 .unknown。
        session.clearTransactions()
    }

    private func freshStatus() -> (AdFreeStatus, UserDefaults, String) {
        let name = "RemoveAdsPurchaseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (AdFreeStatus(defaults: defaults), defaults, name)
    }

    @Test("商品 ID 對得上、抓得到商品")
    func productLoads() async {
        let (status, _, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        await status.loadProductIfNeeded()
        #expect(status.product?.id == AdConfig.removeAdsProductID)
        #expect(status.product?.type == .nonConsumable)
    }

    @Test("購買成功 → 立即免廣告並寫入快取")
    func purchaseGrantsAdFree() async throws {
        let (status, defaults, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(status.isPurchased == false)
        let outcome = try await status.purchase()
        #expect(outcome == .purchased)
        #expect(status.isPurchased == true)
        #expect(defaults.bool(forKey: "AdFree_purchased") == true)
    }

    @Test("畫面用的購買：成功回感謝訊息並生效")
    func purchaseWithMessage() async {
        let (status, _, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(await status.purchaseWithMessage() == localized("已移除廣告，謝謝支持！"))
        #expect(status.isPurchased == true)
    }

    @Test("重裝（快取清空）後：啟動時的權益查詢與還原購買都能找回")
    func entitlementSurvivesReinstall() async throws {
        let (buyer, _, n1) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: n1) }
        _ = try await buyer.purchase()

        let (relaunched, _, n2) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: n2) }
        #expect(relaunched.isPurchased == false)
        await relaunched.refreshEntitlements()
        #expect(relaunched.isPurchased == true)

        let (restorer, _, n3) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: n3) }
        #expect(await restorer.restore() == true)
    }

    @Test("沒買過：還原回報找不到")
    func restoreWithoutPurchase() async {
        let (status, _, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        #expect(await status.restore() == false)
        #expect(status.isPurchased == false)
    }

    @Test("退款後權益消失")
    func refundRevokes() async throws {
        let (status, defaults, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        status.listenForTransactions()
        _ = try await status.purchase()
        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        // 退款在 StoreKit 內是非同步生效；正式環境由 Transaction.updates 觸發 refreshEntitlements。
        for _ in 0..<50 {
            await status.refreshEntitlements()
            if !status.isPurchased { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(status.isPurchased == false)
        #expect(defaults.bool(forKey: "AdFree_purchased") == false)
    }

    @Test("Ask to Buy：先回 pending，家長核准後由交易監聽自動生效")
    func askToBuyApprovedLater() async throws {
        session.askToBuyEnabled = true
        let (status, _, name) = freshStatus()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        status.listenForTransactions()

        #expect(try await status.purchase() == .pending)
        #expect(status.isPurchased == false)

        let pending = try #require(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: UInt(pending.identifier))

        for _ in 0..<50 where !status.isPurchased {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(status.isPurchased == true)
    }
}
