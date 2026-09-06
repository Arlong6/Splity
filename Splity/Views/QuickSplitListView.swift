import SwiftUI
import SwiftData

/// 快速分帳：一次性的飯局分帳，不建群組。第一層是過去的紀錄清單。
struct QuickSplitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QuickSplit.date, order: .reverse) private var splits: [QuickSplit]

    @State private var showingNew = false

    var body: some View {
        SwiftUI.Group {
            if splits.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(splits) { split in
                        NavigationLink(value: split) {
                            row(split)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("快速分帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("新增快速分帳", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            QuickSplitEditView()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("還沒有快速分帳", systemImage: "person.2.badge.plus")
        } description: {
            Text("偶爾的飯局不用建群組。輸入誰先出了多少，馬上算出每人應付與誰給誰。")
        } actions: {
            Button { showingNew = true } label: {
                Text("開始分帳")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func row(_ split: QuickSplit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(split.title)
                    .font(.headline)
                Text("\(split.date.formatted(date: .abbreviated, time: .omitted)) · \(split.participants.count) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(split.total, format: .currency(code: split.currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(splits[index])
        }
        try? modelContext.save()
    }
}
