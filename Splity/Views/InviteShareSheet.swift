import SwiftUI

struct InviteShareSheet: View {
    let groupName: String
    let inviteCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var showingShareSheet = false

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
                .padding(.vertical, 20)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))

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

                Button {
                    showingShareSheet = true
                } label: {
                    Text("分享")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("打開 App → 輸入邀請碼即可加入")
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
    InviteShareSheet(groupName: "勞動節沖繩", inviteCode: "K3F9X2")
}
