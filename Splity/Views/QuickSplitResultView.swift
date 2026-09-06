import SwiftUI
import SwiftData

/// 快速分帳紀錄（唯讀）：摘要、每人先出、誰給誰多少。
struct QuickSplitResultView: View {
    let split: QuickSplit

    private var result: QuickSplitResult {
        QuickSplitCalculator.compute(participants: split.participants, currencyCode: split.currencyCode)
    }

    private var currencyCode: String { split.currencyCode }

    private var shareText: String {
        var lines = ["【\(split.title)】快速分帳"]
        lines.append("總額 \(result.total.formatted(.currency(code: currencyCode)))，\(result.participantCount) 人，每人 \(result.perShare.formatted(.currency(code: currencyCode)))")
        for t in result.transfers {
            lines.append("• \(t.from.name) → \(t.to.name)  \(t.amount.formatted(.currency(code: currencyCode)))")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                paidList
                if result.transfers.isEmpty {
                    Text("剛好平均，不需要轉帳")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(result.transfers) { t in
                        SettlementCardView(
                            fromName: t.from.name,
                            toName: t.to.name,
                            amount: t.amount,
                            currencyCode: currencyCode
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(split.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.perShare, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                Text("每人應付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(result.total, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                Text("總額 · \(result.participantCount) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var paidList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("先出金額")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
            ForEach(result.participants) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(p.paid, format: .currency(code: currencyCode))
                        .foregroundStyle(p.paid > 0 ? .primary : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if p.id != result.participants.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
