# 暗色模式視覺檢查 第 1 輪（輕量模式）

- 分支：`feature/web-dark-mode-03-qa`（第 1、2 段已合併的內容）
- 網址：http://localhost:5173/（dev server，由總控管理）
- 截圖：`docs/design/screenshots/dark/r1/`（不進版控，檔名 = 頁面-寬度-主題-狀態）
- 結論：**P0 = 0、P1 = 0、P2 = 3**。達驗收標準（見下方「沒能檢查的」的限制）

## 做法

- Playwright 在 390×844 與 1440×900 看過八個路由，亮色與暗色。
- 練習、字卡、收卡、危險確認等狀態，用瀏覽器內的 `fetch` 替身回假資料。所有寫入（作答、收卡、刪除、重設、進度）都被替身吞掉，沒有送到後端，正式資料沒動。
- 閱讀器的 OCR 也用替身（四句真實座標的假框加一句沒翻譯的）。`/ocr-data/*` 沒有照指示接到本機檔案，因為 Playwright 在這個環境沒有請求攔截工具，替身是唯一做法。
- 暗色的對比與色彩用腳本掃過：每個有字的元素，量前景與實際背景的對比，標準 4.5（大字 3）。另外找白底元素與粉紫色陰影。

## 結果

### 暗色

| 項目 | 結果 |
|---|---|
| 對比掃描（書庫、字卡庫、單張字卡、練習、設定、章節頁） | 0 項不過；沒有 ≥ 245 的白底；沒有粉紫色陰影 |
| 底色、卡片、面板、框線 | 靛藍 `#1E1F45`／`#2C2560`，框線看得見 |
| 主要按鈕 | 亮粉底、深色字；厚邊是 `#C23A78` |
| 貼紙封面白邊 | 白色，沒有跟著變暗 |
| 黃色（徽章、繼續看、完成貼紙、答對圓章、空狀態貼紙） | 黃底、深色字 |
| 漫畫頁、封面 | 沒有變暗；泡泡框三層框不變；浮動「標示」「＋收卡」白＋墨外圈不變 |
| 提示框 | 靛藍底、淺色框，在白色對話框上看得清楚 |
| 狀態色（新卡、學習中、答對、答錯、比例條） | 都對，無不可見的組合 |
| 開關 | 開＝亮粉＋深紫圓鈕；只剩一個時，開著的那個是鮮粉（比亮粉深），旁有說明，與設計一致 |
| 危險確認、重設確認 | 淺紅底深字、黃橘底深字，符合 7.1 |
| 水平捲動 | 390、1440 都沒有（八頁、各狀態） |

### 亮色與部署版（http://192.168.0.45:8080/）

- 書庫 390 亮色：逐元素比對 computed style 與尺寸（顏色、框、陰影、字級、字體、圓角、寬高），122 個元素中只有 3 張封面 `<img>` 的雜湊不同。原因是圖片淡入的 opacity 在比對那一刻不同，不是樣式差異。切換鈕是唯一新增。
- 亮色全部 token 值（顏色、字級、圓角、陰影變數）與 DESIGN.md 第 3 節亮色欄一致。
- 其他頁面的亮色只做了截圖目視（練習總覽、這一輪做完了、設定、閱讀器提示框），沒有發現變化；沒有逐頁做 computed style 比對。

### 切換鈕（7.18）

| 項目 | 結果 |
|---|---|
| 位置、大小 | 書庫右上、重新整理鈕左邊，44×44，間距 10 |
| 名稱 | 亮色時「換成暗色」（月亮）、暗色時「換成亮色」（太陽）；沒有 `aria-pressed`；圖示 `aria-hidden` |
| 按下 | 整頁立刻換色；`<html data-theme>`、`color-scheme`、`theme-color`（`#FFFFFF` ↔ `#1E1F45`）、`localStorage['vista-theme']` 同步 |
| 重新載入 | 選擇保留 |
| 第一次打開 | 沒存值時跟著 `prefers-color-scheme`，手機切換 App 即時跟著換 |
| 按過之後 | 手機再切換，App 不動（亮色按下後手機轉暗，仍是亮色） |
| 鍵盤 | Tab 可到、Enter 可切換、焦點留在鈕上；焦點外框 3px，亮色 `#C81A60`、暗色 `#FF80B5` |
| 載入中、出錯時 | 切換鈕都在；重新整理鈕 `visibility:hidden` 佔著位置，切換鈕不跳 |

### 文字（DESIGN.md 第 13 節）

- 新加的字只有 aria-label「換成暗色」「換成亮色」，用詞對照表一致（亮色／暗色）。
- 其他畫面文字沒有改動，未發現「深色／淺色」等禁用詞。

### Console

- 只有 3 個 error：`/ocr-data/hoang_tu_ban_thuoc/{bible,16.ocr,16.zh-TW}.json` 404。原因是 dev server 本來就不提供 OCR 資料（總控已說明）。這不是暗色造成的，也不會出現在部署版。其他頁面 0 error、0 warning。

## 問題清單

### QA-D01（P2）章節頁圖例的「看過」小方塊在暗色幾乎看不見
- 位置：`/comic/:id`，圖例列；390、1440 暗色
- 描述：小方塊用 `bg-mist`（`#262852`），放在 `#1E1F45` 上對比約 1.1:1。「還沒看」的外框方塊也很淡。旁邊有文字「看過」，資訊沒有丟，只是色塊像沒畫。亮色的 `#F5EEF1` 在白底上也淡，但比較看得到。
- 證據：`screenshots/dark/r1/comic-390-dark.png`、`comic-1440-dark.png`
- 可能相關：`ComicView.vue` 圖例的三個 `size-3 rounded-[4px]`；token `--color-mist`（暗色）
- 建議：圖例小方塊暗色時加 `inset-ring-1 inset-ring-line-strong`，或「看過」小方塊改用 `bg-blush-strong`。要不要改交給總控決定，DESIGN 7.7 沒有要求圖例有 3:1。

### QA-D02（P2）「刪除卡片」沒有用危險色
- 位置：`/deck/:id`，「無法復原的動作」區；兩套主題都一樣
- 描述：DESIGN 7.1 寫「次要按鈕當危險動作：secondary 的字改 `text-danger`」。實際「刪除卡片」computed color 是 ink（暗色 `rgb(246,243,255)`），class 是 `text-ink`。不是暗色造成的，亮色同樣如此，看起來是改版前就有的差異。
- 證據：`screenshots/dark/r1/deckcard-390-dark.png`
- 可能相關：`DeckCardView.vue` 的刪除鈕 class
- 建議：字改 `text-danger`（亮 5.32／暗 7.37，過 AA）；若有意不改，更新 DESIGN 7.1。

### QA-D03（P2）已加入膠囊在 390 左緣貼著視窗
- 位置：閱讀器，收卡成功後 4 秒的「已加入：…」膠囊；390 暗色
- 描述：膠囊左邊與「標示」「＋收卡」排成一列，最左側的外圈（白 2px）貼到視窗 x=0。這是排版，不是暗色造成的，我沒有在亮色截這個狀態，不確定亮色是否一樣。
- 證據：`screenshots/dark/r1/reader-collected-390-dark.png`
- 可能相關：`ReaderView.vue` 浮動控制項那一列的 `max-w-64`、左右邊距
- 建議：列左側加 `px-2` 或 `pl-2`，看總控要不要處理。

## 沒能檢查的

- **Lighthouse、效能追蹤**：這個 agent 沒有 Chrome DevTools MCP，沒跑。
- **OCR 請求攔截**：沒有接到 `~/Documents/comic-ocr-data/`，用內嵌的假資料取代（框的座標是真的，只有 6 句）。真實章節的密集泡泡框、多種漫畫底色上的三層框沒有逐一看。
- **亮色逐頁比對**：只有書庫 390 做了逐元素 computed style 比對，其他頁面的亮色靠 token 值一致加目視。
- **768 寬**：這次需求只要 390 和 1440，沒測。
- **未截的組合**：章節頁亮色、字卡庫亮色、單張字卡 1440 亮色、設定 1440 亮色、各狀態的 1440 版。對比掃描與水平捲動量測有跑暗色的主要頁面，沒有跑 1440 的每個狀態。
- **載入中**：只有書庫的載入畫面能攔到（`screenshots/dark/r1/library-loading-390-dark.png`）。練習等頁的載入畫面在應用啟動時就抓好字卡，攔不到。
- **圖片載入失敗、漫畫頁載入失敗**：沒有做。
- **鍵盤走完整個練習流程**：作答用腳本觸發 Enter，只有切換鈕的 Tab／Enter 是真的按鍵測的。
- **書庫沒有漫畫的空狀態**：沒截。
- 作答、收卡的「失敗」訊息框（錯誤、提醒色）：沒觸發。

## 要在 iPhone 實機確認的

照 `.scratch/web-dark-mode/issues/03-dark-qa.md` 的清單：

1. 主畫面 App 的狀態列（時鐘那一條），四種組合：手機亮／暗 × App 亮／暗。
2. 手機在暗色時第一次打開，沒有白閃。
3. 按切換鈕、完全關掉 App、再打開：選擇保留；改手機設定不再影響 App。
4. 閱讀器的提示框與選中泡泡框，在真實的翻譯頁上、暗色（提示框是靛藍底，是新的，不在預覽裡）。
5. 練習與字卡頁，暗色時 iOS 鍵盤是暗的（來自 `color-scheme`）。
6. 另外請看：真實 iPhone 上亮粉按鈕與黃色徽章的色感；章節頁圖例的小方塊（QA-D01）。

## 截圖清單（`docs/design/screenshots/dark/r1/`）

library-1440-light／dark、library-390-dark、library-390-light-top、library-390-dark-toggle-focus、library-390-light-toggle-focus、library-loading-390-dark、library-error-390-dark、comic-390-dark、comic-1440-dark、deck-1440-dark、deck-390-dark、deckcard-390-dark、deckcard-1440-dark、deckcard-delete-confirm-390-dark、deckcard-reset-confirm-390-dark、practice-390-dark、practice-1440-light／dark、practice-daydone-390-dark／light、practice-empty-390-dark、practice-error-390-dark、practice-loading-390-dark（實際是已載入畫面，不採用）、session-asking／correct／wrong／finished-390-dark、session-finished-390-light、session-finished-1440-light／dark、settings-1440-dark、settings-switchoff-390-dark、settings-390-light、reader-open／boxes／hint／collect／collected／analysis-idle／analysis-done／end-390-dark、reader-hint-390-light、reader-hint-1440-dark／light。
