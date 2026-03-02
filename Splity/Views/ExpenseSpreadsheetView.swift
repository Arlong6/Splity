import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSV Export

private struct CSVExportFile: Transferable {
    let filename: String
    let csvString: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.filename)
            try Data(file.csvString.utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Row model

private struct Row: Identifiable {
    let id: UUID        // expense.id
    let title: String
    let amounts: [Decimal]
    let total: Decimal
}

// MARK: - View

struct ExpenseSpreadsheetView: View {
    let group: Group
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0

    @Query private var allSplits: [ExpenseSplit]

    // 總花費列底色：飽和金黃，黑字對比清晰
    private let amberColor = Color(red: 1.0, green: 0.80, blue: 0.05)

    // Base dimensions at scale = 1
    private let baseItemW: CGFloat   = 80
    private let baseMemberW: CGFloat = 60
    private let baseTotalW: CGFloat  = 60
    private let baseRowH: CGFloat    = 30
    private let baseFontSize: CGFloat = 12

    private var iW: CGFloat { baseItemW   * scale }
    private var mW: CGFloat { baseMemberW * scale }
    private var tW: CGFloat { baseTotalW  * scale }
    private var rH: CGFloat { baseRowH    * scale }
    private var fS: CGFloat { baseFontSize * scale }

    // Generate N unique pastel colors by evenly spacing hues around the color wheel.
    // Same index = same color in both sections; no repeats.
    private var expenseColors: [Color] {
        let n = max(sortedExpenses.count, 1)
        return (0..<n).map { i in
            Color(hue: Double(i) / Double(n), saturation: 0.22, brightness: 0.96)
        }
    }

    private func rowBg(_ index: Int) -> Color {
        guard index < expenseColors.count else { return Color(.systemBackground) }
        return expenseColors[index]
    }

    // MARK: - Data

    private var sortedMembers: [Member] {
        group.members.sorted { $0.name < $1.name }
    }

    private var sortedExpenses: [Expense] {
        group.expenses.sorted { ($0.date ?? $0.createdAt) < ($1.date ?? $1.createdAt) }
    }

    private var splitLookup: [UUID: [UUID: Decimal]] {
        var map: [UUID: [UUID: Decimal]] = [:]
        for split in allSplits {
            guard let expID = split.expense?.id,
                  let memID = split.member?.id else { continue }
            map[expID, default: [:]][memID] = split.amount
        }
        return map
    }

    /// 大家要付的
    private var evRows: [Row] {
        let ms  = sortedMembers
        let lkp = splitLookup
        return sortedExpenses.map { exp in
            Row(
                id: exp.id,
                title: exp.title,
                amounts: ms.map { m in lkp[exp.id]?[m.id] ?? 0 },
                total: exp.totalAmount
            )
        }
    }

    /// 有人先墊
    private var puRows: [Row] {
        let ms = sortedMembers
        return sortedExpenses.map { exp in
            Row(
                id: exp.id,
                title: exp.title,
                amounts: ms.map { m in
                    exp.paidBy?.id == m.id ? -exp.totalAmount : 0
                },
                total: -exp.totalAmount
            )
        }
    }

    /// 總花費 = -netBalance per member
    private var netAmounts: [Decimal] {
        let bal = SettlementCalculator.computeNetBalances(expenses: sortedExpenses)
        return sortedMembers.map { -(bal[$0] ?? 0) }
    }

    private var tableWidth: CGFloat {
        iW + mW * CGFloat(sortedMembers.count) + tW
    }

    // MARK: - Body

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            tableContent
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in scale = min(max(baseScale * v, 0.4), 3.0) }
                .onEnded   { _ in baseScale = scale }
        )
        .navigationTitle("分帳明細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: CSVExportFile(
                        filename: "\(group.name)_分帳明細.csv",
                        csvString: SpreadsheetExporter.generateCSV(group: group)
                    ),
                    preview: SharePreview("\(group.name)_分帳明細.csv")
                ) {
                    Label("匯出", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        let ms  = sortedMembers
        let ev  = evRows
        let pu  = puRows
        let net = netAmounts

        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────
            HStack(spacing: 0) {
                hCell("品項", w: iW)
                ForEach(ms, id: \.persistentModelID) { m in hCell(m.name, w: mW) }
                hCell("總價", w: tW)
            }

            // ── 大家要付的 ───────────────────────────────────────
            secRow("大家要付的")
            ForEach(Array(ev.enumerated()), id: \.element.id) { idx, row in
                HStack(spacing: 0) {
                    lCell(row.title, w: iW, bg: rowBg(idx))
                    ForEach(row.amounts.indices, id: \.self) { j in
                        dCell(row.amounts[j], w: mW, bg: rowBg(idx))
                    }
                    dCell(row.total, w: tW, bg: rowBg(idx))
                }
            }

            // ── 有人先墊 ─────────────────────────────────────────
            secRow("有人先墊")
            ForEach(Array(pu.enumerated()), id: \.element.id) { idx, row in
                HStack(spacing: 0) {
                    lCell(row.title, w: iW, bg: rowBg(idx))
                    ForEach(row.amounts.indices, id: \.self) { j in
                        dCell(row.amounts[j], w: mW, bg: rowBg(idx))
                    }
                    dCell(row.total, w: tW, bg: rowBg(idx))
                }
            }

            // ── 總花費 ───────────────────────────────────────────
            HStack(spacing: 0) {
                lCell("總花費", w: iW, bg: amberColor, bold: true)
                ForEach(net.indices, id: \.self) { i in
                    netCell(net[i], w: mW)
                }
                dCell(0, w: tW, bg: amberColor)
            }
        }
    }

    // MARK: - Cell builders

    private func hCell(_ text: String, w: CGFloat) -> some View {
        Text(text)
            .font(.system(size: fS, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: w, height: rH)
            .background(Color.indigo)
            .border(Color.indigo.opacity(0.5), width: 0.5)
    }

    private func secRow(_ label: String) -> some View {
        Text(label)
            .font(.system(size: fS, weight: .bold))
            .foregroundStyle(Color.indigo)
            .padding(.leading, 8)
            .frame(width: tableWidth, height: rH, alignment: .leading)
            .background(Color.indigo.opacity(0.08))
            .border(Color(.systemGray4), width: 0.5)
    }

    private func lCell(_ text: String, w: CGFloat, bg: Color, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: fS, weight: bold ? .heavy : .semibold))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 4)
            .frame(width: w, height: rH, alignment: .leading)
            .background(bg)
            .border(Color(.systemGray4), width: 0.5)
    }

    private func dCell(_ value: Decimal, w: CGFloat, bg: Color) -> some View {
        Text(fmt(value))
            .font(.system(size: fS, weight: .semibold))
            .foregroundStyle(Color.black)
            .monospacedDigit()
            .frame(width: w, height: rH)
            .background(bg)
            .border(Color(.systemGray4), width: 0.5)
    }

    private func netCell(_ value: Decimal, w: CGFloat) -> some View {
        Text(fmt(value))
            .font(.system(size: fS, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.black)
            .frame(width: w, height: rH)
            .background(amberColor)
            .border(Color(.systemGray4), width: 0.5)
    }

    private func fmt(_ value: Decimal) -> String {
        var rounded = Decimal()
        var mutable = value
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
