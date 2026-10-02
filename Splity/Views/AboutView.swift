import SwiftUI
import StoreKit

/// 「關於」：版本、回報問題、隱私權政策、網頁版、評分。
///
/// 這個畫面存在的理由是回報管道。在這之前 app 裡完全沒有回報入口——supportUrl 只出現在
/// App Store 商店頁，而且指向 GitHub issues，一般使用者要先有 GitHub 帳號才留得了言。
/// 入口做在帳目列表底部那行版本上：會低頭找版本號的人，正好就是要回報問題的人。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let diagnostics = SupportMail.Diagnostics.current()

    /// 寄信失敗時顯示——模擬器或沒有設定郵件帳號的裝置開不了 mailto。
    @State private var mailFailed = false

    @Environment(FirebaseSharingManager.self) private var sharingManager
    @State private var purchasing = false
    @State private var purchaseMessage: String?
    @State private var copiedID = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(localized("版本")) {
                        Text(verbatim: SupportMail.versionLine(diagnostics))
                            .accessibilityIdentifier("aboutVersionValue")
                    }
                }

                removeAdsSection

                Section {
                    Button {
                        guard let url = SupportMail.url(body: "", diagnostics: diagnostics) else {
                            mailFailed = true
                            return
                        }
                        openURL(url) { accepted in
                            if !accepted { mailFailed = true }
                        }
                    } label: {
                        row("回報問題", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("aboutReportProblem")
                } footer: {
                    Text("信件會自動帶上版本與裝置資訊，你只要描述問題就好。")
                }

                Section {
                    link("網頁版", systemImage: "safari", urlString: SplityLinks.webHome)
                    link("給 Splity 評分", systemImage: "star", urlString: SplityLinks.appStore)
                    link("隱私權政策", systemImage: "hand.raised", urlString: SplityLinks.privacyPolicy)
                }
            }
            .navigationTitle("關於 Splity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("開不了郵件 App", isPresented: $mailFailed) {
                Button("好") {}
            } message: {
                Text("請改寄到 \(SupportMail.address)")
            }
            .alert("移除廣告", isPresented: Binding(
                get: { purchaseMessage != nil },
                set: { if !$0 { purchaseMessage = nil } }
            )) {
                Button("好") { purchaseMessage = nil }
            } message: {
                Text(purchaseMessage ?? "")
            }
        }
    }

    // MARK: - 移除廣告

    /// 買斷去廣告 + 還原購買。footer 順便露出匿名 uid：開發者要把朋友加進 Firestore 的免廣告名單，
    /// 需要對方把這串 ID 傳過來；一般使用者看到也無妨，它不含任何個人資訊。
    private var removeAdsSection: some View {
        let adFree = AdFreeStatus.shared
        return Section {
            if adFree.isPurchased {
                Label("已移除廣告", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if adFree.isRemoteAdFree {
                // 名單上的朋友本來就沒有廣告，別讓他們看到購買按鈕而誤買。
                // 名單綁匿名 uid、重裝會失效，所以「還原購買」照樣留著。
                Label("你在免廣告名單中", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await purchaseRemoveAds() }
                } label: {
                    HStack {
                        row("移除廣告", systemImage: "rectangle.slash")
                        Spacer()
                        if purchasing {
                            ProgressView()
                        } else if let price = adFree.product?.displayPrice {
                            Text(price).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(purchasing || adFree.product == nil)
                .accessibilityIdentifier("aboutRemoveAds")
            }
            Button {
                Task { await restorePurchases() }
            } label: {
                row("還原購買", systemImage: "arrow.clockwise")
            }
            .disabled(purchasing)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("一次購買，永久移除橫幅與插頁廣告。")
                if let uid = sharingManager.currentUserId {
                    Button {
                        UIPasteboard.general.string = uid
                        copiedID = true
                    } label: {
                        (copiedID ? Text("已複製") : Text("你的 ID（點一下複製）")) + Text(verbatim: " \(uid)")
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task { await adFree.loadProductIfNeeded() }
    }

    private func purchaseRemoveAds() async {
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await AdFreeStatus.shared.purchase() {
            case .purchased: purchaseMessage = String(localized: "已移除廣告")
            case .pending: purchaseMessage = String(localized: "購買待核准，完成後會自動生效。")
            case .cancelled: break
            }
        } catch {
            purchaseMessage = String(localized: "購買失敗") + "\n" + error.localizedDescription
        }
    }

    private func restorePurchases() async {
        purchasing = true
        defer { purchasing = false }
        let restored = await AdFreeStatus.shared.restore()
        purchaseMessage = String(localized: restored ? "已還原購買" : "沒有找到可還原的購買")
    }

    private func row(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    /// 外部連結一律交給系統開，不內嵌瀏覽器——隱私權政策與商店頁都該在使用者信任的地方開。
    ///
    /// 用 `@ViewBuilder` 而不是包一層 `Group`：這個專案有自己的 `Group` model
    /// （SwiftData 的帳本），會把 SwiftUI 的 `Group` 遮蔽掉，寫 `Group { }` 會編不過。
    @ViewBuilder
    private func link(_ title: LocalizedStringKey, systemImage: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    AboutView()
        .environment(FirebaseSharingManager.shared)
}
