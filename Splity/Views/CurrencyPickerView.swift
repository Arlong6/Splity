import SwiftUI

/// 共用幣別選單。先列最近使用、再列常用，其餘可搜尋。
struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""
    // 開啟時讀一次就好；選完就關掉，不需要即時更新
    @State private var recentCodes = RecentCurrencies.list()

    private var filteredRecent: [String] { filter(recentCodes) }
    private var commonCodes: [String] { CurrencyService.common }
    private var otherCodes: [String] {
        CurrencyService.allSupported.filter { !commonCodes.contains($0) }.sorted()
    }

    private var filteredCommon: [String] { filter(commonCodes) }
    private var filteredOther:  [String] { filter(otherCodes) }

    private func filter(_ codes: [String]) -> [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return codes }
        return codes.filter { code in
            code.contains(q) || CurrencyService.displayName(for: code).uppercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredRecent.isEmpty {
                    Section("最近使用") {
                        ForEach(filteredRecent, id: \.self) { code in row(code) }
                    }
                }
                if !filteredCommon.isEmpty {
                    Section("常用") {
                        ForEach(filteredCommon, id: \.self) { code in row(code) }
                    }
                }
                if !filteredOther.isEmpty {
                    Section("其他") {
                        ForEach(filteredOther, id: \.self) { code in row(code) }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜尋幣別")
            .navigationTitle("選擇幣別")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    /// 點已選中的幣別不寫入：呼叫端的 setter 可能有副作用（花費表單會清掉鎖定匯率並重抓）。
    static func select(_ code: String, into selection: Binding<String>) {
        guard code != selection.wrappedValue else { return }
        selection.wrappedValue = code
    }

    private func row(_ code: String) -> some View {
        Button {
            Self.select(code, into: $selection)
            RecentCurrencies.record(code)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(CurrencyService.flag(for: code))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(code).font(.headline)
                    Text(CurrencyService.displayName(for: code))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if code == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
