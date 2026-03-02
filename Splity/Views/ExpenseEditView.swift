import SwiftUI
import SwiftData

struct ExpenseEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ExpenseEditViewModel

    let isEditing: Bool

    init(group: Group, expense: Expense? = nil) {
        _viewModel = State(initialValue: ExpenseEditViewModel(group: group, expense: expense))
        self.isEditing = expense != nil
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "TWD"
    }

    var body: some View {
        Form {
            // MARK: - Details
            Section("基本資訊") {
                TextField("品項名稱", text: $viewModel.title)

                HStack {
                    Text(currencyCode)
                        .foregroundStyle(.secondary)
                    TextField("金額", text: $viewModel.totalAmountString)
                        .keyboardType(.decimalPad)
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
                if viewModel.isEvenSplit, let base = viewModel.evenSplitAmount {
                    if let upper = viewModel.evenSplitUpperAmount {
                        Text("每人 \(base, format: .currency(code: currencyCode)) – \(upper, format: .currency(code: currencyCode))")
                    } else {
                        Text("每人 \(base, format: .currency(code: currencyCode))")
                    }
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
                        Text(sum, format: .currency(code: currencyCode))
                            .foregroundStyle(sumColor)
                        Text("/ \(total, format: .currency(code: currencyCode))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "編輯花費" : "新增花費")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    if viewModel.save(modelContext: modelContext) {
                        dismiss()
                    }
                }
                .disabled(!viewModel.isValid)
            }
        }
    }
}
