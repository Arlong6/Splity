# 快速分帳（Quick Split）設計

日期：2026-09-06

## 目的

偶爾約出來吃飯的一次性分帳：不建群組、不同步、不共編。輸入「誰先出了多少」，
直接得到「每人應付多少」與「誰給誰多少」，並留一份本機紀錄供事後查看。

## 範圍

- 入口：帳目列表的列表列「快速分帳（不用建群組）」（除號圖示，與邀請碼列同區）
  ，另在工具列保留同圖示按鈕。
- 第一層：過去的快速分帳紀錄清單（新到舊），右上加號開新的一筆；左滑刪除。
- 新增頁（sheet）：標題（預設空、儲存時以日期補）、幣別、成員列三欄（姓名／先出／應付）、
  即時結果（總額、平均每人、誰給誰多少）。至少兩位有名字的成員、總額大於 0、且帳目結得平才可儲存。
- 紀錄頁：唯讀。摘要卡（總額、人數、平均每人）、姓名／先出／應付三欄明細、轉帳卡片、分享文字。
- 純本機 SwiftData；不進 Firebase、不進群組、不進現有歷史紀錄頁。

## 計算

「應付」是每個人實際要負擔的金額，由使用者逐列指定，留空代表自動平分。

- 留空（nil）＝平分剩下的；填 0 ＝不用付。**兩者意義不同，不可互換**
  （有人只是陪坐沒吃，應付填 0，全額由其他人平分）。
- 總額 = Σ 先出。餘額 = 總額 − Σ 已指定的應付。
- 平均每人 = `Decimal.round(餘額 ÷ 未指定人數, in: 幣別)`，套用到每個未指定的人。
- 每人淨額 = 先出 × 縮放係數 − 應付，其中縮放係數 = Σ應付 ÷ 總額，
  用來吸收進位落差，讓沒先出錢的人付的金額恰好等於畫面顯示的應付。
- 轉帳由與群組結算相同的 greedy 核心算出，次分位殘值 guard 一併沿用。

### 結不平的處理

所有人都指定了應付、但合計不等於總額時，沒有人能吸收差額，硬算出的轉帳會結不平。
此時不產生任何轉帳，畫面顯示差額提示，儲存鈕停用。只要有任何一人留空就不會發生。

已指定的應付超過總額時（平分餘額為負），照算但標紅提示，多半是打錯字。

## 技術

- `SettlementCalculator` 抽出泛型核心：
  `settle<ID: Hashable>(balances: [(id: ID, balance: Decimal)], currencyCode:) -> [Transfer<ID>]`
  與對應的 hub 版本。`calculateSettlements` / `calculateHubSettlements` 改為
  先算 Member 淨額再呼叫核心，行為不變，由既有測試守住。
- 新模型 `QuickSplit`：`id`、`title`、`currencyCode`、`date`、`participantsData`（JSON，
  `[QuickSplitParticipant]`，金額以字串編碼避免 Decimal 走 Double 失真）。無關聯，
  免處理 CloudKit inverse 規則。加入 `SplityApp` schema 與測試 `makeContainer`。
  `share` 為後加欄位，解碼用 `decodeIfPresent`，1.8.0 build 15 存下的舊紀錄仍可讀（缺欄位＝nil＝平分）。
- `QuickSplitCalculator`：純函式，輸入成員與幣別，輸出總額、每人應付、轉帳清單。
- 結算卡片抽成 `SettlementCardView(fromName:toName:amount:currencyCode:)`，
  `SettlementView` 與紀錄頁共用。

## 檔案

新增：`Models/QuickSplit.swift`、`Utils/QuickSplitCalculator.swift`、
`Views/SettlementCardView.swift`、`Views/QuickSplitListView.swift`、
`Views/QuickSplitEditView.swift`、`Views/QuickSplitResultView.swift`、
`SplityTests/QuickSplitTests.swift`

修改：`Utils/SettlementCalculator.swift`、`Views/SettlementView.swift`、
`Views/GroupListView.swift`、`SplityApp.swift`、`SplityTests/SplityTests.swift`（makeContainer）、
`Localizable.xcstrings`（新字串補英文）

## 測試

- 核心泛型函式：既有 Member 路徑測試不變；新增以 String 為 ID 的核心測試。
- QuickSplitCalculator：單一付款人、多位付款人、TWD 進位、USD 次分位殘值終止。
- QuickSplit 序列化：金額 round-trip 不失真。
- UI：模擬器實跑截圖。
