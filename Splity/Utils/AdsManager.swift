import SwiftUI
import UIKit
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

/// Google Mobile Ads 的啟動與插頁廣告管理。
///
/// 啟動順序固定是 **ATT → UMP 同意表單 → SDK 初始化**：Apple 5.1.2 要求在任何追蹤發生前先問 ATT，
/// 先初始化 SDK 再問是常見退件原因。UMP 對台灣、日本等非受規範地區會自動不顯示表單，
/// 所以不用自己判斷地區，照官方流程走即可。
///
/// 免廣告的人（`AdFreeStatus`）連 SDK 都不初始化：不問 ATT、不載任何廣告。
@Observable
final class AdsManager: NSObject {
    static let shared = AdsManager()

    /// SDK 已初始化、可以載廣告。橫幅看這個旗標決定要不要出現。
    private(set) var isStarted = false

    private var startTask: Task<Void, Never>?
    private var interstitial: InterstitialAd?
    private var onInterstitialDismissed: (() -> Void)?

    private override init() {}

    /// 進入主畫面後呼叫一次；重複呼叫無效。
    func start(uid: String?) {
        guard startTask == nil else { return }
        startTask = Task { await run(uid: uid) }
    }

    private func run(uid: String?) async {
        let adFree = AdFreeStatus.shared
        adFree.listenForTransactions()
        await adFree.refresh(uid: uid)
        guard !adFree.isAdFree else { return }

        InterstitialPolicy.recordFirstLaunchIfNeeded()

        // 列表頁一出現還有通知權限、更新提示可能要跳，錯開一秒別疊在一起。
        try? await Task.sleep(for: .seconds(1))
        _ = await ATTrackingManager.requestTrackingAuthorization()

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: nil)
            if let viewController = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: viewController)
            }
        } catch {
            // 沒網路或表單載入失敗：交給 canRequestAds 決定，不中斷。
        }
        guard ConsentInformation.shared.canRequestAds else { return }

        MobileAds.shared.requestConfiguration.maxAdContentRating = .parentalGuidance
        await withCheckedContinuation { continuation in
            MobileAds.shared.start { _ in continuation.resume() }
        }
        isStarted = true
        await loadInterstitial()
    }

    // MARK: - 插頁

    private func loadInterstitial() async {
        guard isStarted, interstitial == nil, !AdFreeStatus.shared.isAdFree else { return }
        do {
            let ad = try await InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            interstitial = ad
        } catch {
            interstitial = nil
        }
    }

    /// 允許且已載好就播，播完（或關掉）才執行 `completion`；任何條件不符都直接執行 `completion`。
    /// 呼叫端把「關閉畫面」放進 completion，使用者體感就是「按完成 → 看廣告 → 畫面關閉」。
    func showInterstitialIfAllowed(then completion: @escaping () -> Void) {
        guard !AdFreeStatus.shared.isAdFree,
              let ad = interstitial,
              let viewController = Self.topViewController(),
              InterstitialPolicy.consumeShowOpportunity()
        else {
            completion()
            return
        }
        interstitial = nil
        onInterstitialDismissed = completion
        ad.present(from: viewController)
    }

    private func finishInterstitial() {
        let completion = onInterstitialDismissed
        onInterstitialDismissed = nil
        completion?()
        Task { await loadInterstitial() }
    }

    // MARK: - 取得最上層的 view controller（sheet 裡也要能 present）

    static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension AdsManager: FullScreenContentDelegate {
    // SDK 的 delegate 是 ObjC 協定、不保證隔離；一律跳回 main actor 再動狀態。
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in finishInterstitial() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in finishInterstitial() }
    }
}

// MARK: - 橫幅

/// 放在列表底部的自適應橫幅。免廣告或 SDK 還沒啟動時不佔任何空間。
///
/// 尺寸刻意用舊的 `currentOrientationAnchoredAdaptiveBanner`（約 60pt），不用 SDK 13 主推的
/// `largeAnchoredAdaptiveBanner`：後者在 iPhone 上算出來是 126pt，佔掉 15% 螢幕，
/// 對一個分帳列表來說太吵。它目前只是 deprecated 還能用；哪天被移除再改成 inline adaptive + maxHeight。
///
/// 橫幅上方附一條「移除廣告」：原本入口只在列表最底的「關於」，連 App Review 都找不到。
struct AdBanner: View {
    var onRemoveAds: () -> Void

    private static func bannerSize(width: CGFloat) -> AdSize {
        currentOrientationAnchoredAdaptiveBanner(width: width)
    }

    var body: some View {
        if !AdFreeStatus.shared.isAdFree, AdsManager.shared.isStarted {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onRemoveAds) {
                        HStack(spacing: 2) {
                            Text("移除廣告")
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .font(.caption)
                    }
                    .accessibilityIdentifier("bannerRemoveAds")
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                GeometryReader { geometry in
                    let size = Self.bannerSize(width: geometry.size.width)
                    BannerViewContainer(adSize: size)
                        .frame(width: size.size.width, height: size.size.height)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: Self.bannerSize(width: UIScreen.main.bounds.width).size.height)
                .accessibilityLabel(Text("廣告"))
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = AdsManager.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
