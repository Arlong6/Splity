# Splity — 旅遊分帳 App

一款專為旅遊、聚餐等多人消費場景設計的 iOS 分帳應用，讓記帳與結算變得簡單清楚。

---

## 功能介紹

### 群組管理
- 建立多個分帳群組（例如：日本五天四夜、跨年聚餐）
- 每個群組可新增任意數量的成員
- 支援刪除成員（有關聯花費時會提示無法刪除）

### 花費紀錄
- 新增花費，記錄品項名稱、金額、付款人、日期、備註
- 支援**平均分帳**與**自訂金額**兩種分帳方式
- 花費列表依金額由大到小排序，一目瞭然
- 支援長按左滑改名、右滑刪除

### 平均分帳算法
採用「**無條件進位**」策略：
- 所有人付 `ceil(總金額 ÷ 人數)`，每人金額相同
- 多出的零頭由付款人保留，作為先行墊付的小福利
- 例：`150 ÷ 9 = 16.67`，每人付 **17 元**，付款人多收 3 元

### 結算計算
- 自動計算每位成員的淨餘額（誰欠誰、欠多少）
- 以最少交易筆數給出最佳還款方案
- 顯示綠色（被欠）/ 紅色（欠人）直覺標示

### 分帳明細表格
- 以試算表格式呈現完整分帳明細
  - **大家要付的**：每人應付金額
  - **有人先墊**：誰先付了多少
  - **總花費**：每人最終淨負擔（金黃底色、黑字）
- 同一筆花費在兩個區段使用相同底色，方便對照
- 支援雙指縮放，適應不同螢幕大小

### CSV 匯出
- 一鍵匯出 CSV 檔案，透過 ShareLink 分享或存入「檔案」
- UTF-8 BOM 編碼，Excel、Numbers 開啟中文不亂碼
- 欄位：品項、各成員應付金額、總價

---

## 技術架構

| 項目 | 說明 |
|------|------|
| 平台 | iOS 17+ |
| UI 框架 | SwiftUI |
| 資料層 | SwiftData |
| 語言 | Swift 5.9 |
| 架構 | MVVM |

---

## 專案結構

```
Splity/
├── Models/
│   ├── Group.swift          # 群組
│   ├── Member.swift         # 成員
│   ├── Expense.swift        # 花費
│   └── ExpenseSplit.swift   # 分帳項目
├── ViewModels/
│   └── ExpenseEditViewModel.swift
├── Views/
│   ├── GroupListView.swift
│   ├── GroupDetailView.swift
│   ├── ExpenseEditView.swift
│   ├── SettlementView.swift
│   └── ExpenseSpreadsheetView.swift
└── Utils/
    ├── SettlementCalculator.swift
    └── SpreadsheetExporter.swift
```

---

## 安裝方式

1. Clone 此 repo
2. 用 Xcode 16+ 開啟 `Splity/Splity.xcodeproj`
3. 選擇目標裝置或模擬器，按下 Run
