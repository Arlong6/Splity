# 花費分類與旅程統計 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每筆花費可選填分類（新增時依品項名稱自動猜），列表顯示圖示，帳本有大家合計的分類統計圓餅圖與「分類不合用？告訴我們」回報信。

**Architecture:** `Expense` 加選填字串欄位 `category`（存代碼）。分類清單、關鍵字猜測、統計加總都是可單元測試的純邏輯；沒存分類的舊花費只在顯示時猜，不寫回。同步時一律寫 `category`（沒值寫 `NSNull()`），讓「改回未分類」也能同步。

**Tech Stack:** Swift / SwiftUI / SwiftData、Swift Charts（`SectorMark`）、Firebase Firestore、Swift Testing；網頁版 Next.js（獨立 git repo `Splity/web`）。

**Spec:** `docs/superpowers/specs/2026-11-25-expense-categories-design.md`

## Global Constraints

- 在 iOS repo 開分支 `feat/expense-categories` 開發（先把 spec 與本計畫 commit 在這個分支上）；不直接 commit 到 main。
- 最低 iOS 18.0；不引入第三方套件。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`：純邏輯型別標 `nonisolated`（比照現有 `nonisolated enum`）。
- 不加 VersionedSchema / SchemaMigrationPlan；新欄位用 `var category: String? = nil`（輕量遷移）。
- 介面字串走 `Localizable.xcstrings`，中英文都要有；View 以外取字串用 `localized(...)`（`Utils/AppLanguage.swift`），禁用 `String(localized:)`。
- 分類代碼固定：`food` `transport` `lodging` `fun` `shopping` `daily` `other`；中文名：餐飲、交通、住宿、門票娛樂、購物、日用品、其他；英文名：Food & Drink、Transport、Lodging、Tickets & Fun、Shopping、Daily Needs、Other。沒分類顯示「未分類」/ "Uncategorized"。
- 不改 Firestore 安全規則、不做回填遷移、不把花費內容傳到外部服務。
- 跑 xcodebuild / 模擬器前一定要先向 game-maker-e3 要時段，等它回「Splity 可以跑了」；整台電腦只開一台模擬器；`xcodebuild test` 一律加 `-parallel-testing-enabled NO`；開始與結束各在 `/Volumes/ToyRobotDev/mac-schedule.md` 寫一行；跑完 erase 模擬器並回報「Splity 完成」。
- 測試指令範本（以下簡稱 `RUN_TESTS <target>`）：
  `cd /Users/arlong/Projects/splity_money_app/Splity/Splity && xcodebuild test -scheme Splity -parallel-testing-enabled NO -destination 'id=846CD1FD-413E-4C0A-8F47-20EAA93A38D9' -only-testing:<target>`
  為了少排時段，Task 1–5 的程式可以先全部寫好再一次跑（每個 task 的「先失敗」可用編譯錯誤或一次跑確認）；每個 task 仍各自 commit。

## Review Focus

1. 未來版本新增的分類代碼（例如 `"pets"`）被這一版讀到：顯示成「其他」，但編輯其他欄位存檔後雲端仍是 `"pets"`。→ Task 2 測試 `unknownCodeSurvivesSave`。
2. 品項名稱大小寫、前後空白、中英混寫（`"  UBER to hotel "`）：要照常猜，且多重命中取最長關鍵字。→ Task 1 測試 `normalizesAndPrefersLongest`。
3. 使用者把分類改回「未分類」：雲端要變 `null`，別台讀到 `null` 要變 `nil`，不是保留舊值。→ Task 3 測試 `nilEncodesAsNull` / `decodesNullAndMissingAsNil`。
4. 帳本只有已刪除花費或金額全為 0：統計畫面不閃退、顯示空狀態，入口列不出現。→ Task 4 測試 `emptyWhenOnlyArchivedOrZero`。
5. 編輯一筆舊（`nil`）花費但沒按儲存就離開：資料仍是 `nil`。→ Task 2 測試 `prefillDoesNotWriteWithoutSave`。

---

### Task 1: 分類清單、關鍵字猜測、顯示用分類、模型欄位

**Files:**
- Create: `Splity/Splity/Models/ExpenseCategory.swift`
- Create: `Splity/Splity/Utils/CategoryGuesser.swift`
- Modify: `Splity/Splity/Models/Expense.swift`（加欄位與 `displayCategory`）
- Modify: `Splity/Splity/Localizable.xcstrings`（7 個分類名 + 「未分類」）
- Test: `Splity/SplityTests/ExpenseCategoryTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated enum ExpenseCategory: String, CaseIterable, Identifiable { case food, transport, lodging, fun, shopping, daily, other }`，`var displayName: String`（`localized`）、`var symbolName: String`（spec 表中的 SF Symbol）。`static var uncategorizedName: String`。
  - `nonisolated enum CategoryGuesser { static func guess(title: String) -> ExpenseCategory? }`
  - `Expense.category: String?`；`extension Expense { var displayCategory: ExpenseCategory? }`：`category` 為已知代碼 → 該分類；為未知代碼 → `.other`；為 `nil` → `CategoryGuesser.guess(title:)`。

- [ ] **Step 1: 寫失敗測試** `ExpenseCategoryTests`：
  - `guessesCommonTitles`：`加油`/`中油`/`停車費`/`高鐵`/`Uber`/`taxi` → `.transport`；`飯店`/`民宿`/`Airbnb`/`hotel` → `.lodging`；`晚餐`/`咖啡`/`dinner` → `.food`；`門票`/`ticket` → `.fun`；`超市` → `.daily`。
  - `returnsNilWhenUnknown`：`"asdf"`、`""` → `nil`。
  - `normalizesAndPrefersLongest`：`"  UBER to hotel "` 的結果等於「命中關鍵字中最長者」的分類（測試內寫明預期值，依你定的關鍵字表）；大寫與前後空白不影響。
  - `displayCategoryRules`：`category = "lodging"` → `.lodging`；`"pets"` → `.other`；`nil` 且 title `"晚餐"` → `.food`；`nil` 且 title `"asdf"` → `nil`。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityTests/ExpenseCategoryTests`，預期編譯失敗（型別不存在）。
- [ ] **Step 3:** 實作上述型別。關鍵字表放 `CategoryGuesser` 內的 `[(keyword: String, category: ExpenseCategory)]`，比對前 `trimmingCharacters(in: .whitespacesAndNewlines).lowercased()`，用 `contains`；多重命中取關鍵字最長者，同長取 `allCases` 順序較前者。`Expense` 加 `var category: String? = nil`（放在 `baseCurrencyCode` 之後）。xcstrings 加 8 個 key 的 en / zh-Hant。
- [ ] **Step 4:** 跑測試，預期 PASS。
- [ ] **Step 5:** Commit：`feat(category): 分類清單、關鍵字猜測與顯示用分類`

### Task 2: 記帳 ViewModel 的分類狀態與存檔

**Files:**
- Modify: `Splity/Splity/ViewModels/ExpenseEditViewModel.swift`（表單欄位區、init 編輯分支 :167 附近、`save()` 共用段 :343）
- Test: `Splity/SplityTests/ExpenseCategoryTests.swift`（新增 `ExpenseEditCategoryTests` suite；比照 `SplitModePersistenceTests` 建 container 與 group）

**Interfaces:**
- Consumes: `ExpenseCategory`、`CategoryGuesser.guess(title:)`
- Produces:
  - `var category: ExpenseCategory?`（表單目前顯示的分類，`nil`＝未分類）
  - `func userPicked(_ category: ExpenseCategory?)`：設值並停止自動猜
  - `func titleDidChange()`：自動猜仍啟用時 `category = CategoryGuesser.guess(title: title)`
  - 自動猜啟用條件：使用者沒手動選過，且（新增花費，或既有花費的 `category == nil`）
  - 既有花費 `category` 為未知代碼時：表單顯示 `.other`，存檔時若使用者沒手動選過，寫回原代碼

- [ ] **Step 1: 寫失敗測試**
  - `newExpenseGuessesFromTitle`：新增模式設 `title = "加油"` 後 `titleDidChange()` → `.transport`；改 `"晚餐"` 再呼叫 → `.food`。
  - `manualPickStopsGuessing`：`userPicked(.shopping)` 後改 title 為 `"加油"` 並 `titleDidChange()` → 仍 `.shopping`。
  - `existingCategoryNotChanged`：既有花費 `category = "lodging"`、title `"晚餐"`，init 後 `.lodging`，`titleDidChange()` 後仍 `.lodging`。
  - `nilExistingPrefillsGuess`：既有花費 `category = nil`、title `"晚餐"`，init 後 `vm.category == .food`。
  - `prefillDoesNotWriteWithoutSave`：同上但不呼叫 `save`，`expense.category == nil`。
  - `savePersistsCategory`：新增 → `save` → 存下的 Expense `category == "transport"`；`userPicked(nil)` 後存檔 → `nil`。
  - `unknownCodeSurvivesSave`：既有 `category = "pets"`，init 後 `vm.category == .other`；改金額存檔 → `expense.category == "pets"`。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityTests/ExpenseEditCategoryTests`，預期 FAIL。
- [ ] **Step 3:** 實作。存檔在共用段寫 `savedExpense.category = …`。
- [ ] **Step 4:** 跑測試 PASS；同時跑 `SplityTests/SplitModePersistenceTests`、`SplityTests/SaveBlockerTests` 確認沒壞。
- [ ] **Step 5:** Commit：`feat(category): 記帳表單的分類狀態、自動猜與存檔`

### Task 3: 同步 category 欄位

**Files:**
- Create: `Splity/Splity/Utils/ExpenseCategoryCoding.swift`
- Modify: `Splity/Splity/Utils/FirebaseSharingManager.swift`：`serializeExpense`（:1016）、`mergeExpenses` 既有花費分支（:770–820，比照 `isEvenSplit` 的比對後賦值）與新花費分支（:821–841）、`deserializeGroup`（:1082–1094）
- Test: `Splity/SplityTests/ExpenseCategoryTests.swift`（新增 `ExpenseCategoryCodingTests`）

**Interfaces:**
- Produces: `nonisolated enum ExpenseCategoryCoding { static let key = "category"; static func encode(_ code: String?) -> Any; static func decode(_ raw: Any?) -> String? }`
  - `encode`：有值回傳字串，`nil` 回傳 `NSNull()`
  - `decode`：非空字串回傳字串；`NSNull`、缺值、空字串、非字串都回傳 `nil`

- [ ] **Step 1: 寫失敗測試**
  - `nilEncodesAsNull`：`encode(nil) is NSNull`；`encode("food") as? String == "food"`。
  - `decodesNullAndMissingAsNil`：`decode(NSNull())`、`decode(nil)`、`decode("")`、`decode(3)` 都是 `nil`；`decode("pets") == "pets"`（未知代碼原樣保留）。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityTests/ExpenseCategoryCodingTests`，預期 FAIL。
- [ ] **Step 3:** 實作 coding，並在四個位置使用：`serializeExpense` **一律**寫 `eDict[ExpenseCategoryCoding.key] = ExpenseCategoryCoding.encode(expense.category)`；三個讀取點用 `decode(eData[key])`，既有花費分支值不同才賦值。
- [ ] **Step 4:** 跑測試 PASS；再跑 `SplityTests/SyncRepairTests`、`SplityTests/ExpenseMergePolicyTests` 確認沒壞。
- [ ] **Step 5:** Commit：`feat(category): 分類隨共享帳本同步，改回未分類也會同步`

### Task 4: 統計加總

**Files:**
- Create: `Splity/Splity/Utils/CategoryStats.swift`
- Test: `Splity/SplityTests/ExpenseCategoryTests.swift`（新增 `CategoryStatsTests`）

**Interfaces:**
- Consumes: `Expense.displayCategory`
- Produces:
  - `struct CategoryTotal: Identifiable { let category: ExpenseCategory?; let amount: Decimal; let percent: Int; var id: String }`（`id` 為代碼或 `"uncategorized"`）
  - `enum CategoryStats { static func totals(for expenses: [Expense]) -> [CategoryTotal]; static func grandTotal(_ totals: [CategoryTotal]) -> Decimal }`
  - 規則：排除 `archived == true`；以 `displayCategory` 歸類、加總 `totalAmount`；金額為 0 的分類不列；依金額由大到小，「未分類」（`nil`）永遠最後；`percent` 為該類 / 總額 ×100 四捨五入。

- [ ] **Step 1: 寫失敗測試**
  - `sumsAndSorts`：住宿 600、餐飲 300、交通 100 → 依序 lodging / food / transport，percent 60 / 30 / 10，`grandTotal == 1000`。
  - `uncategorizedLast`：未分類 900、餐飲 100 → 餐飲在前、未分類在後。
  - `usesGuessForNil`：`category = nil`、title `"飯店"` 的花費算進 lodging。
  - `emptyWhenOnlyArchivedOrZero`：只有已刪除花費或金額 0 → `totals` 為空、`grandTotal == 0`。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityTests/CategoryStatsTests`，預期 FAIL。
- [ ] **Step 3:** 實作。
- [ ] **Step 4:** 跑測試 PASS。
- [ ] **Step 5:** Commit：`feat(category): 分類統計加總`

### Task 5: 回報信可帶自訂標題

**Files:**
- Modify: `Splity/Splity/Utils/SupportMail.swift:60`
- Modify: `Splity/Splity/Localizable.xcstrings`（「Splity 分類建議」）
- Test: `Splity/SplityTests/SupportMailTests.swift`

**Interfaces:**
- Produces: `static func url(body: String, subject: String? = nil, diagnostics: Diagnostics = .current(), activityLog: String = DiagnosticLog.shared.reportSection()) -> URL?`；`subject == nil` 時維持現在的「Splity 問題回報 版本」。現有呼叫不改。

- [ ] **Step 1: 寫失敗測試** `customSubject`：`url(body: "", subject: "Splity 分類建議")` 解出的 `subject` query 等於 `"Splity 分類建議"`；`defaultSubjectUnchanged`：不帶 subject 時與現有測試的預期相同。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityTests/SupportMailTests`，預期 FAIL。
- [ ] **Step 3:** 實作（照現有編碼方式處理 subject，避免 `&` 斷掉 query）。
- [ ] **Step 4:** 跑測試 PASS。
- [ ] **Step 5:** Commit：`feat(support): 回報信可帶自訂標題`

### Task 6: 介面（記帳選單、列表圖示、統計畫面與入口）

**Files:**
- Modify: `Splity/Splity/Views/ExpenseEditView.swift`（「基本資訊」區品項名稱 :34 之後加一列；`.onChange` 區 :253 加 `viewModel.title` → `titleDidChange()`）
- Modify: `Splity/Splity/Views/GroupDetailView.swift`（`ExpenseRowView` :567 標題前加圖示；`expensesSection` :162 最上方加「分類統計 ›」列；`GroupDetailSheets` :626 加 `showingStats`，比照 `showingSpreadsheet`）
- Create: `Splity/Splity/Views/CategoryStatsView.swift`
- Modify: `Splity/Splity/Localizable.xcstrings`（「分類」「分類統計」「分類不合用？告訴我們」及統計畫面其他字串）

**Interfaces:**
- Consumes: Task 1 `ExpenseCategory` / `displayCategory`；Task 2 `vm.category` / `userPicked(_:)` / `titleDidChange()`；Task 4 `CategoryStats`；Task 5 `SupportMail.url(body:subject:)`
- Produces: `struct CategoryStatsView: View { let group: Group }`

- [ ] **Step 1:** 記帳畫面：一列「分類」，選項為「未分類」＋7 類（圖示＋名稱），選擇時呼叫 `userPicked(_:)`。不影響 `isValid`。
- [ ] **Step 2:** 列表：`ExpenseRowView` 標題前顯示 `displayCategory` 的圖示（`accessibilityLabel` 為分類名）；`nil` 不顯示。
- [ ] **Step 3:** 統計畫面：甜甜圈圓餅圖（`SectorMark`，`innerRadius`），中間顯示 `grandTotal`（結算幣別格式）；下方清單每列圖示、名稱、金額、`percent%`；未分類為灰色；最底部按鈕「分類不合用？告訴我們」，以 `SupportMail.url(body: "", subject: localized("Splity 分類建議"))` 開信，失敗時比照 `AboutView` :35–46、:64–68 的提示。`totals` 為空時顯示空狀態文字。
- [ ] **Step 4:** 入口列：`expensesSection` 最上方「分類統計 ›」，`CategoryStats.totals` 為空時不顯示，點了開 sheet。
- [ ] **Step 5:** 跑 `RUN_TESTS SplityUITests/SaveBlockerReasonTests`、`RUN_TESTS SplityUITests/EnglishLocaleTests`、`RUN_TESTS SplityUITests/RecentCurrenciesUITests`，預期全部 PASS。
- [ ] **Step 6:** 截圖自己看過：中文與英文介面各一張（記帳畫面、有圖示的列表、統計畫面）。確認沒有漏翻、圖示對齊、深色模式可讀。
- [ ] **Step 7:** Commit：`feat(category): 記帳分類選單、列表圖示與分類統計畫面`

### Task 7: 網頁版保留分類（獨立 repo `Splity/web`）

**Files:**
- Modify: `web/src/lib/types.ts`（`FirestoreExpense` 加 `category?: string | null;`）
- Modify: `web/src/components/ExpenseForm.tsx:233–236`（比照 date / note：`if (expense && expense.category !== undefined) newExpense.category = expense.category;`）

- [ ] **Step 1:** 修改兩個檔案。
- [ ] **Step 2:** 在 `web/` 跑 `npx tsc --noEmit` 與 `npm run lint`，預期無錯誤。
- [ ] **Step 3:** Commit（web repo）：`fix(web): 編輯花費時保留 iOS 設定的分類`。**不要** push 或部署，等 arlong 同意。

### Task 8: 全部驗證與交付

- [ ] **Step 1:** 向 game-maker-e3 要時段後，跑 `RUN_TESTS SplityTests`（全部單元測試），預期 `** TEST SUCCEEDED **`，購買類 6 項為 skipped。
- [ ] **Step 2:** 跑 `RUN_TESTS SplityUITests`（全部 UI 測試），預期 PASS；跑完 erase 模擬器、寫完成紀錄、回報「Splity 完成」。
- [ ] **Step 3:** 給 arlong 真機（TestFlight 或 Xcode 安裝）兩台共享帳本的逐步測試說明：A 新增「加油」看到自動選交通；B 看到同一圖示；A 改回未分類，B 也變；開統計看到圓餅圖與回報信入口。
- [ ] **Step 4:** 回報結果與證據（測試輸出、截圖），等 arlong 決定合併、推送、網頁版部署與送審版本。
