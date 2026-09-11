# 1.8.1 第二批：掃描剩餘項目

日期：2026-09-12　範圍由 arlong 核可（把 2026-09-11 計畫的「不排入本版」全部拉進來一起做）

第一批（五項 HIGH 資料完整性，commit `95138a9`）已完成。本批把剩下的做完，
與第一批合併成同一個版本發布。

---

## A. Widget 死碼移除（arlong 選定：先刪掉）

`SplityWidget/`（205 行 + entitlements）從未加進任何 build target
（`grep -c SplityWidget project.pbxproj` = 0），從來沒被編譯過。
`Utils/WidgetDataWriter.swift` 寫 JSON 並呼叫 `reloadAllTimelines()`，全部沒有作用。

移除 `SplityWidget/`、`Utils/WidgetDataWriter.swift` 及 `GroupListView` 的呼叫點。
**app group entitlement 保留**——SwiftData 的 store 就在那個容器裡，拿掉會讓既有帳本消失。

## B. 共享帳本的成員與認領（四項，2026-09-05 起列管、2026-09-07 複核仍在）

1. **`pushGroupMeta:286-296` 整包覆蓋 members**，會抹掉別人剛用 transaction 寫好的
   `claimedByUid`（第 288 行在 nil 時直接省略 key）。
   情境：B 認領成員 M；A 在收到快照前新增／刪除成員 → M 的認領消失，B 被要求重新認領。
   做法：推送成員時保留遠端既有的 `claimedByUid`，不以本地的 nil 覆蓋遠端的值。
2. **認領視窗每次進群組都跳**：`GroupDetailView:76-80` 只看 `claimedMember == nil`，
   「稍後再說」完全不持久化，連從花費編輯頁返回都會再跳一次。
   做法：以每群組的 UserDefaults 旗標記住已婉拒，提供再次認領的入口（⋯選單）。
3. **非擁有者可觸發邀請碼重生**：`createInviteCode:89-91` 在本地判定過期時自動
   `regenerateInviteCode`，沒有擁有者檢查。實害有限（無人讀取 group 的 inviteCode 欄位），
   但破壞「只有擁有者能換碼」的不變式。做法：補上擁有者檢查，非擁有者改為丟出明確錯誤。
4. **Firestore 匯入金額零驗證**：`Decimal(string:)` 收下 `-5`、`1e100`、`12abc`
   （已實測），任何成員寫入 `totalAmount: "-1e30"` 就能毒化所有裝置的結算。
   做法：加一個集中的金額解析器，拒絕負數、非有限值與超出合理上限者，
   並在 rules 對 `totalAmount` 與 split `amount` 加上格式與範圍限制。
   rules 改動用 emulator 測試；**部署到正式環境前要先問過 arlong**。

## C. 在地化（英文使用者目前會看到中文）

已量測（從編譯器產生的 `.stringsdata` 取權威清單，非憑估計）：

- **37 個 LocalizedStringKey 字面值不在 catalog 裡**。命令列 `xcodebuild` 只產生
  `.stringsdata`，不會寫回 `.xcstrings` 原始檔，所以只有用 Xcode.app 建置時加進去的
  才在裡面。這 37 個只要補 catalog 條目＋英文，不必改程式碼。
  分布：ChangeBaseCurrencyView 10、ExpenseEditView 10、GroupListView 8、
  GroupDetailView 5、CurrencyPickerView 4、ExpenseSpreadsheetView 1。
- **約 60 處純 String 字面值完全繞過 catalog**，必須改程式碼包 `String(localized:)`：
  `ActivityAction.displayText`（11）、`SharingError.errorDescription`（4）、
  CSV 表頭（12）、表格 cell builder 的欄位名、通知內容、分享文字
  （結算／快速分帳／邀請）、`CurrencyService` 錯誤（2）、
  `ExpenseEditViewModel:244`、`MemberClaimView:137`、`GroupDetailView` 的刪除錯誤訊息。

catalog 目前 167 key，全部 en + zh-Hant 已翻譯且英文值不含中文（已驗證）。

**收尾檢查**：加一個測試，把 `.stringsdata` 的 key 與 catalog 比對，
缺少或英文值仍含中文就讓測試失敗——否則同樣的漏洞會再長回來。

## D. 無障礙

- `ExpenseEditView:132-155` 分帳成員列沒有選取狀態（只換圖示），
  自訂金額欄一律叫「金額」，VoiceOver 聽到 N 個一模一樣的欄位。
  做法：加 `.isSelected` trait 與含成員名的標籤。
- `ExpenseSpreadsheetView:406-459` 整張表固定 12pt，不隨 Dynamic Type。
  做法：改用可隨字級縮放的字型。
- `SettlementCardView` 頭像與箭頭應對 VoiceOver 隱藏，整張卡片合併成一個可讀元素；
  姓名 `lineLimit(1)` 在大字級會截斷。
- 純圖示按鈕補 accessibilityLabel（語言選單、邀請分享關閉鈕、表格關閉鈕）。

## E. Onboarding 介紹快速分帳

`OnboardingView` 四頁都在講群組流程，沒提到快速分帳。加一頁或改寫其中一頁。

---

## 驗證

- 單元測試：金額解析器、認領旗標、在地化完整性檢查。
- Emulator：rules 對金額的限制、`pushGroupMeta` 不覆蓋 claimedByUid 的契約。
- UI 測試：認領視窗婉拒後不再跳。
- 英文 locale 實跑截圖，確認沒有殘留中文。
