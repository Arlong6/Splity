import SwiftUI
import SwiftData

/// 改群組基準幣別。會抓所有來源幣的最新匯率，預覽逐筆換算後的金額，
/// 使用者按確認才真的寫入 SwiftData + 推到 Firebase。
struct ChangeBaseCurrencyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FirebaseSharingManager.self) private var sharingManager

    let group: Group

    @State private var newBase: String
    @State private var rateMap: [String: Decimal] = [:]   // 來源幣 → newBase 的 5 日最低匯率
    @State private var failedCurrencies: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingPicker = false
    @State private var ready = false  // 已抓過匯率

    init(group: Group) {
        self.group = group
        _newBase = State(initialValue: group.baseCurrencyCode)
    }

    private var oldBase: String { group.baseCurrencyCode }
    private var willChange: Bool { newBase != oldBase }

    /// 群組裡所有需要換算來源幣的清單（去重）。
    /// 規則：外幣花費用其 originalCurrencyCode；本地幣花費用 oldBase。
    private var sourceCurrencies: [String] {
        var set = Set<String>()
        // 含已刪除(archived)花費：它們仍可被還原，不一起換算的話還原後會把
        // 舊幣種金額混進新基準幣的帳本，污染結算
        for expense in group.expenses {
            if let oc = expense.originalCurrencyCode {
                set.insert(oc)
            } else {
                set.insert(oldBase)
            }
        }
        return Array(set).sorted()
    }

    private func effectiveRate(for code: String) -> Decimal? {
        if code == newBase { return 1 }
        return rateMap[code]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("從") {
                    HStack {
                        Text(CurrencyService.flag(for: oldBase))
                        Text(oldBase)
                        Text("（\(CurrencyService.displayName(for: oldBase))）")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("改為") {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Text(CurrencyService.flag(for: newBase))
                            Text(newBase)
                            Text("（\(CurrencyService.displayName(for: newBase))）")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if willChange && ready {
                    Section {
                        ForEach(sourceCurrencies, id: \.self) { code in
                            HStack {
                                Text(CurrencyService.flag(for: code))
                                Text("1 \(code) =")
                                    .font(.callout)
                                Spacer()
                                if let rate = rateMap[code] {
                                    Text("\(formatRate(rate)) \(newBase)")
                                        .font(.callout)
                                        .monospacedDigit()
                                } else {
                                    Text("無法取得")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("匯率（當下牌價）")
                    } footer: {
                        Text("以 exchangerate-api.com 當下牌價換算，套用後鎖定。")
                            .font(.caption)
                    }

                    Section("換算預覽") {
                        ForEach(group.expenses.filter { !$0.archived }) { expense in
                            previewRow(expense)
                        }
                    }
                }
            }
            .navigationTitle("結算幣別")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !willChange {
                        // 沒改幣別就只是關掉
                        Button("完成") { dismiss() }
                    } else if !ready {
                        if isLoading {
                            ProgressView()
                        } else {
                            Button("換算") {
                                Task { await loadRates() }
                            }
                        }
                    } else {
                        Button("套用") {
                            apply()
                        }
                        .disabled(!allRatesValid())
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                CurrencyPickerView(selection: Binding(
                    get: { newBase },
                    set: { newBase = $0; ready = false; rateMap = [:]; failedCurrencies = [] }
                ))
            }
            .alert("錯誤", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ expense: Expense) -> some View {
        let sourceCode = expense.originalCurrencyCode ?? oldBase
        let originalAmount = expense.originalAmount ?? expense.totalAmount
        let rate = effectiveRate(for: sourceCode)
        let newAmount: Decimal? = rate.map { Decimal.round(originalAmount * $0, in: newBase) }
        VStack(alignment: .leading, spacing: 2) {
            Text(expense.title).font(.callout)
            HStack(spacing: 6) {
                Text(originalAmount, format: .currency(code: sourceCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let newAmount {
                    Text(newAmount, format: .currency(code: newBase))
                        .font(.caption.bold())
                        .foregroundStyle(.indigo)
                } else {
                    Text("？")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func allRatesValid() -> Bool {
        for code in sourceCurrencies {
            guard let rate = effectiveRate(for: code), rate > 0 else { return false }
        }
        return true
    }

    private func formatRate(_ rate: Decimal) -> String {
        var rounded = Decimal()
        var mutable = rate
        NSDecimalRound(&rounded, &mutable, 6, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private func loadRates() async {
        isLoading = true
        defer { isLoading = false }
        var newMap: [String: Decimal] = [:]
        var failed: Set<String> = []
        for code in sourceCurrencies {
            do {
                let rate = try await CurrencyService.shared.fetchLatestRate(from: code, to: newBase)
                newMap[code] = rate
            } catch {
                failed.insert(code)
            }
        }
        rateMap = newMap
        failedCurrencies = failed
        ready = true
    }

    private func apply() {
        guard allRatesValid() else { return }

        // 含 archived：見 sourceCurrencies 的說明（還原污染防護）
        for expense in group.expenses {
            let sourceCode = expense.originalCurrencyCode ?? oldBase
            guard let rate = effectiveRate(for: sourceCode) else { continue }
            BaseCurrencyConversion.convert(expense, from: sourceCode, rate: rate, to: newBase)
        }

        group.baseCurrencyCode = newBase

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if group.isShared {
            let sharedGroup = group
            let manager = sharingManager
            Task {
                await manager.pushInBackground {
                    try await manager.pushChanges(for: sharedGroup)
                }
                await manager.logActivity(
                    for: sharedGroup,
                    action: .editedExpense,
                    target: "結算幣別",
                    details: "\(oldBase) → \(newBase)"
                )
            }
        }

        dismiss()
    }
}
