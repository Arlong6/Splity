import SwiftUI
import SwiftData

struct MemberClaimView: View {
    @Bindable var group: Group
    var onClaim: (Member) -> Void
    var onSkip: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(FirebaseSharingManager.self) private var sharingManager

    @State private var showingAddNew = false
    @State private var newMemberName = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var sortedMembers: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if !sortedMembers.isEmpty {
                    Section("選擇你是哪一位") {
                        ForEach(sortedMembers) { member in
                            claimRow(member)
                        }
                    }
                }

                Section {
                    Button {
                        newMemberName = ""
                        showingAddNew = true
                    } label: {
                        Label(sortedMembers.isEmpty ? "輸入你的名字" : "以新的身份加入", systemImage: "person.badge.plus")
                    }
                }

                if !sortedMembers.isEmpty {
                    Section {
                        Text("你選擇的身份會綁定到這個裝置，其他成員會看到你做的變更。未被選擇的成員是「幽靈成員」，任何人都能幫他代記帳。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("選擇你的身份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onSkip != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("稍後再說") {
                            onSkip?()
                            dismiss()
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .alert("你的名字", isPresented: $showingAddNew) {
                TextField("名字", text: $newMemberName)
                Button("取消", role: .cancel) { newMemberName = "" }
                Button("確認") { addAndClaim() }
            }
            .alert("失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isBusy {
                    ProgressView().padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func claimRow(_ member: Member) -> some View {
        let isMine = member.claimedByUid != nil && member.claimedByUid == sharingManager.currentUserId
        let isTaken = member.claimedByUid != nil && !isMine

        Button {
            guard !isTaken else { return }
            claim(member)
        } label: {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Text(String(member.name.prefix(1)))
                        .font(.subheadline.bold())
                        .foregroundStyle(.indigo)
                }
                Text(member.name)
                    .foregroundStyle(isTaken ? .secondary : .primary)
                Spacer()
                if isMine {
                    Text("已是你")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                } else if isTaken {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isTaken || isBusy)
    }

    private func claim(_ member: Member) {
        isBusy = true
        Task {
            do {
                try await sharingManager.claimMember(member, in: group, modelContext: modelContext)
                onClaim(member)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func addAndClaim() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !group.members.contains(where: { $0.name == trimmed }) else {
            errorMessage = "群組內已有同名成員，請選擇或換個名字"
            return
        }
        let member = Member(name: trimmed)
        modelContext.insert(member)
        group.members.append(member)
        newMemberName = ""
        claim(member)
    }
}
