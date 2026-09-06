import SwiftUI
import SwiftData

struct SettlementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FirebaseSharingManager.self) private var sharingManager
    let group: Group

    @State private var mode: SettlementMode = .minimized
    @State private var syncError: String?

    private var settlements: [Settlement] {
        let expenses = group.expenses.filter { !$0.archived }
        switch mode {
        case .minimized: return SettlementCalculator.calculateSettlements(expenses: expenses, currencyCode: currencyCode)
        case .hub:       return SettlementCalculator.calculateHubSettlements(expenses: expenses, currencyCode: currencyCode)
        }
    }

    private var currencyCode: String {
        group.baseCurrencyCode
    }

    private var totalAmount: Decimal {
        settlements.reduce(0) { $0 + $1.amount }
    }

    private var settlementShareText: String {
        var lines = ["【\(group.name)】結算明細"]
        for s in settlements {
            let amount = s.amount.formatted(.currency(code: currencyCode))
            lines.append("• \(s.from.name) → \(s.to.name)  \(amount)")
        }
        lines.append("\n共 \(settlements.count) 筆轉帳可結清所有帳目")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            if settlements.isEmpty {
                allSettledView
            } else {
                VStack(spacing: 16) {
                    Picker("結算方式", selection: $mode) {
                        Text("最少轉帳").tag(SettlementMode.minimized)
                        Text("集中付款").tag(SettlementMode.hub)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    summaryCard
                    ForEach(settlements) { settlement in
                        settlementCard(settlement)
                    }
                    Text("共需 \(settlements.count) 筆轉帳即可結清所有債務")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
            }
        }
        .refreshable { await refresh() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("結算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
            if !settlements.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: settlementShareText) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await refresh() }
        .alert("同步失敗", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("好") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
    }

    private func refresh() async {
        guard group.isShared else { return }
        do {
            try await sharingManager.pullChanges(for: group, modelContext: modelContext)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - All Settled

    private var allSettledView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }
            Text("全部結清了")
                .font(.title2.bold())
            Text("目前沒有未結清的款項")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(settlements.count) 筆轉帳")
                    .font(.title3.bold())
                Text("需要完成的付款")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(totalAmount, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                Text("合計金額")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Settlement Card

    private func settlementCard(_ settlement: Settlement) -> some View {
        SettlementCardView(
            fromName: settlement.from.name,
            toName: settlement.to.name,
            amount: settlement.amount,
            currencyCode: currencyCode
        )
    }
}
