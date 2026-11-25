import SwiftUI
import Charts

/// 帳本的分類統計：甜甜圈圖加上各類金額與百分比（大家合計，結算幣別）。
struct CategoryStatsView: View {
    let group: Group

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var mailFailed = false

    private var totals: [CategoryTotal] { CategoryStats.totals(for: group.expenses) }
    private var currencyCode: String { group.baseCurrencyCode }

    var body: some View {
        let totals = self.totals
        List {
            if totals.isEmpty {
                Text("還沒有可以統計的花費")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    chart(totals)
                        .frame(height: 240)
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(totals) { row($0) }
                }
            }

            Section {
                Button("分類不合用？告訴我們") { sendSuggestion() }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("categorySuggestionButton")
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("分類統計")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .alert("開不了郵件 App", isPresented: $mailFailed) {
            Button("好") {}
        } message: {
            Text("請改寄到 \(SupportMail.address)")
        }
    }

    private func chart(_ totals: [CategoryTotal]) -> some View {
        Chart(totals) { item in
            SectorMark(
                angle: .value("金額", NSDecimalNumber(decimal: item.amount).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(Self.color(for: item.category))
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let rect = geo[frame]
                    VStack(spacing: 2) {
                        Text("總計")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CategoryStats.grandTotal(totals), format: .currency(code: currencyCode))
                            .font(.title3.bold())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    .frame(width: rect.width * 0.55)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .accessibilityHidden(true) // 下方清單已列出同樣的數字，VoiceOver 讀清單即可
    }

    private func row(_ item: CategoryTotal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category?.symbolName ?? "questionmark.circle")
                .foregroundStyle(Self.color(for: item.category))
                .frame(width: 24)
            Text(item.category?.displayName ?? ExpenseCategory.uncategorizedName)
                .foregroundStyle(item.category == nil ? .secondary : .primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.amount, format: .currency(code: currencyCode))
                    .monospacedDigit()
                Text(verbatim: "\(item.percent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sendSuggestion() {
        guard let url = SupportMail.url(body: "", subject: localized("Splity 分類建議")) else {
            mailFailed = true
            return
        }
        openURL(url) { accepted in
            if !accepted { mailFailed = true }
        }
    }

    /// 每類固定顏色，圖和清單一致；未分類用灰色。系統色在深色模式會自動調亮。
    static func color(for category: ExpenseCategory?) -> Color {
        switch category {
        case .food: return .orange
        case .transport: return .blue
        case .lodging: return .indigo
        case .fun: return .pink
        case .shopping: return .teal
        case .daily: return .green
        case .other: return .brown
        case nil: return .gray
        }
    }
}
