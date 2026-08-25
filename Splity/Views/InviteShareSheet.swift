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

    private var shareMessage: String {
        """
        一起來分帳！

        加入「\(groupName)」帳目
        邀請碼：\(inviteCode)

        下載 Splity：https://apps.apple.com/app/id6760477233
        打開 App → 輸入邀請碼即可加入
        """
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
