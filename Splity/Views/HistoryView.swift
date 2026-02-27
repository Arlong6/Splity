import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HistoryRecord.date, order: .reverse) private var records: [HistoryRecord]

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.action == .settled
                              ? "checkmark.circle.fill"
                              : "trash.circle.fill")
                            .font(.title2)
                            .foregroundStyle(record.action == .settled ? .green : .red)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.groupName)
                                .font(.headline)
                            Text("\(record.memberCount) 人・\(record.expenseCount) 筆花費")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(record.date, format: .dateTime.year().month().day())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    offsets.forEach { modelContext.delete(records[$0]) }
                }
            }
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(
                        "沒有歷史紀錄",
                        systemImage: "clock",
                        description: Text("結清或刪除帳目後會出現紀錄")
                    )
                }
            }
            .navigationTitle("歷史紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("清除全部") {
                            records.forEach { modelContext.delete($0) }
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
