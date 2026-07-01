import SwiftUI

/// 共用幣別選單。先列常用、其餘可搜尋。
struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""

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

    private func row(_ code: String) -> some View {
        Button {
            selection = code
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
