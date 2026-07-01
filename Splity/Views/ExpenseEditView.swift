import SwiftUI
import SwiftData

struct ExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ExpenseEditViewModel
    @State private var saveError: String?
    @State private var showingCurrencyPicker = false

    let isEditing: Bool

    init(group: Group, expense: Expense? = nil) {
        _viewModel = State(initialValue: ExpenseEditViewModel(group: group, expense: expense))
        self.isEditing = expense != nil
    }

    /// 使用者輸入時的金額顯示幣別（可能與基準幣不同）
    private var inputCurrencyCode: String {
        viewModel.selectedCurrencyCode
    }

    /// 群組基準幣（顯示換算後預覽用）
    private var baseCurrencyCode: String {
        viewModel.group.baseCurrencyCode
    }

    var body: some View {
        Form {
            // MARK: - Details
            Section("基本資訊") {
                TextField("品項名稱", text: $viewModel.title)

                HStack {
                    Button {
                        showingCurrencyPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(CurrencyService.flag(for: inputCurrencyCode))
                            Text(inputCurrencyCode)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    TextField("金額", text: $viewModel.totalAmountString)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                if viewModel.isForeign {
                    HStack {
                        Text("匯率")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.isFetchingRate {
                            ProgressView()
                                .controlSize(.small)
                            Text("取得中…")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else if let rate = viewModel.lockedRate {
                            Text("1 \(inputCurrencyCode) = \(formatRate(rate)) \(baseCurrencyCode)")
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        } else if viewModel.rateFetchFailed {
                            Text("無法取得匯率")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    if !viewModel.isFetchingRate, viewModel.lockedRate != nil {
                        Text("以建立當下牌價鎖定（exchangerate-api.com）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let converted = viewModel.convertedTotal {
                        HStack {
                            Text("換算後")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(converted, format: .currency(code: baseCurrencyCode))
                                .font(.callout.bold())
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                Picker("誰先付", selection: $viewModel.selectedPayer) {
                    Text("選擇付款人").tag(nil as Member?)
                    ForEach(viewModel.members) { member in
                        Text(member.name).tag(member as Member?)
                    }
                }
            }

            // MARK: - Date
            Section {
                Toggle("加上日期", isOn: $viewModel.hasDate)
                if viewModel.hasDate {
                    DatePicker("日期", selection: $viewModel.date, displayedComponents: .date)
                }
            }

            // MARK: - Note
            Section("備註") {
                TextField("選填備註", text: $viewModel.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            // MARK: - Split Mode
            Section {
                Toggle("平均分帳", isOn: $viewModel.isEvenSplit)
            } header: {
                Text("分帳方式")
            } footer: {
                if viewModel.isEvenSplit, let amount = viewModel.evenSplitAmount {
                    Text("每人 \(amount, format: .currency(code: inputCurrencyCode))")
                }
            }

            // MARK: - Split Members
            Section("分帳成員") {
                ForEach(viewModel.members) { member in
                    HStack {
                        Button {
                            viewModel.toggleMember(member)
                        } label: {
                            HStack {
                                Image(systemName: viewModel.selectedMemberIDs.contains(member.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedMemberIDs.contains(member.id)
                                                     ? .blue : .gray)
                                Text(member.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !viewModel.isEvenSplit && viewModel.selectedMemberIDs.contains(member.id) {
                            TextField("金額", text: Binding(
                                get: { viewModel.customAmounts[member.id] ?? "" },
                                set: { viewModel.customAmounts[member.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        }
                    }
                }

                if !viewModel.isEvenSplit {
                    HStack {
                        Text("分帳合計")
                        Spacer()
                        let sum = viewModel.customAmountsSum
                        let total = viewModel.totalAmount ?? 0
                        let sumColor: Color = sum == total ? .green
                            : viewModel.hasAnyCustomInput ? .red : .secondary
                        Text(sum, format: .currency(code: inputCurrencyCode))
                            .foregroundStyle(sumColor)
                        Text("/ \(total, format: .currency(code: inputCurrencyCode))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "編輯花費" : "新增花費")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCurrencyPicker) {
            CurrencyPickerView(selection: Binding(
                get: { viewModel.selectedCurrencyCode },
                set: { newCode in
                    viewModel.selectedCurrencyCode = newCode
                    viewModel.lockedRate = nil
                    viewModel.rateFetchFailed = false
                    Task { await viewModel.refreshExchangeRate() }
                }
            ))
        }
        .task {
            // 編輯既有外幣花費也補抓最新 5 日低（不會覆蓋已存在的鎖定值，但首次進入空值時會帶）
            if viewModel.isForeign && viewModel.lockedRate == nil {
                await viewModel.refreshExchangeRate()
            }
        }
        .alert("儲存失敗", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    if let error = viewModel.save(modelContext: modelContext) {
                        saveError = error
                    } else {
                        dismiss()
                    }
                }
                .disabled(!viewModel.isValid)
            }
        }
    }

    private func formatRate(_ rate: Decimal) -> String {
        var rounded = Decimal()
        var mutable = rate
        NSDecimalRound(&rounded, &mutable, 6, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
