# 快速分帳（Quick Split）設計

日期：2026-09-06

## 目的

偶爾約出來吃飯的一次性分帳：不建群組、不同步、不共編。輸入「誰先出了多少」，
直接得到「每人應付多少」與「誰給誰多少」，並留一份本機紀錄供事後查看。

## 範圍

- 入口：帳目列表工具列新增「快速分帳」（計算機圖示），推入快速分帳頁。
- 第一層：過去的快速分帳紀錄清單（新到舊），右上加號開新的一筆；左滑刪除。
- 新增頁（sheet）：標題（預設空、儲存時以日期補）、幣別、成員列（姓名＋先出金額，預設 0）、
  即時結果（總額、每人應付、誰給誰多少）。至少兩位有名字的成員且總額大於 0 才可儲存。
- 紀錄頁：唯讀。摘要卡（總額、每人應付、人數）、成員先出清單、轉帳卡片、分享文字。
- 均分 only。不均分的情境走正式群組。
- 純本機 SwiftData；不進 Firebase、不進群組、不進現有歷史紀錄頁。

## 計算

- 每人淨額 = 先出金額 − 總額 ÷ 人數（用未進位的精確值）。
- 轉帳由與群組結算相同的 greedy 核心算出，進位規則沿用 `Decimal.round(_:in:)`
  （整數幣別無條件進位、小數幣別四捨五入），次分位殘值 guard 一併沿用。
- 顯示的「每人應付」= `Decimal.round(總額 ÷ 人數, in: 幣別)`。

## 技術

- `SettlementCalculator` 抽出泛型核心：
  `settle<ID: Hashable>(balances: [(id: ID, balance: Decimal)], currencyCode:) -> [Transfer<ID>]`
  與對應的 hub 版本。`calculateSettlements` / `calculateHubSettlements` 改為
  先算 Member 淨額再呼叫核心，行為不變，由既有測試守住。
- 新模型 `QuickSplit`：`id`、`title`、`currencyCode`、`date`、`participantsData`（JSON，
  `[QuickSplitParticipant]`，金額以字串編碼避免 Decimal 走 Double 失真）。無關聯，
  免處理 CloudKit inverse 規則。加入 `SplityApp` schema 與測試 `makeContainer`。
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
