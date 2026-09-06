import SwiftUI
import SwiftData

/// 新增快速分帳：成員與先出金額，結果即時顯示，儲存後成為唯讀紀錄。
struct QuickSplitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private struct Row: Identifiable {
        let id = UUID()
        var name = ""
        var paidText = ""
    }

    @State private var title = ""
    @State private var currencyCode = QuickSplitPrefs.lastCurrency
    @State private var rows: [Row] = [Row(), Row()]
    @State private var showingCurrencyPicker = false
    private enum Field: Hashable {
        case name(UUID)
        case paid(UUID)
    }

    @FocusState private var focusedField: Field?

    private var participants: [QuickSplitParticipant] {
        rows.map { QuickSplitParticipant(id: $0.id, name: $0.name, paid: Decimal.parseAmount($0.paidText) ?? 0) }
    }

    private var result: QuickSplitResult {
        QuickSplitCalculator.compute(participants: participants, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        result.participantCount >= 2 && result.total > 0
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

                Section {
                    ForEach($rows) { $row in
                        HStack {
                            TextField("姓名", text: $row.name)
                                .focused($focusedField, equals: .name(row.id))
                                .accessibilityIdentifier("quickSplitName")
                            TextField("0", text: $row.paidText)
                                .focused($focusedField, equals: .paid(row.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .accessibilityLabel("\(row.name.isEmpty ? String(localized: "成員") : row.name) 先出金額")
                                .accessibilityIdentifier("quickSplitPaid")
                        }
                    }
                    .onDelete { offsets in rows.remove(atOffsets: offsets) }

                    Button {
                        let row = Row()
                        rows.append(row)
                        focusedField = .name(row.id)
                    } label: {
                        Label("新增成員", systemImage: "plus.circle")
                    }
                } header: {
                    Text("成員與先出金額")
                } footer: {
                    Text("沒先出錢的人留 0。至少兩位成員、總額大於 0 才能儲存。")
                }

                Section("結果") {
                    LabeledContent("總額") {
                        Text(result.total, format: .currency(code: currencyCode))
                    }
                    LabeledContent("每人應付") {
                        Text(result.perShare, format: .currency(code: currencyCode))
                            .bold()
                    }
                    if result.transfers.isEmpty {
                        Text(canSave ? "剛好平均，不需要轉帳" : "填好成員與金額後，這裡會顯示誰給誰多少")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        }
    }

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
        try? modelContext.save()
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
