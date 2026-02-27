import SwiftUI

struct SettlementView: View {
    @Environment(\.dismiss) private var dismiss
    let group: Group

    private var settlements: [Settlement] {
        SettlementCalculator.calculateSettlements(expenses: group.expenses)
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "TWD"
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
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // Payer
                VStack(spacing: 8) {
                    avatarCircle(name: settlement.from.name, color: .red)
                    Text(settlement.from.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .frame(minWidth: 70)

                // Arrow + Amount
                VStack(spacing: 6) {
                    Text(settlement.amount, format: .currency(code: currencyCode))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [.orange, Color(red: 1, green: 0.4, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.35))
                            .frame(height: 2)
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)

                // Receiver
                VStack(spacing: 8) {
                    avatarCircle(name: settlement.to.name, color: .green)
                    Text(settlement.to.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .frame(minWidth: 70)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            // Footer label
            HStack {
                Image(systemName: "hand.tap")
                    .font(.caption2)
                Text("\(settlement.from.name) 轉給 \(settlement.to.name)")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    private func avatarCircle(name: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 54, height: 54)
            Circle()
                .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                .frame(width: 54, height: 54)
            Text(String(name.prefix(1)))
                .font(.title2.bold())
                .foregroundStyle(color)
        }
    }
}
