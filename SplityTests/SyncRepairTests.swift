import Testing
import Foundation
@testable import Splity

@Suite("同步修補：成員合併、漏傳花費、舊陣列鏡像、金額收斂、結算幣別")
struct SyncRepairTests {

    // MARK: - M3 成員清單合併

    @Test("別台剛加、本機還沒收到的成員不會被推送洗掉")
    func keepsRemoteOnlyMember() {
        let local = [SyncRepair.MemberSnapshot(id: "A", name: "小明", claim: nil)]
        let remote: [[String: Any]] = [
            ["id": "A", "name": "小明"],
            ["id": "B", "name": "小華", "claimedByUid": "uid-b"]
        ]
        let merged = SyncRepair.mergedMembers(local: local, remote: remote, removedIDs: [])
        #expect(merged.compactMap { $0["id"] as? String } == ["A", "B"])
        #expect(merged[1]["claimedByUid"] as? String == "uid-b")
    }

    @Test("本機刪掉的成員不會因為遠端還有而被留下")
    func dropsLocallyRemovedMember() {
        let local = [SyncRepair.MemberSnapshot(id: "A", name: "小明", claim: nil)]
        let remote: [[String: Any]] = [["id": "A", "name": "小明"], ["id": "B", "name": "小華"]]
        let merged = SyncRepair.mergedMembers(local: local, remote: remote, removedIDs: ["B"])
        #expect(merged.compactMap { $0["id"] as? String } == ["A"])
    }

    @Test("本機認領優先，本機沒有就保留遠端認領；本機改名生效")
    func claimsAndNames() {
        let local = [
            SyncRepair.MemberSnapshot(id: "A", name: "小明改", claim: nil),
            SyncRepair.MemberSnapshot(id: "B", name: "小華", claim: "uid-local")
        ]
        let remote: [[String: Any]] = [
            ["id": "A", "name": "小明", "claimedByUid": "uid-a"],
            ["id": "B", "name": "小華", "claimedByUid": "uid-remote"]
        ]
        let merged = SyncRepair.mergedMembers(local: local, remote: remote, removedIDs: [])
        #expect(merged[0]["name"] as? String == "小明改")
        #expect(merged[0]["claimedByUid"] as? String == "uid-a")
        #expect(merged[1]["claimedByUid"] as? String == "uid-local")
    }

    // MARK: - H3 漏傳花費

    @Test("本機有、雲端子集合與舊陣列都沒有的花費要重傳")
    func findsUnsyncedExpenses() {
        let a = UUID(), b = UUID(), c = UUID()
        let remote: [[String: Any]] = [["id": a.uuidString], ["id": b.uuidString, "isPurged": true]]
        #expect(SyncRepair.unsyncedExpenseIDs(local: [a, b, c], remote: remote) == [c])
    }

    @Test("雲端都有就不重傳")
    func nothingUnsynced() {
        let a = UUID()
        #expect(SyncRepair.unsyncedExpenseIDs(local: [a], remote: [["id": a.uuidString]]).isEmpty)
    }

    // MARK: - M4 舊陣列鏡像

    @Test("只替換有更新的那幾筆，其他人的花費與順序不動，新的一筆附加在後")
    func replacesLegacyEntries() {
        let arr: [[String: Any]] = [
            ["id": "1", "totalAmount": "100"],
            ["id": "2", "totalAmount": "200"]
        ]
        let updated = SyncRepair.replacingLegacyExpenses(arr, with: [
            "2": ["id": "2", "totalAmount": "6000"],
            "3": ["id": "3", "totalAmount": "9"]
        ])
        #expect(updated.compactMap { $0["id"] as? String } == ["1", "2", "3"])
        #expect(updated[0]["totalAmount"] as? String == "100")
        #expect(updated[1]["totalAmount"] as? String == "6000")
    }

    // MARK: - 補建子集合時收斂長小數

    @Test("舊陣列裡的長小數補建前收斂到 rules 允許的長度")
    func normalizesLongAmounts() {
        let long = "1234.567890123456789012345678"
        let out = SyncRepair.normalizedAmounts(["id": "x", "totalAmount": long, "exchangeRate": "0.21", "title": "拉麵"])
        let total = out["totalAmount"] as? String
        #expect(total != nil && total!.count <= RemoteAmount.maxEncodedLength)
        #expect(out["exchangeRate"] as? String == "0.21")
        #expect(out["title"] as? String == "拉麵")
    }

    @Test("舊資料以數字型別存的金額改成字串")
    func normalizesNumericAmounts() {
        let out = SyncRepair.normalizedAmounts(["id": "x", "totalAmount": NSNumber(value: 150)])
        #expect(out["totalAmount"] as? String == "150")
    }

    // MARK: - M5 結算幣別不一致

    @Test("花費記的結算幣別和帳本一致或沒記錄，不換算")
    func noConversionNeeded() {
        #expect(SyncRepair.conversionSource(expenseBase: nil, originalCode: nil, groupBase: "JPY") == nil)
        #expect(SyncRepair.conversionSource(expenseBase: "JPY", originalCode: "USD", groupBase: "JPY") == nil)
    }

    @Test("本地幣花費以舊結算幣換算；外幣花費以原幣換算")
    func conversionSourceCodes() {
        #expect(SyncRepair.conversionSource(expenseBase: "TWD", originalCode: nil, groupBase: "JPY") == "TWD")
        #expect(SyncRepair.conversionSource(expenseBase: "TWD", originalCode: "USD", groupBase: "JPY") == "USD")
    }

    @Test("換幣別之後才寫到伺服器、還掛舊幣別的花費要補換算")
    func staleBaseExpenseIDs() {
        let changedAt = Date(timeIntervalSince1970: 1_000)
        // 離線時在換幣別「之前」記、連上網才上傳：寫入時間在換幣別之後 → 要換
        let offlineBefore = UUID()
        // 離線時在換幣別「之後」記 → 要換
        let offlineAfter = UUID()
        // 換幣別前就在伺服器上、換幣別那台沒換到（例如它當時沒有這筆）→ 不動，避免誤換
        let uploadedEarlier = UUID()
        // 換幣別那台已經換好（和帳本同幣別）→ 不動
        let converted = UUID()
        // 舊資料沒有幣別或沒有寫入時間 → 不動
        let noBase = UUID(), noWrittenAt = UUID()
        let ids = SyncRepair.staleBaseExpenseIDs(
            remote: [
                .init(id: offlineBefore, base: "TWD", serverWrittenAt: Date(timeIntervalSince1970: 1_200)),
                .init(id: offlineAfter, base: "TWD", serverWrittenAt: Date(timeIntervalSince1970: 1_100)),
                .init(id: uploadedEarlier, base: "TWD", serverWrittenAt: Date(timeIntervalSince1970: 900)),
                .init(id: converted, base: "JPY", serverWrittenAt: Date(timeIntervalSince1970: 1_000)),
                .init(id: noBase, base: nil, serverWrittenAt: Date(timeIntervalSince1970: 1_100)),
                .init(id: noWrittenAt, base: "TWD", serverWrittenAt: nil)
            ],
            groupBase: "JPY",
            changedAt: changedAt
        )
        #expect(ids == [offlineBefore, offlineAfter])
    }

    @Test("換兩次幣別（TWD→JPY→USD）時，停在最早幣別的花費也會被選到")
    func staleAcrossTwoChanges() {
        let id = UUID()
        let ids = SyncRepair.staleBaseExpenseIDs(
            remote: [.init(id: id, base: "TWD", serverWrittenAt: Date(timeIntervalSince1970: 2_100))],
            groupBase: "USD",
            changedAt: Date(timeIntervalSince1970: 2_000)
        )
        #expect(ids == [id])
    }
}
