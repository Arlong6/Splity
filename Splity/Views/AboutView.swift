import SwiftUI

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(localized("版本")) {
                        Text(verbatim: SupportMail.versionLine(diagnostics))
                            .accessibilityIdentifier("aboutVersionValue")
                    }
                }

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
        }
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
}
