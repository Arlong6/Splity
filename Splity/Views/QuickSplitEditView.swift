import SwiftUI
import SwiftData

/// 新增快速分帳：姓名、先出金額、應付金額三欄，結果即時顯示，儲存後成為唯讀紀錄。
struct QuickSplitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private struct Row: Identifiable {
        let id = UUID()
        var name = ""
        var paidText = ""
        var shareText = ""
    }

    private enum Field: Hashable {
        case name(UUID)
        case paid(UUID)
        case share(UUID)
    }

    private static let amountColumnWidth: CGFloat = 88

    @State private var title = ""
    @State private var currencyCode = QuickSplitPrefs.lastCurrency
    @State private var rows: [Row] = [Row(), Row()]
    @State private var showingCurrencyPicker = false
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private var participants: [QuickSplitParticipant] {
        rows.map { row in
            QuickSplitParticipant(
                id: row.id,
                name: row.name,
                paid: Decimal.parseAmount(row.paidText) ?? 0,
                // 留空 = 平分剩下的；填 0 = 不用付。兩者不可混為一談。
                share: row.shareText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil
                    : Decimal.parseAmount(row.shareText)
            )
        }
    }

    private var result: QuickSplitResult {
        QuickSplitCalculator.compute(participants: participants, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        result.participantCount >= 2 && result.total > 0 && result.isBalanced
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名稱") {
                    TextField("例如：週五晚餐", text: $title)
                }

                Section("幣別") {
                    Button { showingCurrencyPicker = true } label: {
                        HStack {
                            Text(CurrencyService.flag(for: currencyCode))
                            Text(currencyCode).foregroundStyle(.primary)
                            Text(CurrencyService.displayName(for: currencyCode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                membersSection
                resultSection
            }
            .navigationTitle("快速分帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
                // 數字鍵盤沒有收起鍵，提供「完成」
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerView(selection: $currencyCode)
            }
            .alert("儲存失敗", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - 成員

    private var membersSection: some View {
        Section {
            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    TextField("姓名", text: $row.name)
                        .focused($focusedField, equals: .name(row.id))
                        .accessibilityIdentifier("quickSplitName")

                    TextField("0", text: $row.paidText)
                        .focused($focusedField, equals: .paid(row.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: Self.amountColumnWidth)
                        .accessibilityIdentifier("quickSplitPaid")
                        .accessibilityLabel("\(displayName(row)) 先出金額")

                    TextField("", text: $row.shareText, prompt: autoSharePrompt)
                        .focused($focusedField, equals: .share(row.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: Self.amountColumnWidth)
                        .accessibilityIdentifier("quickSplitShare")
                        .accessibilityLabel("\(displayName(row)) 應付金額")
                }
            }
            .onDelete { offsets in
                focusedField = nil
                rows.remove(atOffsets: offsets)
            }

            Button {
                let row = Row()
                rows.append(row)
                focusedField = .name(row.id)
            } label: {
                Label("新增成員", systemImage: "plus.circle")
            }
        } header: {
            HStack(spacing: 8) {
                Text("姓名")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("先出")
                    .frame(width: Self.amountColumnWidth, alignment: .trailing)
                Text("應付")
                    .frame(width: Self.amountColumnWidth, alignment: .trailing)
            }
        } footer: {
            Text("先出留空視為 0。應付留空代表平分剩下的，填 0 代表不用付。至少兩位成員、總額大於 0 才能儲存。")
        }
    }

    /// 應付欄留空時，用灰字顯示他實際會分攤到的金額
    private var autoSharePrompt: Text? {
        guard result.autoCount > 0, result.total > 0 else { return nil }
        return Text(result.autoShare, format: .number)
    }

    private func displayName(_ row: Row) -> String {
        row.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? localized("成員")
            : row.name
    }

    // MARK: - 結果

    private var resultSection: some View {
        Section("結果") {
            LabeledContent("總額") {
                Text(result.total, format: .currency(code: currencyCode))
            }
            if result.autoCount > 0 {
                LabeledContent("平均每人") {
                    Text(result.autoShare, format: .currency(code: currencyCode))
                        .bold()
                        .foregroundStyle(result.isOverAssigned ? .red : .primary)
                }
            }

            if !result.isBalanced {
                Label(unbalancedMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if result.isOverAssigned {
                Label("已填的應付超過總額，平均每人變成負數", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if result.transfers.isEmpty {
                if result.isBalanced {
                    Text(canSave ? "剛好平衡，不需要轉帳" : "填好成員與金額後，這裡會顯示誰給誰多少")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(result.transfers) { t in
                    HStack {
                        Text("\(t.from.name) → \(t.to.name)")
                        Spacer()
                        Text(t.amount, format: .currency(code: currencyCode))
                            .foregroundStyle(.orange)
                            .bold()
                    }
                }
            }
        }
    }

    private var unbalancedMessage: String {
        let assigned = result.assignedTotal.formatted(.currency(code: currencyCode))
        let gap = abs(result.remaining).formatted(.currency(code: currencyCode))
        return result.remaining > 0
            ? localized("應付合計 \(assigned)，比總額少 \(gap)")
            : localized("應付合計 \(assigned)，比總額多 \(gap)")
    }

    // MARK: - 儲存

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let finalTitle = trimmed.isEmpty
            ? Date().formatted(date: .abbreviated, time: .shortened)
            : trimmed
        let split = QuickSplit(
            title: finalTitle,
            currencyCode: currencyCode,
            participants: result.participants
        )
        modelContext.insert(split)
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            modelContext.delete(split)
            return
        }
        QuickSplitPrefs.lastCurrency = currencyCode
        dismiss()
    }
}

/// 每裝置的快速分帳偏好（UserDefaults、不同步）
enum QuickSplitPrefs {
    private static let currencyKey = "quickSplit.lastCurrency"

    static var lastCurrency: String {
        get { UserDefaults.standard.string(forKey: currencyKey) ?? Locale.current.currency?.identifier ?? "TWD" }
        set { UserDefaults.standard.set(newValue, forKey: currencyKey) }
    }
}
