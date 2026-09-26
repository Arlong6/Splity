# Splity 1.8.3 更新說明

沿用 `appstore-copy-1.8.2.md` 的 `<!-- field: -->` 慣例：寫進 App Store Connect 時由腳本
從這個檔案解析，不手動複製貼上，避免抄錯或兩邊不一致。

字元上限 whatsNew 4000。

## 這一版對使用者而言改了什麼

只列使用者看得到的。UI 測試的穩定性修正（`e81f23e`）是內部的，不寫進更新說明——
使用者從來沒看過那些測試，寫了只是雜訊。

- 新增「關於」畫面（`95a5113`）：回報問題、網頁版、給評分、隱私權政策
- 回報問題會預填版本、機型、iOS 版本、語言
- 帳目列表底部顯示目前版本（`d10d3e9`）

分類同時從「社交網路」改為「財經」，那不是更新說明的內容，但屬於這一版一起送出的變更。

## zh-Hant

<!-- field: ZH_WHATSNEW limit:4000 -->
```
這一版新增了什麼：

・新增「關於」畫面：在帳目列表最下方點一下就到，裡面可以回報問題、打開網頁版、查看隱私權政策。
・回報問題會自動帶上版本與裝置資訊，你只要描述遇到的狀況就好，不用再多一趟來回確認你的版本。
・列表最下方現在看得到目前的版本號。

有任何問題或建議，歡迎從「關於」裡的「回報問題」告訴我們。
```

## en-US

<!-- field: EN_WHATSNEW limit:4000 -->
```
What's new in this version:

• An About screen, one tap away at the bottom of the ledger list, where you can report a problem, open the web version and read the privacy policy.
• Reporting a problem opens an email that already carries your version and device details, so you only have to describe what happened.
• The bottom of the list now shows which version you are running.

Questions or ideas are always welcome through Report a problem, inside About.
```
