import SwiftUI
import SwiftData

/// 快速分帳紀錄（唯讀）：摘要、每人先出與應付、誰給誰多少。
struct QuickSplitResultView: View {
    let split: QuickSplit

    private static let amountColumnWidth: CGFloat = 92

    private var result: QuickSplitResult {
        QuickSplitCalculator.compute(participants: split.participants, currencyCode: split.currencyCode)
    }

    private var currencyCode: String { split.currencyCode }

    private var shareText: String {
        var lines = [localized("【\(split.title)】快速分帳")]
        let totalText = result.total.formatted(.currency(code: currencyCode))
        lines.append(localized("總額 \(totalText)，\(result.participantCount) 人"))
        for p in result.participants {
            let paid = p.paid.formatted(.currency(code: currencyCode))
            let share = result.share(for: p).formatted(.currency(code: currencyCode))
            lines.append(localized("• \(p.name)　先出 \(paid)　應付 \(share)"))
        }
        if !result.transfers.isEmpty {
            lines.append("")
            for t in result.transfers {
                lines.append("• \(t.from.name) → \(t.to.name)  \(t.amount.formatted(.currency(code: currencyCode)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                breakdownCard
                if result.transfers.isEmpty {
                    Text("剛好平衡，不需要轉帳")
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
                Text(result.total, format: .currency(code: currencyCode))
                    .font(.title3.bold())
                Text("總額 · \(result.participantCount) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if result.autoCount > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.autoShare, format: .currency(code: currencyCode))
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                    Text("平均每人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("姓名")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("先出")
                    .frame(width: Self.amountColumnWidth, alignment: .trailing)
                Text("應付")
                    .frame(width: Self.amountColumnWidth, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(result.participants) { p in
                HStack(spacing: 8) {
                    Text(p.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(p.paid, format: .currency(code: currencyCode))
                        .frame(width: Self.amountColumnWidth, alignment: .trailing)
                        .foregroundStyle(p.paid > 0 ? .primary : .secondary)
                    Text(result.share(for: p), format: .currency(code: currencyCode))
                        .frame(width: Self.amountColumnWidth, alignment: .trailing)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.name) 先出 \(p.paid.formatted(.currency(code: currencyCode)))，應付 \(result.share(for: p).formatted(.currency(code: currencyCode)))")

                if p.id != result.participants.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
