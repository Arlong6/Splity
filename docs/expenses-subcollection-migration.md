# Expenses 子集合化遷移藍圖（併發資料遺失根治）

狀態：設計完成、實作中（branch `refactor/expenses-subcollection`）
策略：**雙寫過渡**（使用者拍板，非 force-update 硬切）

## 問題
線上 `groups/{id}` 是單一文件，`expenses` / `members` 是陣列欄位。
- iOS `pushChanges` → `setData(整份 group)` 全覆寫
- Web `writeGroupExpenses` → `updateDoc({ expenses })` 整陣列覆寫
→ 併發編輯時後寫者整批蓋掉前者 = lost update。

## 關鍵洞察
單純改子集合**不夠**。`pushChanges(for: group)` 每次推「全部花費」；兩台同時各推全套，
仍會用過時版本互蓋。**根治 = granular push：只推這次真正改動的那一筆**（搭配 Firestore
單文件 last-write-wins，不同花費的併發即互不干擾）。

## 目標 schema
```
groups/{id}                         # 群組 meta + members（沿用）+ 保留 expenses[] 陣列（給舊版讀）
groups/{id}/expenses/{expenseId}    # ★新：每筆花費一份文件，欄位同陣列元素（id/title/totalAmount(str)/
                                    #   payerId/createdAt/isDeleted/date?/note?/deletedAt?/
                                    #   originalCurrencyCode?/originalAmount?(str)/exchangeRate?(str)/splits[]）
groups/{id}/activities/{id}         # 沿用
inviteCodes/{code}                  # 沿用
```
不需新增 model 欄位：新↔新同一筆衝突由 Firestore 單文件 last-write-wins 解決；
不同筆由 granular push 解決；陣列僅作舊版「最佳努力」鏡像。

## 寫入（雙寫）
- `serializeExpense(_:) -> [String:Any]`：從 `serializeGroup` 抽出單筆序列化（復用）。
- `pushExpense(_ expense, in group)`（granular，主要路徑）：
  1. `setData(serializeExpense(expense))` 到 `groups/{id}/expenses/{expense.id}`（merge:false）
  2. 鏡像到舊陣列：對 group 文件 `runTransaction` 讀 expenses[]、以 id 取代/插入該筆、寫回
     （讓舊版仍看得到新版的編輯；transaction 確保不誤刪其他筆）
- `pushChanges(for group)`（bulk，僅初次分享 / 換基準幣等「全部都變」時用）：
  WriteBatch 寫 group meta+members+完整陣列 + 每筆 expense 子文件。
- 軟刪除沿用（`isDeleted=true` 寫回該筆子文件 + 陣列），不做 `deleteDoc`。

## 讀取（雙讀 + 惰性遷移）
- 監聽：在 group 文件 listener 之外，**新增** `groups/{id}/expenses` 子集合 listener。
  - merge 拆成 `mergeGroupMeta`(name/isSettled/baseCurrency/members) ← group 文件
    與 `mergeExpenses` ← 子集合文件。
- Fallback：群組若**無子集合文件**（舊群組/未遷移），才用 group 文件的 `expenses[]` 陣列。
- 惰性遷移 backfill：首次對某共享群組讀取時，若子集合為空但陣列有資料，
  把每筆陣列花費寫進子集合（doc id = expense.id，冪等可重入）。

## members / claim
members 留在 group 文件（變動少）。`claimMember` 改 `runTransaction` 原子更新該成員，
取代 `pushChanges` 全覆寫，避免併發 claim 互蓋。

## firestore.rules（沿用 App Check 路線）
```
match /groups/{groupId}/expenses/{expenseId} {
  allow read: if request.auth != null;
  allow create, update: if request.auth != null;
  allow delete: if false;   // 軟刪除，不從 client 硬刪
}
```

## 呼叫端改動
- `ExpenseEditViewModel.save` → `pushExpense(savedExpense, in: group)`（取代 pushChanges）
- `GroupDetailView` 刪除/還原 → `pushExpense`（帶 archived）
- `HistoryView` 還原 → 同上（順帶修「還原不同步」的既有 MEDIUM）
- `ChangeBaseCurrencyView` → 維持 bulk `pushChanges`（全部花費都變）
- `claimMember` → transactional member 更新

## Web 對應（注意：此版 Next.js 有破壞性改動，動工前讀 node_modules/next/dist/docs/）
- `lib/push.ts`：新增 `writeExpense`（setDoc 子文件 + transaction 鏡像陣列）；`writeGroupExpenses` 淘汰
- `lib/useGroup.ts`：除 group 文件外，`onSnapshot` 訂閱 `expenses` 子集合並合併
- `lib/types.ts`：標註 expenses 改子集合（保留陣列型別作 legacy）
- 頁面 `expense/new`、`expense/[id]`：存檔走 `writeExpense`

## 已知限制（雙寫策略內在、使用者已知並選擇）
**舊版 client 對「既有花費」的編輯，可能不會傳到新版 client**：舊版只更新陣列、不碰子集合，
而新版以子集合為權威；陣列元素無版本戳，新版無法可靠判定舊版的編輯較新。
- 不同筆 / 新增：可被新版接住（陣列有、子集合無 → merge 進來）
- 新版的編輯：透過鏡像寫回陣列，舊版讀得到
- 緩解：靠已修好的更新提示促使使用者升級，縮短舊↔新並存窗口；舊版淘汰後移除陣列鏡像

## 測試 / 驗證
- 既有 23 單元測試需維持綠（純邏輯不受影響）。
- FirebaseSharingManager 難做單元測試（需 Firebase）；以「build 成功 + 模擬器手動啟動冒煙」為守門。
- 手動情境：A/B 兩裝置同時各加不同花費 → 兩筆都在；同時改同一筆 → last-write-wins 不丟其他筆；
  舊版加花費 → 新版看得到；換基準幣 → 全部正確。
- 回滾：分支獨立；陣列保留，未啟用子集合讀取前線上資料不受影響。
```
