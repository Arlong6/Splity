import Testing
import SwiftData
import Foundation
@testable import Splity

// MARK: - 檔名消毒（CSV 匯出）

struct FilenameSanitizingTests {

    @Test("斜線不會變成巢狀路徑")
    func slashBecomesUnderscore() {
        #expect("3/1 聚餐".sanitizedAsFilename == "3_1 聚餐")
    }

    @Test("冒號、反斜線與其他保留字元一併換掉")
    func otherReservedCharacters() {
        #expect("a:b\\c*d?e\"f<g>h|i".sanitizedAsFilename == "a_b_c_d_e_f_g_h_i")
    }

    @Test("換行與控制字元換掉")
    func controlCharacters() {
        #expect("晚餐\n第二攤".sanitizedAsFilename == "晚餐_第二攤")
    }

    @Test("空字串與純空白退回預設名稱")
    func emptyFallsBack() {
        #expect(!"".sanitizedAsFilename.isEmpty)
        #expect(!"   ".sanitizedAsFilename.isEmpty)
        #expect(!"///".sanitizedAsFilename.isEmpty)
    }

    @Test("開頭的點被去掉，不會變成隱藏檔")
    func leadingDotsRemoved() {
        #expect("..晚餐".sanitizedAsFilename == "晚餐")
    }

    @Test("過長的名稱被截短")
    func longNameTruncated() {
        let long = String(repeating: "餐", count: 200)
        #expect(long.sanitizedAsFilename.count <= 60)
    }

    @Test("正常名稱原封不動")
    func normalNameUnchanged() {
        #expect("沖繩旅遊".sanitizedAsFilename == "沖繩旅遊")
    }
}

// MARK: - 外幣自訂分帳還原

struct ForeignSplitRestoreTests {

    /// TWD 帳本、USD 21 元自訂 10.5 / 10.5、匯率 31.623 → 存成 333 / 333 TWD。
    /// 單純除回匯率會得到 10.5303… 兩筆加總 21.0606 ≠ 21，
    /// isValid 的 customAmountsSum == total 永遠不成立 → 儲存鈕鎖死、無法重新編輯。
    @Test("還原後加總精確等於原始外幣總額")
    func restoredSplitsSumToOriginalTotal() {
        let a = UUID(), b = UUID()
        let rate = Decimal(string: "31.623")!
        let restored = ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [(id: a, amount: 333), (id: b, amount: 333)],
            rate: rate,
            originalTotal: 21,
            currencyCode: "USD"
        )
        let sum = restored.values.reduce(Decimal(0), +)
        #expect(sum == 21)
        #expect(restored.count == 2)
    }

    @Test("殘值補在金額最大的那一筆")
    func residualGoesToLargestSplit() {
        let small = UUID(), large = UUID()
        let restored = ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [(id: small, amount: 100), (id: large, amount: 900)],
            rate: 10,
            originalTotal: 101,
            currencyCode: "USD"
        )
        #expect(restored[small] == 10)
        #expect(restored[large] == 91)   // 90 + 殘值 1
        #expect(restored.values.reduce(Decimal(0), +) == 101)
    }

    @Test("整除時不動任何一筆")
    func exactDivisionUnchanged() {
        let a = UUID(), b = UUID()
        let restored = ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [(id: a, amount: 300), (id: b, amount: 300)],
            rate: 30,
            originalTotal: 20,
            currencyCode: "USD"
        )
        #expect(restored[a] == 10)
        #expect(restored[b] == 10)
    }

    @Test("匯率為 0 或沒有拆帳時回傳空字典，不會除以零")
    func guardsAgainstBadInput() {
        #expect(ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [(id: UUID(), amount: 100)], rate: 0, originalTotal: 10, currencyCode: "USD"
        ).isEmpty)
        #expect(ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [], rate: 30, originalTotal: 10, currencyCode: "USD"
        ).isEmpty)
    }

    @Test("0 位小數幣別（JPY）同樣對齊總額")
    func zeroDecimalCurrency() {
        let a = UUID(), b = UUID(), c = UUID()
        let restored = ExpenseEditViewModel.restoreForeignSplits(
            baseAmounts: [(id: a, amount: 334), (id: b, amount: 333), (id: c, amount: 333)],
            rate: Decimal(string: "0.21")!,
            originalTotal: 4762,
            currencyCode: "JPY"
        )
        #expect(restored.values.reduce(Decimal(0), +) == 4762)
        #expect(restored.values.allSatisfy { $0 == Decimal.round($0, in: "JPY") })
    }
}

// MARK: - Store 救援

struct StoreRescueTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "StoreRescueTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("候選路徑包含 App Group 容器，而不只是 Application Support")
    func candidatesIncludeAppGroup() {
        let candidates = StoreRescue.candidateURLs(defaults: makeDefaults())
        #expect(!candidates.isEmpty)
        // 沒有 app group 容器的環境（例如某些測試 runner）至少要有 Application Support 候選
        #expect(candidates.contains { $0.lastPathComponent == "default.store" })
    }

    @Test("記錄過實際路徑後，該路徑排在最前面")
    func recordedURLTakesPriority() {
        let defaults = makeDefaults()
        let recorded = URL(fileURLWithPath: "/tmp/recorded-\(UUID().uuidString)/default.store")
        StoreRescue.recordStoreURL(recorded, defaults: defaults)
        #expect(StoreRescue.candidateURLs(defaults: defaults).first == recorded)
    }

    @Test("候選路徑不重複")
    func candidatesAreDeduplicated() {
        let defaults = makeDefaults()
        let appSupport = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        StoreRescue.recordStoreURL(appSupport, defaults: defaults)
        let paths = StoreRescue.candidateURLs(defaults: defaults).map(\.path)
        #expect(paths.count == Set(paths).count)
    }

    @Test("備份把 store 與 WAL 整組搬走")
    func backupMovesWholeGroup() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rescue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = dir.appendingPathComponent("default.store")
        for suffix in StoreRescue.suffixes {
            try Data("x".utf8).write(to: URL(fileURLWithPath: store.path + suffix))
        }

        let prefix = StoreRescue.backupStore(at: store, stamp: 12345)
        #expect(prefix != nil)
        for suffix in StoreRescue.suffixes {
            #expect(!FileManager.default.fileExists(atPath: store.path + suffix))
            #expect(FileManager.default.fileExists(atPath: store.path + suffix + ".corrupt-12345.bak"))
        }
    }

    @Test("沒有檔案可搬時回傳 nil，不會誤報成功")
    func backupWithNothingToMove() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("absent-\(UUID().uuidString)/default.store")
        #expect(StoreRescue.backupStore(at: missing) == nil)
    }

    @Test("救援旗標取出後即清除，提示只跳一次")
    func rescueFlagIsConsumedOnce() {
        let defaults = makeDefaults()
        #expect(StoreRescue.consumeRescueFlag(defaults: defaults) == false)
        StoreRescue.markRescued(defaults: defaults)
        #expect(StoreRescue.consumeRescueFlag(defaults: defaults) == true)
        #expect(StoreRescue.consumeRescueFlag(defaults: defaults) == false)
    }
}
