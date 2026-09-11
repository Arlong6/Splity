# 1.8.1 資料完整性批次

日期：2026-09-11　範圍由 arlong 於 2026-09-11 核可（只做五項高風險）

主線：**資料不會不見、同步不會出錯**。五項彼此獨立，都不動 Firestore rules，
不需要兩台裝置實測（第 2 項可用模擬器＋emulator 驗證）。

來源：2026-09-07 全面掃描（4 agents）＋主 session 於 2026-09-11 逐項複核 file:line。

---

## 1. 資料救援路徑指錯位置（HIGH，會靜默丟資料）

`SplityApp.swift:70` 硬寫 `URL.applicationSupportDirectory/default.store`，
但實際的 store 在 **App Group 容器**裡（已用 `simctl get_app_container … groups` 實證：
`<AppGroup>/Library/Application Support/default.store`）——因為 `ModelConfiguration`
的 `groupContainer` 預設 `.automatic`，而 app 有 app group entitlement。

後果：容器初始化失敗時，備份改名找不到檔案 → 重試必定同樣失敗 → 靜默退回記憶體容器，
該次啟動後所有操作在關閉 app 時全部消失，且使用者完全沒有被告知。

### 做法

**不改 happy path 建立容器的方式**（改 URL 會讓既有使用者的帳本「消失」，風險不可接受）。

- 成功建立容器後，把 `container.configurations.first?.url` 記進 UserDefaults。
  下次啟動的救援路徑直接用這個已知為真的路徑。
- 還沒記錄過時（首次升級），依序探測 app group 容器與 Application Support 兩個候選位置。
- 失敗時**先原地重試一次**（吸收暫時性鎖定／I-O 錯誤），仍失敗才改名備份。
- 改名備份時 `.store` / `-wal` / `-shm` 必須一起搬；任一搬移失敗就整組還原，
  避免留下 store 與 WAL 不匹配的殘局。
- 真的走到救援就寫一個 UserDefaults 旗標，由 `GroupListView` 首次出現時跳一次提示，
  告訴使用者資料無法開啟、備份已保留。旗標看過即清除。

### 驗證
單元測試涵蓋候選路徑推導與備份群組的全有全無搬移。
救援流程用刻意寫壞的 store 檔在模擬器實跑一次。

---

## 2. 永久刪除的墓碑被覆蓋（HIGH，刪掉的花費會全員復活）

`FirebaseSharingManager.swift:219 / 236 / 273` 推送花費用整包覆蓋的 `setData`，
會把 `:309` 寫下的 `isPurged` 墓碑洗掉。

情境：A 永久刪除某筆花費；B 還沒同步到，在歷史頁按還原 → 墓碑被覆蓋 → 該筆對所有人復活。

### 做法
三處改為 `setData(merge: true)`。已確認 `serializeExpense`（`:757-783`）**不會**寫出
`isPurged`，所以墓碑在 merge 後仍然存在，讀取端（`:497`）繼續判定為已刪除。
splits 是陣列，merge 時整個取代，語意正確。

### 驗證
Firestore emulator 整合測試：寫墓碑 → 推送同一筆花費 → 重讀確認 `isPurged` 仍為 true。

---

## 3. 外幣自訂分帳無法重新編輯（HIGH，日常會踩到）

`ExpenseEditViewModel.swift:133` 還原時把已進位的基準幣金額除回匯率
（`split.amount / restoreRate`），加總必然不等於原始外幣總額；
`:82` 的 `customAmountsSum == total` 因此永遠不成立 → 儲存鈕鎖死，只能整筆重打。

### 做法（arlong 選定：還原時分配殘值，不動 schema）
還原後計算 `expense.originalAmount`（原始外幣總額，模型已有此欄位）與各還原值加總的差，
把差額加到金額最大的那一筆上，使加總精確等於原始總額。
只影響載入既有花費時顯示的數字，可能與當初輸入差一分，屬已知取捨。

### 驗證
單元測試：TWD 帳本、USD 21 元自訂 10.5 / 10.5、匯率 31.623 → 還原後加總等於 21 且 `isValid` 為真。

---

## 4. 推送與儲存失敗被吞掉（HIGH，使用者以為成功了）

`FirebaseSharingManager.swift:34`（claimMember）、`ExpenseEditViewModel.swift:272`、
`HistoryView.swift:58`、`ChangeBaseCurrencyView.swift:262` 用 `try?` 吞掉錯誤；
`HistoryView.swift:54` 等處 `try? modelContext.save()` 同樣無聲。

最嚴重的是認領：推送失敗仍在本地標記成功，下一次遠端同步把它洗掉，
使用者看到認領視窗再次跳出且毫無說明。

### 做法
改成 `do/catch` 並把錯誤接到既有的 alert 綁定上。`MemberClaimView.swift:126` 的
catch＋alert 早已接好，只要把 `try?` 換掉即可生效。

### 驗證
單元測試覆蓋錯誤傳遞路徑；UI 層以既有 alert 綁定為準，不另外寫 UI 測試。

---

## 5. CSV 檔名未消毒（HIGH，分享直接失敗且無訊息）

`ExpenseSpreadsheetView.swift:262` 用 `"\(group.name)_分帳明細.csv"` 當
`appendingPathComponent` 的參數；群組名含 `/` 會變成巢狀路徑，
`Data.write` 在 `FileRepresentation` 裡拋出，ShareLink 靜默失敗。

### 做法
把檔名中的路徑分隔字元與控制字元換成底線，並限制長度；空字串時退回預設名稱。

### 驗證
單元測試涵蓋斜線、冒號、換行、空名稱、超長名稱。

---

## 不排入本版（理由）

- **在地化整批**（約 50 處硬編中文 + 33 個缺 en 的 key）：量大但純機械、不碰邏輯，
  適合獨立一版，避免與本批的行為修正混在同一個 diff。
- **共享帳本成員與認領批次**（`pushGroupMeta` 整包蓋成員、認領視窗重複跳、
  邀請碼擁有者閘門、Firestore 金額驗證）：需要改 rules 並用兩台裝置實測，風險性質不同。
- **無障礙**（分帳成員列選取狀態、表格 Dynamic Type、卡片 VoiceOver 分組）。
- **Widget 死碼**：不在任何 build target，要先決定移除還是真的接上。
- Onboarding 尚未介紹快速分帳。
