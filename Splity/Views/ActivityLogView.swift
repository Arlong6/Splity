import SwiftUI

struct ActivityLogView: View {
    let group: Group
    @Environment(FirebaseSharingManager.self) private var sharingManager
    @Environment(\.dismiss) private var dismiss
    @State private var activities: [ActivityEntry] = []
    @State private var subscription: SharingSubscription?
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("變更紀錄")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .onAppear { start() }
        .onDisappear {
            subscription?.stop()
            subscription = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if activities.isEmpty {
            ContentUnavailableView(
                "還沒有變更紀錄",
                systemImage: "clock.arrow.circlepath",
                description: Text("成員的改動會即時顯示在這裡")
            )
        } else {
            List {
                ForEach(activities) { entry in
                    ActivityRow(entry: entry)
                }
            }
            .listStyle(.plain)
        }
    }

    private func start() {
        guard let id = group.firestoreGroupId else {
            hasLoaded = true
            return
        }
        subscription = sharingManager.listenToActivities(groupId: id) { entries in
            activities = entries
            hasLoaded = true
        }
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.actorName)
                        .font(.subheadline.bold())
                    Text(actionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("「\(entry.target)」")
                    .font(.callout)
                    .lineLimit(2)
                if let details = entry.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var actionText: String { entry.action.displayText }

    private var icon: String {
        switch entry.action {
        case .sharedGroup, .joinedGroup: return "person.2.fill"
        case .addedMember: return "person.badge.plus"
        case .removedMember: return "person.badge.minus"
        case .addedExpense: return "plus.circle.fill"
        case .editedExpense: return "pencil"
        case .renamedExpense: return "character.cursor.ibeam"
        case .deletedExpense: return "trash"
        case .restoredExpense: return "arrow.uturn.backward"
        case .settledGroup: return "checkmark.seal.fill"
        case .unsettledGroup: return "arrow.uturn.backward.circle"
        }
    }

    private var tint: Color {
        switch entry.action {
        case .sharedGroup, .joinedGroup: return .blue
        case .addedMember, .addedExpense: return .green
        case .removedMember, .deletedExpense: return .red
        case .editedExpense, .renamedExpense: return .orange
        case .restoredExpense, .unsettledGroup: return .gray
        case .settledGroup: return .mint
        }
    }
}
