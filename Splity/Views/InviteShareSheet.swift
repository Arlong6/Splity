import SwiftUI

struct InviteShareSheet: View {
    let groupName: String
    let inviteCode: String
    /// 邀請碼到期時間；`nil` = 沒有到期日（TTL 上線前建立的舊碼）。
    var expiresAt: Date? = nil
    /// 重新產生邀請碼。傳 `nil` 代表這個情境不提供重新產生。
    var onRegenerate: (() async throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showingShareSheet = false
    @State private var isRegenerating = false
    @State private var regenerateError: String?

    private var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// 底部提示三態：未過期照舊；過期且能重新產生 → 指向按鈕；過期但不是擁有者
    /// （`onRegenerate == nil`）→ 指向擁有者，否則會叫他按一個畫面上沒有的按鈕。
    private var footerText: LocalizedStringKey {
        guard isExpired else { return "打開 App → 輸入邀請碼即可加入" }
        return onRegenerate == nil
            ? "請向帳目擁有者索取新的邀請碼"
            : "請按「重新產生邀請碼」取得新的 6 碼"
    }

    /// 分享訊息要同時給兩條路：沒有 iPhone 的朋友點網頁版連結（網址已帶邀請碼，
    /// 不必再手動輸入 6 碼），有 iPhone 的再裝 App。順序是「加入什麼 → 一鍵連結 →
    /// App Store」，因為這段多半被貼進 LINE，排在後面的沒人看。
    ///
    /// 邀請碼一定要自己佔一行。App 上現有的使用者全是 iOS→iOS，流程是
    /// 「長按複製邀請碼 → 打開 App → 貼進輸入框」；而且這個 app 沒有 universal link
    /// （AASA 回 404、entitlements 沒有 associated-domains），iPhone 點網頁連結只會進網頁版。
    /// 把 6 碼塞進全形括號裡，等於逼他們在 LINE 裡精準框選括號中間那段——整行純文字長按就選得起來，
    /// 括號中間則明顯難很多。
    private var shareMessage: String {
        [
            localized("邀請你加入「\(groupName)」一起分帳"),
            "",
            localized("點連結直接加入："),
            SplityLinks.webJoin(code: inviteCode),
            "",
            localized("用 iPhone 的話可以改用 App："),
            SplityLinks.appStore,
            localized("邀請碼：\(inviteCode)"),
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(localized("關閉"))
                        .padding(8)
                        .background(Color(.systemGray5), in: Circle())
                }
            }
            .padding(.top, 8)

            Spacer()

            Text("分享「\(groupName)」")
                .font(.title2.bold())

            Text(inviteCode)
                .font(.system(.largeTitle, design: .monospaced).bold())
                .kerning(8)
                .foregroundStyle(isExpired ? .secondary : .primary)
                .padding(.vertical, 20)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))

            if isExpired {
                Label("邀請碼已過期", systemImage: "clock.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let expiresAt {
                Text("有效至 \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = inviteCode
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Text(copied ? "已複製" : "複製邀請碼")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.primary)
                .disabled(isExpired)

                Button {
                    showingShareSheet = true
                } label: {
                    Text("分享")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isExpired)

                if let onRegenerate {
                    Button {
                        regenerateError = nil
                        isRegenerating = true
                        Task {
                            do { try await onRegenerate() }
                            catch { regenerateError = error.localizedDescription }
                            isRegenerating = false
                        }
                    } label: {
                        if isRegenerating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("重新產生邀請碼").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.subheadline)
                    .disabled(isRegenerating)
                }
            }

            if let regenerateError {
                Text(regenerateError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: [shareMessage])
        }
    }
}

#Preview {
    InviteShareSheet(
        groupName: "勞動節沖繩",
        inviteCode: "K3F9X2",
        expiresAt: Date().addingTimeInterval(90 * 24 * 60 * 60),
        onRegenerate: {}
    )
}
