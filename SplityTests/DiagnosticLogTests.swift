import Testing
import Foundation
@testable import Splity

@Suite("問題回報的本機操作紀錄")
struct DiagnosticLogTests {

    private func makeLog(maxEntries: Int = 200) -> DiagnosticLog {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "diag-\(UUID().uuidString).json")
        return DiagnosticLog(fileURL: url, maxEntries: maxEntries)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("超過上限只留最新的幾筆")
    func keepsNewestWithinLimit() {
        let log = makeLog(maxEntries: 3)
        for i in 1...5 { log.record("事件\(i)", at: t0.addingTimeInterval(Double(i))) }
        #expect(log.entries(now: t0.addingTimeInterval(10)).map(\.message) == ["事件3", "事件4", "事件5"])
    }

    @Test("超過 7 天的紀錄不再出現")
    func dropsEntriesOlderThanSevenDays() {
        let log = makeLog()
        log.record("舊的", at: t0)
        log.record("新的", at: t0.addingTimeInterval(6 * 24 * 3600))
        let now = t0.addingTimeInterval(7 * 24 * 3600 + 60)
        #expect(log.entries(now: now).map(\.message) == ["新的"])
    }

    @Test("寫進檔案，換一個實例（例如 App 重開）讀得回來")
    func persistsAcrossInstances() {
        let first = makeLog()
        first.record("開啟新增花費", at: t0)
        let second = DiagnosticLog(fileURL: first.fileURL)
        #expect(second.entries(now: t0).map(\.message) == ["開啟新增花費"])
    }

    @Test("信末區塊：標題＋每行時間與事件；沒有紀錄就是空字串")
    func reportSectionFormat() {
        let log = makeLog()
        #expect(log.reportSection(now: t0).isEmpty)
        log.record("匯率取得失敗（NZD → TWD）：逾時", at: t0)
        let text = log.reportSection(now: t0, timeZone: TimeZone(identifier: "Asia/Taipei")!)
        #expect(text == "最近操作紀錄：\n01/15 16:00:00 匯率取得失敗（NZD → TWD）：逾時")
    }

    @Test("檔案壞掉時當作沒有紀錄，不會讓 App 出錯")
    func corruptFileIsIgnored() throws {
        let log = makeLog()
        try Data("not json".utf8).write(to: log.fileURL)
        #expect(log.entries(now: t0).isEmpty)
        log.record("之後照常記錄", at: t0)
        #expect(log.entries(now: t0).count == 1)
    }
}
