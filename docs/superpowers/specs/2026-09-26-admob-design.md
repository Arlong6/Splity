# Splity 加入 AdMob 廣告與「移除廣告」買斷 — 設計

日期：2026-09-26　版本：1.9.0

## 目標
- 免費版顯示 Google AdMob 廣告：群組列表底部自適應橫幅、結算明細頁按「完成」時的插頁（有頻率上限）。
- 三種人不看廣告：買過「移除廣告」（StoreKit 2 非消耗型 `com.arlongchien.Splity.removeAds`）、被開發者加進 Firestore `adFree/{uid}` 名單、測試環境。
- Pro 之類的訂閱不做；共享帳本成員不連帶免廣告。

## 元件
| 檔案 | 責任 |
|---|---|
| `Splity/Utils/AdConfig.swift` | App ID / unit ID / 商品 ID。Debug 用 Google 測試 ID；Release 未換正式 ID 會有 `#warning`。 |
| `Splity/Utils/AdFreeStatus.swift` | 免廣告判定（測試環境 ∨ 已購買 ∨ 名單），快取在 UserDefaults；購買、還原、監聽交易。 |
| `Splity/Utils/InterstitialPolicy.swift` | 插頁頻率：安裝後 24h 不播、每看 3 次結算明細 1 次、間隔 ≥ 10 分鐘、UI 測試不播。 |
| `Splity/Utils/AdsManager.swift` | 啟動順序 ATT → UMP → `MobileAds.start`；插頁預載與播放；`AdBanner` SwiftUI 橫幅。 |
| `GroupListView` | `onAppear` 啟動廣告流程；List 底部 `safeAreaInset` 放 `AdBanner`。 |
| `SettlementView` | `onAppear` 記一次瀏覽；「完成」→ 插頁 → dismiss。 |
| `AboutView` | 「移除廣告」「還原購買」區塊；footer 露出匿名 uid 供加名單。 |
| `Info.plist` | `GADApplicationIdentifier`、`NSUserTrackingUsageDescription`、`SKAdNetworkItems`（50 筆）。 |
| `firestore.rules`（splity-firebase repo） | `adFree/{uid}`：本人可 get，其他一律拒絕。 |
| `web/public/app-ads.txt`、`web/src/app/privacy` | AdMob 驗證檔與新的隱私權政策頁。 |

## 決策
- 免廣告的人連 SDK 都不初始化，也不問 ATT。
- 匿名 uid 重裝會變，名單不是憑證；憑證只認 StoreKit。
- 移除 macOS / visionOS 平台（GMA 不支援，商店本來也只上 iPhone/iPad）。
- 隱私權政策從 GitHub blob 頁搬到官網 `/privacy`，內容更新不必重新送審；舊 html 只做轉址。

## 驗證
- 單元測試：`InterstitialPolicyTests`、`AdFreeStatusTests`。
- Firestore rules：`web/test/emulator/rules.test.mjs` 新增 5 個 adFree 案例。
- 真機 Debug build 走完 ATT → 橫幅 → 插頁 → StoreKit 設定檔購買 → 橫幅消失。
