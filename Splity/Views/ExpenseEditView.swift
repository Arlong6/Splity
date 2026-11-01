import SwiftUI
import SwiftData

struct ExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ExpenseEditViewModel
    @State private var saveError: String?
    @State private var showingCurrencyPicker = false
    @State private var didSave = false

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
                            Button {
                                DiagnosticLog.shared.record("按下重試匯率")
                                Task { await viewModel.refreshExchangeRate() }
                            } label: {
                                Label("無法取得匯率，點此重試", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
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
            Section {
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
                        // VoiceOver 只報「姓名, 按鈕」，聽不出有沒有被勾選；
                        // 盲用戶因此無法確認某人是否已被排除在這筆分帳之外。
                        .accessibilityLabel(member.name)
                        .accessibilityAddTraits(
                            viewModel.selectedMemberIDs.contains(member.id) ? [.isSelected] : []
                        )

                        Spacer()

                        if !viewModel.isEvenSplit && viewModel.selectedMemberIDs.contains(member.id) {
                            TextField("金額", text: Binding(
                                get: { viewModel.customAmounts[member.id] ?? "" },
                                set: { viewModel.customAmounts[member.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 80)
                            .fixedSize(horizontal: true, vertical: false)
                            // 否則 VoiceOver 會聽到 N 個一模一樣的「金額」欄位
                            .accessibilityLabel(localized("\(member.name) 分攤金額"))
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
            } header: {
                HStack {
                    Text("分帳成員")
                    Spacer()
                    Button(viewModel.allMembersSelected ? "全部取消" : "全選") {
                        viewModel.toggleSelectAll()
                    }
                    .font(.caption)
                }
            }

            // MARK: - 為什麼還不能儲存
            // 「儲存」灰掉時使用者看不出原因（曾回報「無法再增加新的花費」），在表單底部直接說明
            if let blocker = viewModel.saveBlocker {
                Section {
                    Label(blockerMessage(blocker), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("saveBlockerReason")
                }
            }

            // MARK: - 編輯資訊
            if let exp = viewModel.existingExpense {
                Section {
                    HStack {
                        Text(exp.updatedAt == nil ? "建立時間" : "最後編輯")
                        Spacer()
                        Text(exp.updatedAt ?? exp.createdAt,
                             format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    if let editor = exp.lastEditorName, !editor.isEmpty {
                        HStack {
                            Text("編輯者")
                            Spacer()
                            Text(editor).foregroundStyle(.secondary)
                        }
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
                    DiagnosticLog.shared.record("切換幣種 \(viewModel.selectedCurrencyCode) → \(newCode)")
                    viewModel.selectedCurrencyCode = newCode
                    viewModel.lockedRate = nil
                    viewModel.rateFetchFailed = false
                    Task { await viewModel.refreshExchangeRate() }
                }
            ))
        }
        .task {
            DiagnosticLog.shared.record(isEditing ? "開啟編輯花費" : "開啟新增花費")
            // 編輯既有外幣花費也補抓最新 5 日低（不會覆蓋已存在的鎖定值，但首次進入空值時會帶）
            if viewModel.isForeign && viewModel.lockedRate == nil {
                await viewModel.refreshExchangeRate()
            }
        }
        .onChange(of: viewModel.isEvenSplit) { _, even in
            DiagnosticLog.shared.record(even ? "切換為平均分帳" : "切換為自訂分帳")
        }
        .onDisappear {
            guard !didSave else { return }
            let reason = viewModel.saveBlocker.map { "（無法儲存：\($0.logDescription)）" } ?? ""
            DiagnosticLog.shared.record("沒儲存就關閉\(reason)")
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
                        DiagnosticLog.shared.record("儲存花費失敗：\(error)")
                        saveError = error
                    } else {
                        didSave = true
                        DiagnosticLog.shared.record(isEditing ? "儲存花費成功（編輯）" : "儲存花費成功（新增）")
                        dismiss()
                    }
                }
                .disabled(!viewModel.isValid)
            }
        }
    }

    private func blockerMessage(_ blocker: ExpenseEditViewModel.SaveBlocker) -> String {
        switch blocker {
        case .missingTitle: return localized("還不能儲存：請輸入品項名稱")
        case .invalidAmount: return localized("還不能儲存：請輸入大於 0 的金額")
        case .missingPayer: return localized("還不能儲存：請選擇誰先付")
        case .noMembers: return localized("還不能儲存：請至少選一位分帳成員")
        case .customSumMismatch(let diff):
            let amount = abs(diff).formatted(.currency(code: inputCurrencyCode))
            return diff > 0
                ? localized("還不能儲存：分帳合計比總額多 \(amount)")
                : localized("還不能儲存：分帳合計比總額少 \(amount)")
        case .fetchingRate: return localized("正在取得匯率…")
        case .rateUnavailable: return localized("還不能儲存：無法取得匯率，請點上方「重試」或改用結算幣別")
        }
    }

    private func formatRate(_ rate: Decimal) -> String {
        var rounded = Decimal()
        var mutable = rate
        NSDecimalRound(&rounded, &mutable, 6, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}
