import Testing
import Foundation
@testable import Splity

struct SupportMailTests {

    private let diagnostics = SupportMail.Diagnostics(
        version: "1.8.2", build: "18", device: "iPhone17,1", systemVersion: "18.5", language: "zh-Hant"
    )

    @Test("收件人是支援信箱")
    func recipient() throws {
        let url = try #require(SupportMail.url(body: "使用者寫的內容", diagnostics: diagnostics))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "mailto")
        #expect(parts.path == SupportMail.address)
    }

    @Test("主旨帶版本，讓收信時一眼看得出是哪一版")
    func subjectCarriesVersion() throws {
        let url = try #require(SupportMail.url(body: "x", diagnostics: diagnostics))
        let subject = try #require(queryValue(url, "subject"))
        #expect(subject.contains("1.8.2"))
        #expect(subject.contains("18"))
    }

    @Test("內文含完整診斷資訊，不必再回信問")
    func bodyCarriesDiagnostics() throws {
        let url = try #require(SupportMail.url(body: "按結算就閃退", diagnostics: diagnostics))
        let body = try #require(queryValue(url, "body"))
        #expect(body.contains("按結算就閃退"))
        #expect(body.contains("1.8.2 (18)"))
        #expect(body.contains("iPhone17,1"))
        #expect(body.contains("18.5"))
        #expect(body.contains("zh-Hant"))
    }

    @Test("缺 build 號時只放版號，不要留空括號")
    func missingBuild() throws {
        let d = SupportMail.Diagnostics(
            version: "1.8.2", build: nil, device: "iPhone17,1", systemVersion: "18.5", language: "en"
        )
        let url = try #require(SupportMail.url(body: "x", diagnostics: d))
        let body = try #require(queryValue(url, "body"))
        #expect(body.contains("1.8.2"))
        #expect(!body.contains("()"))
    }

    @Test("換行與 & # 等字元要正確編碼，不能把 URL 切斷")
    func escapesSpecialCharacters() throws {
        let messy = "第一行\n第二行 & 第三行 #hashtag ?query"
        let url = try #require(SupportMail.url(body: messy, diagnostics: diagnostics))
        let body = try #require(queryValue(url, "body"))
        // 解碼之後要一字不差，代表中途沒有被 & 或 # 截斷
        #expect(body.contains(messy))
        #expect(url.absoluteString.contains("%0A"), "換行應該被編碼成 %0A")
    }

    @Test("使用者還沒打字時仍然給得出可用的信")
    func emptyBody() throws {
        let url = try #require(SupportMail.url(body: "", diagnostics: diagnostics))
        let body = try #require(queryValue(url, "body"))
        #expect(body.contains("1.8.2 (18)"))
    }

    /// mailto 的 query 由 URLComponents 解析，值本身已經解過碼。
    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
