import Foundation

/// 分享文字裡會出現的產品連結。集中在一處，三個分享入口（邀請、結算、快速分帳）
/// 就不會各自寫死一份、改網址時漏掉其中一個。
enum SplityLinks {
    static let appStoreID = "6760477233"

    static let appStore = "https://apps.apple.com/app/id\(appStoreID)"

    /// 網頁版的加入頁，網址直接帶邀請碼，收件人點一下就進去、不用再手動輸入 6 碼。
    /// 沒有 iPhone 的人只有這條路可走，所以邀請訊息一定要附上。
    ///
    /// ⚠️ 這個網址是 Vercel 依專案名自動配的（`-ten` 是撞名後自動加的後綴），不是自有網域，
    /// 而且它會被編譯進 binary —— 送審後改不掉。所以 Vercel 專案 `splity-web`
    /// （prj_qUbRReFtD3G4ACAgcF3QIix5pYTr）**不可改名、不可刪除重建、不可轉移 team**，
    /// 否則所有已寄出的邀請連結全部失效，而已安裝的舊版 App 會繼續產出死連結。
    /// 決策脈絡與未來換網域要連帶做的事（universal link）見 `docs/links-and-domain.md`。
    ///
    /// 邀請碼的字元集是 `ABCDEFGHJKMNPQRSTUVWXYZ23456789`（見
    /// `FirebaseSharingManager.generateCode()`），全部 URL 安全，不需要額外轉義。
    static func webJoin(code: String) -> String {
        "https://splity-web-ten.vercel.app/join/\(code)"
    }
}
