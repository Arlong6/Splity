# 產品連結與網域

狀態：1.8.2 送審前拍板（2026-09-19）
決定：**暫不買自有網域**，邀請連結繼續用 `https://splity-web-ten.vercel.app`

## 背景

邀請分享訊息裡有一條網頁版連結，讓沒有 iPhone 的朋友也能加入帳本（`Splity/Utils/SplityLinks.swift`）。
這個網址是 Vercel 依專案名自動配的 —— `-ten` 後綴就是 `splity-web.vercel.app` 被別人註冊掉之後
自動加上的，不是自有網域。

## 硬性約束：這個 Vercel 專案不可動

| | |
|---|---|
| 專案名 | `splity-web` |
| projectId | `prj_qUbRReFtD3G4ACAgcF3QIix5pYTr` |
| team | `team_VYNmlTONllBJtpWs8Fzjhb5v`（arlongs-projects） |

**不可改名、不可刪除重建、不可轉移 team。** 任何一項都會讓 `splity-web-ten.vercel.app` 換成別的字串，後果是：

1. 所有已經寄出、躺在別人 LINE 對話裡的邀請連結全部變成死連結；
2. 所有已安裝的 App 版本會**繼續產出**死連結 —— 網址是編譯進 binary 的常數，App 端沒有 remote config，
   只能再送審一版才修得掉，而 iOS 使用者更新有長尾。

## 為什麼這一版接受這個風險

風險的觸發條件只有「我們自己動了那個 Vercel 專案」，那是可控的；而買網域、換 `SITE_URL`、
重新部署、重新送審這串動作會擋住 1.8.2。權衡之下先送審，網域列為後續項目。

評估過但沒採用的中間方案：把 base URL 改成從 Firestore 讀、fallback 到現有字串。否決的理由是
成本與收益不成比例 —— 專案零 remote config 基礎建設，要新增一個公開可讀的 collection、改
`firestore.rules`（目前沒有任何公開可讀的 collection）、處理 App Check，而這一切只是為了讓一個
「租來的地址」可以換，沒有解決根本問題。

## 未來買網域時要連帶做的事

買網域的真正價值不只是耐久性，而是它同時解鎖 universal link —— iPhone 使用者點邀請連結
可以直接開 App，而不是落到網頁版。那才是邀請漏斗真正該有的樣子。

目前三個前置條件**一個都沒有**：

- `Splity/Splity.entitlements` 沒有 `com.apple.developer.associated-domains`
- web 端沒有 `public/.well-known/apple-app-site-association`（線上實測回 404）
- 全 Swift 原始碼沒有 `onOpenURL`，即使 universal link 進來也沒人接

換網域時要改的地方（全 repo 硬寫網址只有這幾處）：

- `Splity/Utils/SplityLinks.swift` — `webJoin(code:)`
- `web/src/lib/site.ts` — `SITE_URL`

`CurrencyService`（`open.er-api.com`）與 `AppUpdateChecker`（`itunes.apple.com`）也有硬寫網址，
但那是第三方與 Apple 的，不在這件事的範圍內。

候選網域與報價（2026-09-19 查，Vercel 報價，USD/年）：`splity.cc` 15、`getsplity.com` 11.25。
`splity.app` / `.com` / `.io` / `.co` 都已被註冊。`splity.tw` 尚可註冊，但 Vercel 不販售 .tw，
要另找台灣註冊商。
