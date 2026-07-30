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


// MARK: - Frozen-pane scroll model

/// 捲動位移模型:靜止=(0,0),往下/右捲為負。用 @Observable 而非 @State——
/// 只有兩個凍結覆蓋層的 body 讀它,捲動每一格畫面只重繪覆蓋層,
/// 整張表格與資料運算完全不重跑(否則手機上大表會明顯卡頓)。
@Observable
private final class SpreadsheetScrollModel {
    var offset: CGPoint = .zero
}

/// 品項欄凍結覆蓋:縱向跟著內容捲、橫向釘在左緣。獨立 View 隔離 offset 觀察範圍。
private struct PinnedColumnOverlay<Content: View>: View {
    let model: SpreadsheetScrollModel
    let columnWidth: CGFloat
    let viewportHeight: CGFloat
    let content: Content

    var body: some View {
        let o = model.offset
        ZStack(alignment: .topLeading) {
            content.offset(x: max(o.x, 0), y: o.y)
        }
        .frame(width: columnWidth + max(o.x, 0), height: viewportHeight, alignment: .topLeading)
        .clipped()
        .shadow(color: .black.opacity(o.x < -1 ? 0.18 : 0), radius: 3, x: 2, y: 0)
        .allowsHitTesting(false)
    }
}

/// 表頭列凍結覆蓋:橫向跟著內容捲、縱向釘在頂端(左上角「品項」雙向釘住)。
private struct PinnedHeaderOverlay<Content: View, Corner: View>: View {
    let model: SpreadsheetScrollModel
    let rowHeight: CGFloat
    let viewportWidth: CGFloat
    let content: Content
    let corner: Corner

    var body: some View {
        let o = model.offset
        ZStack(alignment: .topLeading) {
            content.offset(x: o.x, y: max(o.y, 0))
            corner.offset(x: max(o.x, 0), y: max(o.y, 0))
        }
        .frame(width: viewportWidth, height: rowHeight + max(o.y, 0), alignment: .topLeading)
        .clipped()
        .shadow(color: .black.opacity(o.y < -1 ? 0.18 : 0), radius: 3, x: 0, y: 2)
        .allowsHitTesting(false)
    }
}

// MARK: - View

struct ExpenseSpreadsheetView: View {
    let group: Group
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FirebaseSharingManager.self) private var sharingManager

    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var syncError: String?
    /// 注意:父 view body 不可讀取 scrollModel.offset(會把整張表捲進每格重繪)。
    @State private var scrollModel = SpreadsheetScrollModel()

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

    /// 目前使用者認領的成員在 sortedMembers 的欄位索引(整欄高亮用);未認領為 nil
    private var myColumnIndex: Int? {
        guard let me = sharingManager.claimedMember(in: group) else { return nil }
        return sortedMembers.firstIndex { $0.id == me.id }
    }

    private var sortedExpenses: [Expense] {
        group.expenses.filter { !$0.archived }.sorted { $0.totalAmount > $1.totalAmount }
    }

    /// 大家要付的(直接讀 expense.splits 關聯;先前用無 predicate 的全域 @Query 掃整個資料庫,
    /// 群組一多就是效能地雷)
    private var evRows: [Row] {
        let ms = sortedMembers
        return sortedExpenses.map { exp in
            let byMember = Dictionary(
                exp.splits.compactMap { s in s.member.map { ($0.id, s.amount) } },
                uniquingKeysWith: { first, _ in first }
            )
            return Row(
                id: exp.id,
                title: exp.title,
                amounts: ms.map { byMember[$0.id] ?? 0 },
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

    /// 大家要付的小計 per member
    private var evSubtotals: [Decimal] {
        let rows = evRows
        guard !rows.isEmpty else { return Array(repeating: 0, count: sortedMembers.count) }
        return rows[0].amounts.indices.map { j in
            rows.reduce(Decimal(0)) { $0 + $1.amounts[j] }
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
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                // 內容比視口小時 2D ScrollView 會置中;強制至少填滿視口讓表格固定靠左上,
                // 凍結覆蓋層(以左上為錨點)才能與內容對齊。
                tableContent
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
            .onScrollGeometryChange(for: CGPoint.self) { g in
                // 相對靜止位置的位移:contentOffset 在靜止時 = -adjustedInset,兩者相加歸零
                CGPoint(x: -(g.contentOffset.x + g.contentInsets.leading),
                        y: -(g.contentOffset.y + g.contentInsets.top))
            } action: { _, new in
                scrollModel.offset = new
            }
            .refreshable { await refresh() }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { v in scale = min(max(baseScale * v, 0.4), 3.0) }
                    .onEnded   { _ in baseScale = scale }
            )
            // 凍結窗格:品項欄(橫向捲動時固定)與表頭列(縱向捲動時固定)。
            // 純視覺複本、不攔截手勢;拖曳/縮放/下拉更新照常作用在底下的 ScrollView。
            .overlay(alignment: .topLeading) {
                PinnedColumnOverlay(
                    model: scrollModel,
                    columnWidth: iW,
                    viewportHeight: geo.size.height,
                    content: leftColumn
                )
            }
            .overlay(alignment: .topLeading) {
                PinnedHeaderOverlay(
                    model: scrollModel,
                    rowHeight: rH,
                    viewportWidth: geo.size.width,
                    content: headerRow,
                    corner: hCell("品項", w: iW)
                )
            }
        }
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

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        let ms  = sortedMembers
        let ev  = evRows
        let pu  = puRows
        let net = netAmounts

        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────
            headerRow

            // ── 大家要付的 ───────────────────────────────────────
            secRow("大家要付的")
            ForEach(Array(ev.enumerated()), id: \.element.id) { idx, row in
                HStack(spacing: 0) {
                    lCell(row.title, w: iW, bg: rowBg(idx))
                    ForEach(row.amounts.indices, id: \.self) { j in
                        dCell(row.amounts[j], w: mW, bg: rowBg(idx), highlight: j == myColumnIndex)
                    }
                    dCell(row.total, w: tW, bg: rowBg(idx))
                }
            }

            // ── 大家要付的 小計 ───────────────────────────────────
            let sub = evSubtotals
            HStack(spacing: 0) {
                lCell("個人花費", w: iW, bg: amberColor, bold: true)
                ForEach(sub.indices, id: \.self) { i in
                    netCell(sub[i], w: mW, highlight: i == myColumnIndex)
                }
                netCell(sub.reduce(0, +), w: tW)
            }

            // ── 有人先墊 ─────────────────────────────────────────
            secRow("有人先墊")
            ForEach(Array(pu.enumerated()), id: \.element.id) { idx, row in
                HStack(spacing: 0) {
                    lCell(row.title, w: iW, bg: rowBg(idx))
                    ForEach(row.amounts.indices, id: \.self) { j in
                        dCell(row.amounts[j], w: mW, bg: rowBg(idx), highlight: j == myColumnIndex)
                    }
                    dCell(row.total, w: tW, bg: rowBg(idx))
                }
            }

            // ── 總花費 ───────────────────────────────────────────
            HStack(spacing: 0) {
                lCell("應付/應收", w: iW, bg: amberColor, bold: true)
                ForEach(net.indices, id: \.self) { i in
                    netCell(net[i], w: mW, highlight: i == myColumnIndex)
                }
                dCell(0, w: tW, bg: amberColor)
            }
        }
    }

    /// 表頭列(內容與凍結覆蓋共用同一份,確保欄寬對齊)
    private var headerRow: some View {
        HStack(spacing: 0) {
            hCell("品項", w: iW)
            ForEach(Array(sortedMembers.enumerated()), id: \.element.persistentModelID) { i, m in
                hCell(m.name, w: mW, highlight: i == myColumnIndex)
            }
            hCell("總價", w: tW)
        }
    }

    // MARK: - Frozen panes(凍結表頭/品項欄的內容;覆蓋層本體見檔案頂部的兩個獨立 View)

    /// 品項欄的完整縱向序列,列高與 tableContent 一一對應(皆為 rH)。
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            hCell("品項", w: iW)
            secLeftCell("大家要付的")
            ForEach(Array(evRows.enumerated()), id: \.element.id) { idx, row in
                lCell(row.title, w: iW, bg: rowBg(idx))
            }
            lCell("個人花費", w: iW, bg: amberColor, bold: true)
            secLeftCell("有人先墊")
            ForEach(Array(puRows.enumerated()), id: \.element.id) { idx, row in
                lCell(row.title, w: iW, bg: rowBg(idx))
            }
            lCell("應付/應收", w: iW, bg: amberColor, bold: true)
        }
    }

    /// 凍結欄裡的段落標題切片(需不透明,否則底下捲動內容會透出)
    private func secLeftCell(_ label: String) -> some View {
        Text(label)
            .font(.system(size: fS, weight: .bold))
            .foregroundStyle(Color.indigo)
            .padding(.leading, 8)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: iW, height: rH, alignment: .leading)
            .background(Color.indigo.opacity(0.08))
            .background(Color(.systemBackground))
            .border(Color(.systemGray4), width: 0.5)
    }

    // MARK: - Cell builders

    private func hCell(_ text: String, w: CGFloat, highlight: Bool = false) -> some View {
        Text(text)
            .font(.system(size: fS, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: w, height: rH)
            .background(highlight ? Color.teal : Color.indigo)
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

    private func dCell(_ value: Decimal, w: CGFloat, bg: Color, highlight: Bool = false) -> some View {
        Text(fmt(value))
            .font(.system(size: fS, weight: highlight ? .bold : .semibold))
            .foregroundStyle(Color.black)
            .monospacedDigit()
            .frame(width: w, height: rH)
            .background(highlight ? Color.teal.opacity(0.18) : Color.clear)
            .background(bg)
            .border(Color(.systemGray4), width: 0.5)
    }

    private func netCell(_ value: Decimal, w: CGFloat, highlight: Bool = false) -> some View {
        Text(fmt(value))
            .font(.system(size: fS, weight: highlight ? .heavy : .bold))
            .monospacedDigit()
            .foregroundStyle(Color.black)
            .frame(width: w, height: rH)
            .background(highlight ? Color.teal.opacity(0.25) : Color.clear)
            .background(amberColor)
            .border(Color(.systemGray4), width: 0.5)
    }

    private func fmt(_ value: Decimal) -> String {
        let scale = Decimal.currencyFractionDigits(group.baseCurrencyCode)
        var rounded = Decimal()
        var mutable = value
        NSDecimalRound(&rounded, &mutable, scale, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
