# Splity 1.8.2 App Store 商店頁文案（草稿，待主控審）

草稿日期：2026-09-18
狀態：**只是草稿檔，沒有任何內容被寫進 App Store Connect。** 所有欄位都要主控自己貼上去。

依據的實查事實（本次跑過）：
- `itunes.apple.com/lookup?id=6760477233&country=tw` → version 1.8.1、上架 2026-09-13(UTC)、price 0、
  primaryGenre `Social Networking`、genres `['社交','工具程式']`、languageCodes `['EN','ZH']`、
  description 全文只有「Splity 是專為朋友聚餐、旅遊、合租設計的分帳 App。」、userRatingCount 0。
- `curl -sI https://splity-web-ten.vercel.app` → 200，title「Splity｜旅行分帳」；`/join/ABC123` → 200。
  （`/privacy`、`/support` 都是 404，見第 6 節。）
- app 端功能逐項對照過原始碼，見第 7 節「誠實性查核」。

---

## 0. 字元數怎麼算（先看這段）

本文件每個欄位都標了字元數，計算方式是 **Python `len()`，也就是 Unicode 字元數（一個中文字＝1）**。

**我不確定 App Store Connect 的計數器是否 100% 相同。** 我的理解是 ASC 的輸入框計數用的是
JavaScript `.length`（UTF-16 code unit），BMP 範圍內的中文字同樣算 1，所以兩者應該一致；但
emoji 與罕用字會算 2。**請一律以 ASC 輸入框右下角的即時計數器為準**，不要以本文件的數字為準。
本文件所有中英文欄位都沒有用 emoji，風險應該不大，但副標題（上限 30）最貼邊，貼上時務必看一眼計數器。

各欄位上限（ASC）：名稱 30、副標題 30、關鍵字 100、promotionalText 170、description 4000、whatsNew 4000。

---

## 1. 繁體中文（zh-Hant，現有語系）

### 1.1 App 名稱 — 11 字元 / 30

<!-- field: ZH_NAME limit:30 -->
```
Splity｜旅行分帳
```

理由：目前名稱只有「Splity」6 字元，等於浪費了 24 字元的索引空間，而「分帳」是這個 app 最核心的
搜尋意圖字。用全形「｜」與網頁版 title 一致（網頁 title 實測就是「Splity｜旅行分帳」），品牌一致。
名稱裡放「旅行」是因為旅遊分帳的客單意圖最強、字數最省；聚餐與合租由副標題承接。

注意：這是**商店頁名稱**，不會改變使用者桌面上的 app 名稱（那是 CFBundleDisplayName，不在本次範圍）。

備案（如果主控覺得不該被「旅行」框住）— 13 字元：

```
Splity 旅遊聚餐分帳
```

### 1.2 副標題 — 19 字元 / 30

<!-- field: ZH_SUBTITLE limit:30 -->
```
聚餐旅遊合租：沒廣告、沒訂閱、不限筆數
```

理由：副標題是名稱下方唯一會出現在搜尋結果的那一行，必須同時做兩件事——補足名稱沒吃到的場景字
（聚餐、旅遊、合租），以及把唯一守得住的差異寫成**具體對照**而不是「完全免費」四個空話。
「不限筆數」是直球打在競品評論區最大的抱怨點上，但通篇沒有提到任何競品名稱（2.3.7 安全）。

備案（語氣更強、同樣 19 字元）：

```
沒廣告沒訂閱沒上限，聚餐旅遊合租都好分
```

### 1.3 關鍵字 — 91 字元 / 100

<!-- field: ZH_KEYWORDS limit:100 -->
```
記帳,帳本,均分,平分,結算,分錢,分攤,費用,帳單,代墊,旅費,團費,朋友,室友,出國,自由行,多幣別,匯率,換算,團體,出遊,出差,露營,家庭,情侶,算錢,收支,還錢,借錢,分擔
```

**先修掉現有的 bug**：目前線上的關鍵字字串開頭有兩個半形空白（`  分帳,帳本,...`），白白吃掉
2 個字元而且第一個詞會被當成「 分帳」。新字串**逗號後面一律不留空白**，這是 Apple 官方建議
（空白會被計入 100 字元且不會增加匹配）。

為什麼選這些：
- **意圖同義詞**（記帳／均分／平分／分攤／分擔／分錢／算錢／結算）：台灣人講同一件事有很多種說法，
  Apple 的中文分詞不會自動幫你補同義詞，只能自己列。
- **場景詞**（出國／自由行／出遊／出差／露營／家庭／情侶／室友／朋友／團體）：接住「日本自由行 分帳」
  這類長尾組合；Apple 會把不同關鍵字自動組合成詞組，所以不用自己寫「旅遊分帳」這種組合。
- **功能詞**（多幣別／匯率／換算／帳單／費用／旅費／團費／代墊／還錢／借錢／收支／帳本）。

為什麼捨棄：
- **分帳、旅行**：已經在名稱裡，Apple 會索引名稱，重複等於浪費字元。
- **聚餐、旅遊、合租**：已經在副標題裡，同上。
- **廣告、訂閱、筆數**：副標題已有，而且沒人會搜這些字。
- **競品名稱（Splitwise / tricount / Settle Up / Bill Bear 等）**：踩 2.3.7 紅線，會被退件。一個都不放。
- **拆帳**：台灣語境裡「拆帳」多指營收分潤，不是朋友分攤，意圖不對。
- **AA / AA制**：偏中國大陸用語，台灣使用者搜尋量低，不值得花 3～5 字元。
- **免費**：搜尋意圖很雜（會跟一堆不相干的 app 搶），且「免費」這件事靠副標題講比較有效。

### 1.4 promotionalText — 83 字元 / 170

<!-- field: ZH_PROMO limit:170 -->
```
完全免費，而且是真的免費：沒有廣告、沒有訂閱、沒有內購，記幾筆、開幾個帳本都不限。出國把當地幣別直接記下來，自動換算並鎖住匯率；結算時一次算出誰該給誰，轉帳次數最少。
```

這個欄位**隨時可改、不用送審**（見第 5 節），所以刻意留了將近一半的空間：之後想換季節性訊息
（例如連假前的「出國前先開一本」）直接改這一句就好，不用動 description。

### 1.5 description — 638 字元 / 4000

第一句是關鍵：使用者不點「更多」的話，商店頁大約只看得到前兩三行，所以第一句就把唯一守得住的
差異（完全不變現）講完，第二句才講這是什麼 app。

<!-- field: ZH_DESC limit:4000 -->
```
Splity 是完全免費的分帳 App：沒有廣告、沒有訂閱、沒有內購，記帳筆數和帳本數量都不設上限。

出去玩、聚餐、合租，誰先墊了錢、最後誰該給誰，交給 Splity 算。

【一組邀請碼，大家一起記】
建好帳本會產生 6 碼邀請碼，傳給朋友就能一起記帳，不用註冊、不用 Email、不用手機號碼。沒有 iPhone 的朋友，也可以用網頁版輸入同一組邀請碼加入。

【結算一次算完，轉帳次數最少】
Splity 會自動抵銷彼此的債務，算出最少的轉帳次數；也可以切換成「集中付給一人」，由一個人收齊再分出去。整本帳標記結清後，所有成員都看得到。

【出國記帳，匯率自動換算】
記帳時直接輸入當地幣別，Splity 依當下牌價換算成你設定的結算幣別，並把匯率鎖住，之後牌價變動不會動到已經記好的帳。日圓、韓元、泰銖、歐元等三十多種常用幣別都能用。

【偶爾的飯局，不用開帳本】
用「快速分帳」填誰先出了多少、誰該付多少，馬上算出誰給誰，算完就走，不會在列表裡留下一堆只用一次的群組。

【每一筆都交代得清楚】
表格檢視一次看完所有花費與分攤金額，可以匯出 CSV 檔自己存一份。活動紀錄會留下誰新增、修改、刪除了哪一筆，不用靠記憶對帳。

【關於免費這件事】
Splity 沒有任何變現機制，也沒有打算加。不放廣告、不賣訂閱、沒有內購，更不會做到一半跳出「免費版只能記 3 筆」。喜歡的話，推薦給朋友就是最好的支持。

介面支援繁體中文與英文。有問題或建議，歡迎從支援連結回報。
```

寫法上的取捨：
- 沒有用「不用註冊」當標題或第一句——競品商店頁自己也寫不用註冊，守不住，所以只放在段落內當事實陳述。
- 沒有用「有網頁版」當賣點——同理，只寫成「沒有 iPhone 的朋友也可以用網頁版加入」這個**使用情境**。
- 全篇沒有出現任何其他行動平台名稱（2.3.10 安全），「沒有 iPhone 的朋友」是規避這條紅線的標準寫法。
- 沒有關鍵字堆砌：每個場景詞都出現在完整句子裡，沒有出現「分帳 記帳 旅遊 聚餐 合租…」這種列表。
- 「免費版只能記 3 筆」是描述一種**業界常見做法**，沒有指名任何 app，不算貶低競品。
  如果主控覺得這句太針對性，可以直接刪掉後半句，字數不受影響。

### 1.6 whatsNew（架構，等主控補實際改動）— 目前 146 字元 / 4000

尖括號是**待填佔位符，送出前必須全部換掉或刪掉**。

<!-- field: ZH_WHATSNEW limit:4000 -->
```
這一版修了什麼：

・修正分享邀請連結的問題：<主控補上實際行為，例如「分享出去的連結在某些 App 裡點不開，現在會正確帶到加入頁面」>
・<其他修正，一行一項，用使用者看得懂的話寫，不要寫 commit message>

謝謝所有回報問題的人。有任何問題或建議，歡迎從支援連結告訴我們。
```

關於評分提示：**建議不要寫進 whatsNew。** 評分提示是 app 主動跳出來問使用者的東西，不是使用者
會期待的「新功能」，寫進更新說明反而像在預告會被打擾。如果主控堅持要寫，用這一行（放在最後）：

```
・結算完成後會問一次要不要給評分，隨時可以略過。
```

---

## 2. English（en-US，**目前不存在，需要新增語系**）

英文版不是中文版的直譯：中文版用場景開場（出去玩、聚餐、合租），英文版用「free 到底是什麼意思」
開場，因為英文區使用者對 "free" 早就免疫，必須立刻用具體條件把話講死。

### 2.1 App Name — 26 chars / 30

<!-- field: EN_NAME limit:30 -->
```
Splity: Trip Bill Splitter
```

理由：英文區「bill splitter」是最主要的搜尋詞組，「trip」把場景收在旅遊。避免用 "Expense Manager"
這種字（會跟一堆個人記帳 app 撞在一起，而且那不是這個 app 在做的事）。

### 2.2 Subtitle — 30 chars / 30（剛好貼邊）

<!-- field: EN_SUBTITLE limit:30 -->
```
Group costs, no ads, no limits
```

**剛好 30 字元，一個字都不能多。** 貼上後請確認 ASC 沒有報錯。
如果想留一點餘裕，用這個 27 字元的備案：

```
Group costs, no ads or fees
```

### 2.3 Keywords — 96 chars / 100

<!-- field: EN_KEYWORDS limit:100 -->
```
split,expense,share,settle,roommate,dinner,travel,vacation,friend,debt,IOU,currency,rent,holiday
```

- 避開名稱已有的 Trip / Bill / Splitter 與副標題已有的 Group / costs / ads / limits。
- 保留 `split`：名稱裡是 "Splitter"，我**不確定** Apple 的英文詞幹處理會不會讓 "Splitter" 自動匹配
  到 "split"。這是刻意的保險，代價是 6 個字元；如果主控確定不需要，刪掉可以換兩個新詞進來。
- 一律用單數（Apple 會自行處理單複數），逗號後不留空白。
- 刪掉了 `tally`、`ledger`：英文區搜尋量低，優先讓位給 `roommate`、`vacation`。
- 同樣一個競品名稱都沒有（2.3.7）。

### 2.4 promotionalText — 165 chars / 170

<!-- field: EN_PROMO limit:170 -->
```
Free, and actually free: no ads, no subscription, no in-app purchases, no cap on expenses or groups. Log spending in any currency, settle up in the fewest transfers.
```

### 2.5 description — 1701 chars / 4000

<!-- field: EN_DESC limit:4000 -->
```
Splity is free — no ads, no subscription, no in-app purchases, and no cap on how many expenses or groups you create.

Trips, dinners, shared apartments: Splity tracks who paid for what and tells you who owes whom at the end.

ONE INVITE CODE, EVERYONE LOGS TOGETHER
Create a ledger and you get a six-character invite code. Send it to your friends and they can add expenses too — no account, no email, no phone number. Friends without an iPhone can join with the same code from the web version.

SETTLE UP IN THE FEWEST TRANSFERS
Splity cancels out debts that point both ways and works out the smallest set of payments that clears the ledger. Want one person to handle it instead? Switch to hub mode: everyone pays a single person, who then pays everyone else. Mark the ledger settled and the whole group sees it.

TRAVEL CURRENCIES, CONVERTED AND LOCKED
Enter an expense in the local currency and Splity converts it to your settlement currency at the current rate, then locks that rate in — later swings never rewrite what you already logged. Thirty-plus common currencies, from JPY and KRW to EUR and USD.

QUICK SPLIT FOR ONE-OFF DINNERS
No group needed. Enter who paid what and who owes what, see who pays whom, done — without leaving a single-use group behind in your list.

EVERY LINE ACCOUNTED FOR
The spreadsheet view shows every expense and every share at once, and exports to CSV. The activity log records who added, edited or deleted each entry, so nobody has to go from memory.

ABOUT "FREE"
Splity has no way to make money from you, and no plan to add one. If you like it, tell a friend.

Available in English and Traditional Chinese. Questions or ideas: reach us through the support link.
```

### 2.6 whatsNew（架構）— 目前 182 chars / 4000

<!-- field: EN_WHATSNEW limit:4000 -->
```
What's fixed in this version:

• Invite link sharing: <主控補上實際行為的英文版>
• <其他修正>

Thanks to everyone who reported issues. Questions or ideas are always welcome through the support link.
```

---

## 3. 兩套文案的字數總表（方便主控直接核對）

| 欄位 | 上限 | zh-Hant | en-US |
|---|---|---|---|
| App 名稱 | 30 | 11 | 26 |
| 副標題 | 30 | 19 | **30（貼邊）** |
| 關鍵字 | 100 | 91 | 96 |
| promotionalText | 170 | 83 | 165 |
| description | 4000 | 638 | 1701 |
| whatsNew | 4000 | 146（含佔位符） | 182（含佔位符） |

---

## 4. marketingUrl 與 supportUrl

### marketingUrl（目前空白）

```
https://splity-web-ten.vercel.app
```

實測 `curl -sI` 回 200，`<title>` 是「Splity｜旅行分帳」。

⚠️ **絕對不要填 `splity-web.vercel.app`，那是別人的站。**

兩個保留意見：
1. 這個頁面是 client-side render，`curl` 抓回來的 HTML 幾乎沒有可見文字。使用者用瀏覽器開沒問題，
   但對搜尋引擎和任何抓 meta 的服務來說它是空的。不影響 App Store 審核，但行銷效果打折。
2. 網址是 Vercel 子網域。能用，只是看起來不像正式官網。要不要買網域是主控的決定，不在本次範圍。

### supportUrl（目前指向 GitHub issues）

**建議短期維持現狀，中期換掉。** GitHub issues 頁實測回 200，技術上過得了審核，但：
- 一般使用者要留言得先有 GitHub 帳號，對繁中使用者來說門檻太高，等於沒有支援管道。
- Apple 偶爾會挑剔「支援頁沒有可實際聯絡的方式」（5.1.1 / 1.5 相關），有被要求補件的風險。

建議做法是在網頁版加一頁 `/support`，內容只要：一個 email、常見問題三五條、回報格式。
做好之後 supportUrl 改成：

```
https://splity-web-ten.vercel.app/support
```

⚠️ **這一頁現在是 404，沒做好之前不要填。** 實測：
`/support` → 404、`/privacy` → 404、`/join/ABC123` → 200。

### 順帶提醒：Privacy Policy URL

這是 ASC 的必填欄位，本次沒有查它目前指向哪裡。**主控請自己確認它不是指到
`splity-web-ten.vercel.app/privacy`**——那個路徑現在是 404，隱私權政策連結壞掉是 5.1.1 的退件常客。

---

## 5. 送出前檢查清單

### 5.1 哪些欄位可以即時生效、哪些要綁版本送審

| 欄位 | 我的理解 | 信心 |
|---|---|---|
| promotionalText | **隨時可改，不送審、立刻生效** | 高 |
| description / keywords / whatsNew / 截圖 | 綁版本，必須跟著 1.8.2 一起送審 | 高 |
| App 名稱 / 副標題 | 綁版本，跟著新版本送審 | 高 |
| supportUrl / marketingUrl | **可能**可以在 app 上架狀態下直接改 | 低 — 見下 |
| Privacy Policy URL | **可能**可以直接改 | 低 — 見下 |

**低信心的部分我明說：** URL 類欄位能不能在不送新版本的情況下直接存檔，我不確定，Apple 的規則
這幾年有調整過。判斷方法很簡單——在 ASC 打開該欄位，**如果是灰色不能編輯，就是要綁版本**。

實務上這次不用糾結：1.8.2 反正要送審，把上面全部欄位一次放進 1.8.2 的版本頁，跟著 build 一起送就好。

### 5.2 新增 en-US 語系的注意事項

1. 在版本頁左上角的語系下拉選單新增 English (U.S.)，然後把第 2 節的內容貼進去。
2. ⚠️ **我不確定**新增語系後是否**強制**要上傳一整套英文截圖。我的理解是沒上傳的話會沿用主語系的截圖，
   但也可能直接擋住送出。**請先建立語系、把文案貼完，看送出按鈕有沒有被擋**，如果被擋就得先做英文截圖
   （那是另一件工作，不在本次範圍）。
3. 截圖上如果有中文字，英文語系沿用會很怪，這點主控自己權衡。

### 5.3 逐項檢查

- [ ] 關鍵字開頭的**兩個多餘空白已經清掉**（現有字串是 `  分帳,帳本,...`）
- [ ] 關鍵字裡**沒有任何競品名稱**（2.3.7）
- [ ] 所有欄位（含截圖上的文字）**沒有出現 Android 或其他行動平台名稱**（2.3.10）
- [ ] 副標題字數：中文 19、英文 30（英文剛好貼邊，看 ASC 計數器確認）
- [ ] whatsNew 裡的 `<尖括號佔位符>` **全部換掉或刪掉**（中英兩版都要）
- [ ] marketingUrl 填的是 `splity-web-ten.vercel.app`，**不是** `splity-web.vercel.app`
- [ ] supportUrl 指向的頁面實際打得開（填之前 `curl -sI` 一次）
- [ ] Privacy Policy URL 打得開、不是 404
- [ ] description 裡「沒有 iPhone 的朋友也可以用網頁版加入」這句 —— 確認 1.8.2 的分享連結修正
      真的讓網頁加入這條路可用（見第 7 節最後一項）

### 5.4 一個超出本次範圍、但影響很大的觀察

主分類目前是 `SOCIAL_NETWORKING`，而台灣有量的分帳競品主分類都在**財經**。
分類會直接影響榜單曝光與「相似 app」推薦，這件事的影響很可能大於本文所有文案調整的總和。
**我沒有動它，也不建議在同一版一次改動分類＋全部文案**——那樣之後分不清成效是誰帶來的。
建議：這一版先上文案，觀察兩週，再單獨測分類。

---

## 6. 沒做到 / 不確定的地方

1. **字元計算方式**：以 Python `len()` 計。我相信 ASC 的計數器結果相同，但**不是 100% 確定**，以 ASC 畫面為準。
2. **URL 欄位能否不送審直接改**：不確定，看 ASC 欄位是否可編輯。
3. **新增 en-US 是否強制要英文截圖**：不確定，請用「能不能按下送出」實測。
4. **Privacy Policy URL 現值**：本次沒查，主控自己確認。
5. **關鍵字的實際搜尋量**：我沒有 ASO 工具的數據，關鍵字選擇是根據台灣使用者的語言習慣與意圖推論，
   不是量化排序。如果主控有 App Store Connect 的「搜尋詞」報表或第三方 ASO 數據，應該以那個為準覆蓋我的選擇。
6. **競品情報**：任務交下來的競品數據（Bill Bear 4.93 分／1729 則評分等）我**沒有重新實測**，
   本文只用它來決定「哪些賣點不要寫」，沒有把任何競品數字寫進商店頁文案，所以即使數據過時也不影響文案本身。
7. **whatsNew 是架構不是成品**：等主控補實際改動清單。

---

## 7. 誠實性查核：文案裡每一個功能宣稱的出處

寫之前把每一條都對回原始碼，避免寫出 app 沒有的功能。

| 文案宣稱 | 出處 | 結果 |
|---|---|---|
| 6 碼邀請碼、不用註冊 | `FirebaseSharingManager.swift`、字串「請輸入對方分享的 6 碼邀請碼」 | ✅ |
| 沒有 iPhone 的朋友可用網頁版加入 | `web/app/join`，實測 `/join/ABC123` → 200 | ✅ 但見下方註記 |
| 最少轉帳次數 | `SettlementCalculator.swift:18` `case minimized`、`:60` 貪婪配對註解 | ✅ |
| 集中付給一人 | `SettlementCalculator.swift` `case hub` / `calculateHubSettlements` | ✅ |
| 標記結清，所有成員都看得到 | 字串「整本帳會標記為結清，所有成員都會看到並收到通知」 | ✅ |
| 當地幣別自動換算並鎖住匯率 | 字串「以 exchangerate-api.com 當下牌價換算，套用後鎖定。」 | ✅ |
| **三十多種**常用幣別 | `CurrencyService.allSupported` 實際只有 **34 個** currency code | ⚠️ 見下 |
| 快速分帳不用建群組 | `QuickSplit.swift`、字串「快速分帳（不用建群組）」 | ✅ |
| 表格檢視 | `ExpenseSpreadsheetView.swift` | ✅ |
| 匯出 CSV | `SpreadsheetExporter.generateCSV` + `ShareLink` | ✅ |
| 活動紀錄（誰新增／修改／刪除） | `ActivityAction` enum：added/edited/renamed/deleted/restoredExpense 等 11 種 | ✅ |
| 繁中＋英文介面 | `Localizable.xcstrings`：252 組字串，語系 `{'zh-Hant','en'}` | ✅ |
| 沒有廣告／訂閱／內購 | 專案內沒有 StoreKit、沒有 requestReview、沒有廣告 SDK | ✅ |

**⚠️ 幣別數量（本次最重要的一個修正）**
`CurrencyService.swift:15` 的註解寫「實際會回傳 160+ 個幣別都可用」，但那是講 API 端的能力；
使用者在 `CurrencyPickerView` 實際**選得到的只有 `allSupported` 這 34 個**。
所以文案寫的是「三十多種常用幣別」，**不是**「一百多種」。如果之後把選單放寬到 API 全部幣別，
記得回來改這句。

**三個刻意沒有寫進文案的東西：**
- **「即時通知」**：`ActivityNotifier` 用的是 `BGAppRefreshTask` 背景刷新（`earliestBeginDate` 30 分鐘），
  程式碼註解自己寫「時機由系統決定，非即時」。所以文案裡完全沒有提通知，更沒有寫「即時」。
- **「封存後可查完整歷史明細」**：`HistoryRecord` 只存群組名稱、成員數、筆數、日期，**不存明細**。
  雖然 onboarding 文案寫了「歷史紀錄隨時查閱」，但商店頁不該這樣宣稱，所以沒寫。
- **AI 收據掃描、帳號系統、支付整合**：app 沒有，一個字都沒提。

**⚠️ 需要主控確認的一項相依**
description 寫了「沒有 iPhone 的朋友也可以用網頁版輸入同一組邀請碼加入」。網頁端確實可用，
但 app 目前的分享文字（`InviteShareSheet.swift:37`）只帶 App Store 連結
（`下載 Splity：https://apps.apple.com/app/id6760477233`），**沒有帶網頁版連結**。
也就是說使用者分享出去，對方收到的是「去下載 iOS app」。
如果 1.8.2 的「分享連結修正」正好就是要補上網頁連結，那這句文案剛好對得上；
**如果不是，請主控決定要不要把這句從 description 拿掉**，否則就是承諾了一條使用者實際走不到的路。
