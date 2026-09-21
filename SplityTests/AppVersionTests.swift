import Testing
@testable import Splity

struct AppVersionTests {

    @Test("正常情況：版號與 build 號都在")
    func bothPresent() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "18"]
        #expect(AppVersion.short(info: info) == "1.8.2")
        #expect(AppVersion.build(info: info) == "18")
        #expect(AppVersion.display(info: info) == "Splity 1.8.2 (18)")
    }

    @Test("缺 build 號：省略括號那段，不要顯示空括號")
    func missingBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.8.2"]
        #expect(AppVersion.build(info: info) == nil)
        #expect(AppVersion.display(info: info) == "Splity 1.8.2")
    }

    @Test("build 號是空字串：與缺少時一樣處理")
    func emptyBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.8.2", "CFBundleVersion": ""]
        #expect(AppVersion.display(info: info) == "Splity 1.8.2")
    }

    @Test("完全讀不到：版號回 0，與既有 ReviewPrompt / AppUpdateChecker 的 fallback 一致")
    func nothingPresent() {
        #expect(AppVersion.short(info: nil) == "0")
        #expect(AppVersion.build(info: nil) == nil)
        #expect(AppVersion.display(info: nil) == "Splity 0")
    }

    @Test("型別不對時不要崩，走 fallback")
    func wrongTypes() {
        let info: [String: Any] = ["CFBundleShortVersionString": 182, "CFBundleVersion": ["18"]]
        #expect(AppVersion.short(info: info) == "0")
        #expect(AppVersion.build(info: info) == nil)
    }

    @Test("真實 app bundle 讀得到版號（預設參數確實接到 Bundle.main）")
    func realBundle() {
        // 這條刻意不寫死 1.8.2：版號會隨每次發版變動，寫死等於每次改版都要改測試。
        let version = AppVersion.short()
        #expect(version != "0", "讀不到 CFBundleShortVersionString")
        #expect(version.first?.isNumber == true, "版號應以數字開頭，實際：\(version)")
        #expect(AppVersion.display().hasPrefix("Splity "))
    }
}
