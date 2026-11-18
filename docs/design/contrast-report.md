# 對比驗算報告

- 日期：亮色 2026-11-14；暗色 2026-11-16（第 6 節）；圖例例外 2026-11-17（第 7 節）；發音鈕 2026-11-18（第 8 節）
- 依據：專案根目錄 `DESIGN.md` 第 3 節、`docs/design/design-tokens.json`
- 工具：`python3 ~/.claude/skills/website-studio/scripts/contrast.py`（不加 `--large` 為一般文字門檻 4.5；加 `--large` 為大字／圖示／UI 元件門檻 3.0）
- 標準：一般文字 ≥ 4.5:1；大字（≥ 24px，或 ≥ 18.66px 粗體）、圖示、UI 元件外框、資訊圖形 ≥ 3:1

## 結論

- **亮色、暗色兩套，使用中的組合全部通過。**
- 有一個例外（2026-11-17）：章節頁圖例「看過」的小方塊 `mist-swatch`，亮 1.14、暗 1.45，沒到 3:1。旁邊有字、方塊 `aria-hidden`，不靠它辨識狀態。見第 7 節。
- 亮色：驗算時沒過或太勉強的 9 項都已處理（改色、改用法，或列為禁止組合），其中 3 項是 page-design-spec 原本的寫法，已在 DESIGN.md 15.6 換成通過的 token。見第 5 節。
- 暗色（B 星空藍）：使用中的 89 組全部通過（文字 50、圖形與控制項 25、提示框疊在漫畫上的 14 種底色），B 的預覽色值不用調。沒過或太勉強的 8 項：5 項是現在寫死的白字、白鈕、黃底上的 `text-ink` 不換 token 會壞，2 項是沒有元件用到的組合，1 項是閱讀器提示框只靠框不夠、改靠框和底兩層。全部已處理，見 6.5。
- 兩套共用同一組 class，所以亮色禁止的組合，暗色就算過了也照樣禁止（6.5）。
- 停用狀態在 WCAG 不要求對比，但本系統的停用文字仍 ≥ 4.5（blush-strong 上 ink-faint：亮 4.73、暗 4.92）。
- 發音鈕（2026-11-18）：只用既有 token，亮色、暗色的圖示與實心圓全部 ≥ 3:1，「還沒有發音」那句 ≥ 4.5:1。見第 8 節。

## 1. 文字與背景

| 前景 | 背景 | 用在哪 | 對比 | 門檻 | 結果 |
|---|---|---|---|---|---|
| ink `#2B1F27` | paper `#FFFFFF` | 主要文字 | 15.81 | 4.5 | 通過 |
| ink | blush `#FFF0F5` | 淡粉頂區、練習卡裡的字 | 14.33 | 4.5 | 通過 |
| ink | blush-strong `#FFE0EC` | | 12.90 | 4.5 | 通過 |
| ink | mist `#F5EEF1` | 停用輸入框裡的字（主要） | 13.84 | 4.5 | 通過 |
| ink-soft `#6A5560` | paper | 次要說明、中文翻譯 | 6.82 | 4.5 | 通過 |
| ink-soft | blush | 淡粉卡裡的說明 | 6.18 | 4.5 | 通過 |
| ink-soft | blush-strong | 次要按鈕按下 | 5.56 | 4.5 | 通過 |
| ink-soft | mist | | 5.97 | 4.5 | 通過 |
| ink-soft | line `#F3DDE6` | （備用） | 5.29 | 4.5 | 通過 |
| ink-faint `#765F6B` | paper | 到期時間、未選分頁、placeholder | 5.80 | 4.5 | 通過 |
| ink-faint | blush | 搜尋框提示字 | 5.26 | 4.5 | 通過 |
| ink-faint | mist | 看過的數字格、柔和按鈕停用 | 5.08 | 4.5 | 通過 |
| ink-faint | blush-strong `#FFE0EC` | 主要按鈕停用、停用開關的標籤 | 4.73 | 4.5 | 通過 |
| ink-faint | line `#F3DDE6` | （不使用） | 4.50 | 4.5 | 剛好通過，不採用 |
| white | warning `#9A5B00` | 「確定重設？」確認按鈕 | 5.43 | 4.5 | 通過 |
| white | brand `#C81A60` | 主要按鈕、正在看的數字格、＋收卡 | 5.57 | 4.5 | 通過 |
| white | brand-hover `#B01652` | 主要按鈕 hover | 6.81 | 4.5 | 通過 |
| white | brand-pressed `#9E1449` | 主要按鈕按下 | 7.92 | 4.5 | 通過 |
| brand | paper | 粉色文字、文字按鈕、選中分頁文字 | 5.57 | 4.5 | 通過 |
| brand | blush | 數量標籤、柔和按鈕 | 5.05 | 4.5 | 通過 |
| brand | blush-strong | 「畢業」標籤、柔和按鈕按下 | 4.54 | 4.5 | 通過 |
| brand-hover | paper | 文字按鈕 hover | 6.81 | 4.5 | 通過 |
| brand-hover | blush | | 6.17 | 4.5 | 通過 |
| ink | sun `#FFD23F` | 徽章、「繼續看」標籤 | 10.95 | 4.5 | 通過 |
| white | ink | 閱讀器提示訊息（toast） | 15.81 | 4.5 | 通過 |
| white | danger `#C8322A` | 危險按鈕 | 5.32 | 4.5 | 通過 |
| white | danger-hover `#A82820` | 危險按鈕 hover／按下 | 7.02 | 4.5 | 通過 |
| danger | paper | 錯誤文字、「已到期」 | 5.32 | 4.5 | 通過 |
| danger | danger-tint `#FDECEA` | 區塊內錯誤、柔和危險按鈕 | 4.65 | 4.5 | 通過 |
| danger | blush-strong | （禁止） | 4.34 | 4.5 | **未過 → 禁止組合** |
| success `#17734A` | paper | 「已儲存」「已加入」 | 5.85 | 4.5 | 通過 |
| success | blush | | 5.31 | 4.5 | 通過 |
| success | success-tint `#E6F5EC` | | 5.19 | 4.5 | 通過 |
| warning `#9A5B00` | paper | 「已經收過了」 | 5.43 | 4.5 | 通過 |
| warning | warning-tint `#FFF3D6` | 提醒區塊 | 4.92 | 4.5 | 通過 |

## 2. 字卡狀態文字色（白底、自己的淡底、淡粉底）

| 狀態 | 文字色 | 白 | 淡底 | 淡粉 `#FFF0F5` |
|---|---|---|---|---|
| 新卡 | `#1D63D1` | 5.59 | `#E8F0FD` 4.87 | 5.07 |
| 學習中 | `#9A5B00` | 5.43 | `#FFF3D6` 4.92 | 4.92 |
| 重新學習（含「已到期」「答錯」） | `#C8322A` | 5.32 | `#FDECEA` 4.65 | 4.82 |
| 間隔複習（含「答對」） | `#17734A` | 5.85 | `#E6F5EC` 5.19 | 5.31 |

全部 ≥ 4.5，通過。

## 3. 圖形、圖示與 UI 元件（門檻 3.0）

| 前景 | 背景 | 用在哪 | 對比 | 結果 |
|---|---|---|---|---|
| brand-vivid `#FF4F8B` | paper | 進度條填色（軌道是白底） | 3.11 | 通過 |
| brand-vivid | blush | （原預覽的填空格外框） | 2.82 | **未過 → 改用 brand** |
| brand-vivid | blush-strong | （原預覽的進度條軌道） | 2.54 | **未過 → 軌道改白底** |
| brand | paper | focus 外框、開關開、輸入框聚焦框 | 5.57 | 通過 |
| brand | blush | focus 外框在淡粉上、填空格外框 | 5.05 | 通過 |
| brand | blush-strong | 選中分頁的圖示 | 4.54 | 通過 |
| brand | mist | focus 外框在看過的格子旁 | 4.87 | 通過 |
| ink-faint | paper | 未選分頁圖示、開關關的軌道、搜尋放大鏡 | 5.80 | 通過 |
| ink-faint | blush | 搜尋框放大鏡 | 5.26 | 通過 |
| ink-faint | blush-strong | | 4.73 | 通過 |
| white | line-strong `#A07C8C` | 開關關時的白圓鈕 | 3.65 | 通過 |
| white | brand | 開關開時的白圓鈕 | 5.57 | 通過 |
| white | brand-vivid | 停用但開著的開關白圓鈕 | 3.11 | 通過 |
| line-strong | paper | 輸入框預設外框、開關關的軌道 | 3.65 | 通過 |
| line-strong | blush | 輸入框與開關在淡粉卡上 | 3.31 | 通過 |
| line-strong | line | （不使用） | 2.83 | 未過，不出現 |
| danger | paper | 無效輸入框外框 | 5.32 | 通過 |
| st-review-graphic `#2B9A5E` | paper | 作答欄答對外框 | 3.57 | 通過 |
| st-relearn-graphic `#E5484D` | paper | 作答欄答錯外框 | 3.91 | 通過 |
| brand | blush-strong | 解析中不定進度條的滑塊 | 4.54 | 通過 |
| brand-vivid | paper | 桌機 hover 外框、被挖空那個字的底線、載入圓點 | 3.11 | 通過 |
| ink-faint | mist | 封面載入失敗的書本圖示 | 5.08 | 通過 |
| sun | ink | 提示訊息裡的勾 | 10.95 | 通過 |

### 字卡狀態圖形色（比例條、圖例圓點）

| 狀態 | 圖形色 | 白 | 淡粉 |
|---|---|---|---|
| 新卡 | `#2E6FE0` | 4.70 | 4.26 |
| 學習中（原 `#C98400`） | `#C98400` | 3.10 | **2.81 未過** |
| 學習中（調整後） | `#B87A00` | 3.61 | 3.27 |
| 重新學習 | `#E5484D` | 3.91 | 3.55 |
| 間隔複習 | `#2B9A5E` | 3.57 | 3.23 |

## 4. 閱讀器：疊在漫畫上的框

漫畫底色無法預測，所以用不同亮度的代表色測試：白（對話框）、黑與墨（網點、線稿）、中灰、膚色、天空藍、黃、粉紅、紅、綠、藍綠、紫、深紫、深藍。

單一顏色一定會在某些底色上失敗：

| 前景 | 失敗的底色 |
|---|---|
| 深粉 `#C81A60` | 墨 2.84、中灰 1.41、粉紅 2.58、紅 1.28、綠 2.44 |
| 白 `#FFFFFF` | 粉紅 2.16、綠 2.28 |

所以選中框、提示框、浮動控制項一律用多層：選中框「深粉 3px／白 2px／墨 1px」、有翻譯的提示「深粉 1.5／白 1／墨 1」、沒翻譯的提示「白 1／墨 1」、提示框「白底＋墨框 2px」、浮動控制項「白 2px／墨 1px」。每種底色至少有一層 ≥ 3:1：

| 底色 | 深粉 | 白 | 墨 `#2B1F27` | 最好的一層 |
|---|---|---|---|---|
| 白 `#FFFFFF` | 5.57 | — | 15.81 | 墨 15.81 |
| 黑 `#000000` | 3.77 | 21.00 | — | 白 21.00 |
| 墨 `#2B1F27` | 2.84 | 15.81 | — | 白 15.81 |
| 中灰 `#808080` | 1.41 | 3.95 | 4.00 | 墨 4.00 |
| 膚色 `#F6D7BE` | 4.08 | — | 11.58 | 墨 11.58 |
| 天空藍 `#BFE6FF` | 4.24 | — | 12.03 | 墨 12.03 |
| 黃 `#FFE07A` | 4.29 | — | 12.20 | 墨 12.20 |
| 粉紅 `#FF8DB5` | 2.58 | 2.16 | 7.33 | 墨 7.33 |
| 紅 `#E2382B` | 1.28 | 4.34 | 3.64 | 白 4.34 |
| 綠 `#47C26E` | 2.44 | 2.28 | 6.94 | 墨 6.94 |
| 藍綠 `#1BA59A` | — | 3.05 | 5.19 | 墨 5.19 |
| 紫 `#9B7BEA` | — | 3.27 | 4.83 | 墨 4.83 |
| 深紫 `#5B3A8E` | — | 8.60 | — | 白 8.60 |
| 深藍 `#13306E` | — | 12.53 | — | 白 12.53 |

全部底色都至少有一層 ≥ 3:1，通過。提示框本身是白底墨框，裡面的字是 ink／ink-soft 在白上（15.81／6.82）。

沒翻譯的提示（只有白＋墨）和有翻譯的提示（多一圈深粉）差在有沒有粉色那一圈，不只是換色。

## 5. 沒過的組合與處理

| # | 組合 | 對比 | 處理 |
|---|---|---|---|
| 1 | 鮮粉 `#FF4F8B` 填色／淡粉 2 `#FFE0EC` 軌道（預覽的進度條） | 2.54 | 軌道改白底＋2px `line` 內框，填色對白 3.11 |
| 2 | 鮮粉／淡粉 `#FFF0F5`（預覽的填空格外框） | 2.82 | 在淡粉上的圖形一律改用深粉 `#C81A60`（5.05）；鮮粉只放白底 |
| 3 | 學習中圖形 `#C98400`／淡粉 | 2.81 | 改為 `#B87A00`（白 3.61、淡粉 3.27） |
| 4 | danger `#C8322A`／淡粉 2 | 4.34 | 禁止組合；柔和危險按鈕按下用 danger-tint（4.65） |
| 5 | 單一顏色的泡泡框疊在漫畫上 | 最低 1.28 | 改多層框（第 4 節） |
| 6 | ink-faint／line（停用按鈕底的候選） | 4.50 | 剛好過門檻，不採用；停用改用 blush-strong 底（4.73），和 page-design-spec 一致 |
| 7 | 輸入框用 line `#F3DDE6` 當唯一外框（page-design-spec 原寫法） | 約 1.3 | 改 line-strong `#A07C8C`（白 3.65、淡粉 3.31） |
| 8 | 鮮粉不定進度條滑塊／淡粉 2 軌道（page-design-spec 原寫法） | 2.54 | 滑塊改 brand（4.54） |
| 9 | 學習中圖形色 `#C98400` 用在字卡分布（page-design-spec 原寫法） | 淡粉 2.81 | 換成 `#B87A00` |

## 6. 暗色（B 星空藍）

- 日期：2026-11-16
- 色值：`DESIGN.md` 第 3 節「暗色」欄。paper `#1E1F45`、blush `#2C2560`、blush-strong `#3D3080`、mist `#262852`、line `#36386A`、line-strong `#8A8CC4`、ink `#F6F3FF`、ink-soft `#CCC8F0`、ink-faint `#AEA9DC`、brand `#FF80B5`、brand-hover `#FF6BA8`、brand-pressed `#F2559A`、on-fill `#24102A`。sun `#FFD23F`、on-sun `#2B1F27`、brand-vivid `#FF4F8B` 兩套相同。
- 下表的 paper、blush 等名稱都指暗色的值。原始輸出在第 6.6 節。

### 6.1 文字與背景（門檻 4.5）

| 前景 | 背景 | 用在哪 | 對比 | 結果 |
|---|---|---|---|---|
| ink `#F6F3FF` | paper `#1E1F45` | 主要文字 | 14.35 | 通過 |
| ink | blush `#2C2560` | 淡粉頂區、練習卡裡的字 | 12.45 | 通過 |
| ink | blush-strong `#3D3080` | | 9.92 | 通過 |
| ink | mist `#262852` | | 12.72 | 通過 |
| ink-soft `#CCC8F0` | paper | 次要說明、中文翻譯、圖示鈕 | 9.79 | 通過 |
| ink-soft | blush | 淡粉卡裡的說明、唯讀輸入框 | 8.49 | 通過 |
| ink-soft | blush-strong | 次要按鈕按下 | 6.77 | 通過 |
| ink-soft | mist | 漫畫頁載入失敗 | 8.68 | 通過 |
| ink-faint `#AEA9DC` | paper | 到期時間、未選分頁、placeholder | 7.11 | 通過 |
| ink-faint | blush | 搜尋框提示字 | 6.17 | 通過 |
| ink-faint | blush-strong | 主要按鈕停用、停用開關的標籤 | 4.92 | 通過 |
| ink-faint | mist | 看過的數字格、柔和按鈕停用、停用輸入框 | 6.31 | 通過 |
| brand `#FF80B5` | paper | 粉色文字、選中分頁文字 | 6.74 | 通過 |
| brand | blush | 數量標籤、柔和按鈕 | 5.85 | 通過 |
| brand | blush-strong | 「畢業」標籤、柔和按鈕按下 | 4.66 | 通過 |
| brand-hover `#FF6BA8` | paper | 粉色字 hover | 5.92 | 通過 |
| brand-hover | blush | | 5.14 | 通過 |
| on-fill `#24102A` | brand | 主要按鈕、正在看的數字格、＋收卡、分段選擇選中 | 7.62 | 通過 |
| on-fill | brand-hover | 主要按鈕 hover | 6.70 | 通過 |
| on-fill | brand-pressed `#F2559A` | 主要按鈕按下 | 5.53 | 通過 |
| on-fill 90%（`#3A1B38`） | brand | 兩段文字按鈕的第二段 | 6.46 | 通過 |
| on-fill 90%（`#3A1B3A`） | brand-hover | 同上 hover | 5.67 | 通過 |
| on-fill 90%（`#391735`） | brand-pressed | 同上按下 | 4.85 | 通過 |
| on-sun `#2B1F27` | sun `#FFD23F` | 徽章、「繼續看」「本話完」、完成與空狀態貼紙 | 10.95 | 通過 |
| on-fill | danger `#FF948A` | 危險按鈕 | 8.33 | 通過 |
| on-fill | danger-hover `#F47B70` | 危險按鈕 hover／按下 | 6.69 | 通過 |
| on-fill | warning `#FFC94D` | 「確定重設？」確認按鈕 | 11.60 | 通過 |
| danger | paper | 錯誤文字、「已到期」、次要按鈕當危險動作 | 7.37 | 通過 |
| danger | blush | 次要危險按鈕 hover | 6.40 | 通過 |
| danger | danger-tint `#4B2E4D` | 錯誤訊息框 | 5.48 | 通過 |
| success `#6EDCA2` | paper | 「已儲存」「已加入」 | 9.29 | 通過 |
| success | blush | | 8.06 | 通過 |
| success | success-tint `#244050` | 成功訊息框、「已加入」膠囊 | 6.46 | 通過 |
| warning | paper | 「已經收過了」 | 10.26 | 通過 |
| warning | blush | | 8.90 | 通過 |
| warning | warning-tint `#483C41` | 提醒訊息框 | 6.86 | 通過 |
| ink-soft | warning-tint | 提醒框裡的「到字卡庫修改」連結 | 6.55 | 通過 |
| ink-faint | warning-tint | 提醒框裡的「單字／句子」 | 4.76 | 通過 |
| ink-soft | line `#36386A` | （備用） | 6.78 | 通過 |
| ink-faint | line | （不使用） | 4.92 | 通過，不採用 |
| ink | warning-tint | （備用） | 9.60 | 通過 |
| ink-faint | danger-tint／success-tint | （備用） | 5.29／4.94 | 通過 |

亮色補驗（提醒框裡的次要字，原本沒列）：ink-soft `#6A5560`／warning-tint `#FFF3D6` 6.18、ink-faint `#765F6B`／warning-tint 5.26，通過。

### 6.2 字卡狀態文字色（paper、自己的淡底、blush）

| 狀態 | 文字色 | paper | 淡底 | blush |
|---|---|---|---|---|
| 新卡 | `#9DC0FF` | 8.54 | `#2D396A` 5.99 | 7.41 |
| 學習中 | `#FFC94D` | 10.26 | `#483C41` 6.86 | 8.90 |
| 重新學習（含「已到期」「答錯」） | `#FF948A` | 7.37 | `#4B2E4D` 5.48 | 6.40 |
| 間隔複習（含「答對」） | `#6EDCA2` | 9.29 | `#244050` 6.46 | 8.06 |

全部 ≥ 4.5，通過。淡底是圖形色以 20% 疊在 `#1E1F45` 上的實色（新卡 `#6AA2FF` → `#2D396A`，四個都驗算過混色結果和預覽一致）。

### 6.3 圖形、圖示與 UI 元件（門檻 3.0）

| 前景 | 背景 | 用在哪 | 對比 | 結果 |
|---|---|---|---|---|
| brand-vivid `#FF4F8B` | paper | 進度條填色、桌機 hover 外框、載入圓點、被挖空那個字的底線 | 5.04 | 通過 |
| brand | paper | focus 外框、開關開、輸入框聚焦框 | 6.74 | 通過 |
| brand | blush | focus 外框在淡粉上、填空格外框 | 5.85 | 通過 |
| brand | blush-strong | 選中分頁的圖示、解析中滑塊、錯誤貼紙圖示 | 4.66 | 通過 |
| brand | mist | focus 外框在看過的格子旁 | 5.97 | 通過 |
| ink-soft | paper | 圓形圖示鈕（含主題切換鈕）的圖示 | 9.79 | 通過 |
| ink-faint | paper | 未選分頁圖示 | 7.11 | 通過 |
| ink-faint | blush | 搜尋框放大鏡 | 6.17 | 通過 |
| ink-faint | blush-strong | | 4.92 | 通過 |
| ink-faint | mist | 封面載入失敗的書本圖示 | 6.31 | 通過 |
| line-strong `#8A8CC4` | paper | 輸入框預設外框、開關關的軌道 | 4.96 | 通過 |
| line-strong | blush | 輸入框與開關在淡粉卡上 | 4.30 | 通過 |
| line-strong | line | （不使用） | 3.43 | 通過，不出現 |
| on-fill（圓鈕） | line-strong | 開關關時的圓鈕 | 5.61 | 通過 |
| on-fill（圓鈕） | brand | 開關開時的圓鈕 | 7.62 | 通過 |
| on-fill（圓鈕） | brand-vivid | 停用但開著的開關圓鈕 | 5.70 | 通過 |
| danger | paper | 無效輸入框外框 | 7.37 | 通過 |
| sun | paper | 徽章、正在看小黃點 | 10.88 | 通過 |

#### 字卡狀態圖形色（比例條、圖例圓點、作答欄對錯外框）

| 狀態 | 圖形色 | paper | blush |
|---|---|---|---|
| 新卡 | `#6AA2FF` | 6.15 | 5.34 |
| 學習中 | `#F0B030` | 8.20 | 7.11 |
| 重新學習（答錯外框） | `#FF6B6B` | 5.66 | 4.91 |
| 間隔複習（答對外框） | `#3CC47E` | 7.02 | 6.09 |

### 6.4 閱讀器：暗色的提示框疊在漫畫上

暗色時泡泡框三層框、浮動控制項的白＋墨外圈、`brand-wash` 都和亮色一樣，第 4 節的驗算直接適用。

會變的是提示框：暗色是靛藍底 `#1E1F45` 配淺色框 `#F6F3FF`（`border-ink` 的暗色值）。用第 4 節同一組漫畫代表色測，框和底兩層至少一層 ≥ 3：

| 底色 | 淺色框 `#F6F3FF` | 靛藍底 `#1E1F45` | 最好的一層 |
|---|---|---|---|
| 白 `#FFFFFF` | 1.09 | 15.71 | 底 15.71 |
| 黑 `#000000` | 19.18 | 1.34 | 框 19.18 |
| 墨 `#2B1F27` | 14.44 | 1.01 | 框 14.44 |
| 中灰 `#808080` | 3.61 | 3.98 | 底 3.98 |
| 膚色 `#F6D7BE` | 1.25 | 11.50 | 底 11.50 |
| 天空藍 `#BFE6FF` | 1.20 | 11.95 | 底 11.95 |
| 黃 `#FFE07A` | 1.18 | 12.11 | 底 12.11 |
| 粉紅 `#FF8DB5` | 1.97 | 7.28 | 底 7.28 |
| 紅 `#E2382B` | 3.97 | 3.62 | 框 3.97 |
| 綠 `#47C26E` | 2.08 | 6.89 | 底 6.89 |
| 藍綠 `#1BA59A` | 2.78 | 5.16 | 底 5.16 |
| 紫 `#9B7BEA` | 2.99 | 4.80 | 底 4.80 |
| 深紫 `#5B3A8E` | 7.86 | 1.83 | 框 7.86 |
| 深藍 `#13306E` | 11.45 | 1.25 | 框 11.45 |

全部底色都至少有一層 ≥ 3:1，通過。提示框裡的字是 ink／ink-soft／ink-faint 在 paper 上（14.35／9.79／7.11）。

### 6.5 沒過的組合與處理

| # | 組合 | 暗色對比 | 處理 |
|---|---|---|---|
| 1 | 白字在 brand／brand-hover／brand-pressed 上（現在寫死的 `text-white`） | 2.33／2.65／3.21 | 換 `text-on-fill`（7.62／6.70／5.53） |
| 2 | 白字在 danger 上 | 2.13 | 換 `text-on-fill`（8.33） |
| 3 | 白字在 warning 上 | 1.53 | 換 `text-on-fill`（11.60） |
| 4 | `text-ink` 在 sun 上（ink 在暗色是 `#F6F3FF`） | 1.32 | 換 `text-on-sun`（10.95） |
| 5 | 白圓鈕在 line-strong 上（現在寫死的 `bg-white`） | 3.17（剛過 3，太勉強；而且和開著時的圓鈕不同色） | 換 `bg-on-fill`（5.61） |
| 6 | brand-hover 當字放在 blush-strong 上 | 4.10 | 禁止；目前沒有元件這樣用，粉色字的 hover 只出現在 paper、blush 上 |
| 7 | 白字在 ink 上（亮色第 1 節的提示訊息組合） | 1.09 | 禁止；目前沒有元件這樣用 |
| 8 | 提示框只靠淺色框疊在淺色漫畫上 | 白 1.09、黃 1.18、天空藍 1.20 | 不靠單層：框＋靛藍底兩層，每種底色至少一層 ≥ 3（6.4） |
| 9 | brand-vivid 在 blush／blush-strong 上 | 4.38／3.49（暗色過了） | 亮色 2.82／2.54 沒過，class 共用，**仍禁止** |
| 10 | danger 文字在 blush-strong 上 | 5.10（暗色過了） | 亮色 4.34 沒過，**仍禁止** |

B 的預覽色值沒有任何一個需要調。唯一和預覽不同的是 on-sun：預覽暗色用 `#24102A`（12.30），改成和亮色一樣的 `#2B1F27`（10.95），兩個都過，用同一個值比較單純。

### 6.6 原始輸出

```
$ contrast.py "#F6F3FF" "#1E1F45" "#F6F3FF" "#2C2560" "#F6F3FF" "#3D3080" "#F6F3FF" "#262852" "#CCC8F0" "#1E1F45" "#CCC8F0" "#2C2560" "#CCC8F0" "#3D3080" "#CCC8F0" "#262852" "#AEA9DC" "#1E1F45" "#AEA9DC" "#2C2560" "#AEA9DC" "#3D3080" "#AEA9DC" "#262852" "#AEA9DC" "#36386A" "#CCC8F0" "#36386A" "#FF80B5" "#1E1F45" "#FF80B5" "#2C2560" "#FF80B5" "#3D3080" "#FF80B5" "#262852" "#24102A" "#FF80B5" "#2B1F27" "#FFD23F" "#24102A" "#FFD23F"
#F6F3FF on #1E1F45: 14.35:1  AA PASS  AAA PASS
#F6F3FF on #2C2560: 12.45:1  AA PASS  AAA PASS
#F6F3FF on #3D3080: 9.92:1  AA PASS  AAA PASS
#F6F3FF on #262852: 12.72:1  AA PASS  AAA PASS
#CCC8F0 on #1E1F45: 9.79:1  AA PASS  AAA PASS
#CCC8F0 on #2C2560: 8.49:1  AA PASS  AAA PASS
#CCC8F0 on #3D3080: 6.77:1  AA PASS  AAA FAIL
#CCC8F0 on #262852: 8.68:1  AA PASS  AAA PASS
#AEA9DC on #1E1F45: 7.11:1  AA PASS  AAA PASS
#AEA9DC on #2C2560: 6.17:1  AA PASS  AAA FAIL
#AEA9DC on #3D3080: 4.92:1  AA PASS  AAA FAIL
#AEA9DC on #262852: 6.31:1  AA PASS  AAA FAIL
#AEA9DC on #36386A: 4.92:1  AA PASS  AAA FAIL
#CCC8F0 on #36386A: 6.78:1  AA PASS  AAA FAIL
#FF80B5 on #1E1F45: 6.74:1  AA PASS  AAA FAIL
#FF80B5 on #2C2560: 5.85:1  AA PASS  AAA FAIL
#FF80B5 on #3D3080: 4.66:1  AA PASS  AAA FAIL
#FF80B5 on #262852: 5.97:1  AA PASS  AAA FAIL
#24102A on #FF80B5: 7.62:1  AA PASS  AAA PASS
#2B1F27 on #FFD23F: 10.95:1  AA PASS  AAA PASS
#24102A on #FFD23F: 12.30:1  AA PASS  AAA PASS

$ contrast.py "#24102A" "#FF6BA8" "#24102A" "#F7609E" "#24102A" "#F2559A" "#24102A" "#E8488F" "#FF6BA8" "#1E1F45" "#FF6BA8" "#2C2560" "#24102A" "#FF948A" "#24102A" "#F47B70" "#24102A" "#FF7B70" "#24102A" "#FFC94D" "#24102A" "#F0B030" "#FF948A" "#1E1F45" "#FF948A" "#2C2560" "#FF948A" "#4B2E4D" "#FF948A" "#3D3080" "#6EDCA2" "#1E1F45" "#6EDCA2" "#2C2560" "#6EDCA2" "#244050" "#FFC94D" "#1E1F45" "#FFC94D" "#2C2560" "#FFC94D" "#483C41" "#9DC0FF" "#1E1F45" "#9DC0FF" "#2C2560" "#9DC0FF" "#2D396A"
#24102A on #FF6BA8: 6.70:1  AA PASS  AAA FAIL
#24102A on #F7609E: 6.02:1  AA PASS  AAA FAIL
#24102A on #F2559A: 5.53:1  AA PASS  AAA FAIL
#24102A on #E8488F: 4.87:1  AA PASS  AAA FAIL
#FF6BA8 on #1E1F45: 5.92:1  AA PASS  AAA FAIL
#FF6BA8 on #2C2560: 5.14:1  AA PASS  AAA FAIL
#24102A on #FF948A: 8.33:1  AA PASS  AAA PASS
#24102A on #F47B70: 6.69:1  AA PASS  AAA FAIL
#24102A on #FF7B70: 7.03:1  AA PASS  AAA PASS
#24102A on #FFC94D: 11.60:1  AA PASS  AAA PASS
#24102A on #F0B030: 9.27:1  AA PASS  AAA PASS
#FF948A on #1E1F45: 7.37:1  AA PASS  AAA PASS
#FF948A on #2C2560: 6.40:1  AA PASS  AAA FAIL
#FF948A on #4B2E4D: 5.48:1  AA PASS  AAA FAIL
#FF948A on #3D3080: 5.10:1  AA PASS  AAA FAIL
#6EDCA2 on #1E1F45: 9.29:1  AA PASS  AAA PASS
#6EDCA2 on #2C2560: 8.06:1  AA PASS  AAA PASS
#6EDCA2 on #244050: 6.46:1  AA PASS  AAA FAIL
#FFC94D on #1E1F45: 10.26:1  AA PASS  AAA PASS
#FFC94D on #2C2560: 8.90:1  AA PASS  AAA PASS
#FFC94D on #483C41: 6.86:1  AA PASS  AAA FAIL
#9DC0FF on #1E1F45: 8.54:1  AA PASS  AAA PASS
#9DC0FF on #2C2560: 7.41:1  AA PASS  AAA PASS
#9DC0FF on #2D396A: 5.99:1  AA PASS  AAA FAIL
（hover／按下的候選比較：brand-hover 選 #FF6BA8、brand-pressed 選 #F2559A、danger-hover 選 #F47B70，都是「往深一階、配 on-fill 仍 ≥ 5」的候選裡最接近原色的）

$ contrast.py --large "#6AA2FF" "#1E1F45" "#6AA2FF" "#2C2560" "#F0B030" "#1E1F45" "#F0B030" "#2C2560" "#FF6B6B" "#1E1F45" "#FF6B6B" "#2C2560" "#3CC47E" "#1E1F45" "#3CC47E" "#2C2560" "#FF4F8B" "#1E1F45" "#FF4F8B" "#2C2560" "#FF4F8B" "#3D3080" "#FF4F8B" "#262852" "#8A8CC4" "#1E1F45" "#8A8CC4" "#2C2560" "#8A8CC4" "#36386A" "#24102A" "#8A8CC4" "#24102A" "#FF80B5" "#24102A" "#FF4F8B" "#FF80B5" "#1E1F45" "#FF80B5" "#3D3080" "#FFD23F" "#1E1F45" "#AEA9DC" "#3D3080" "#FF948A" "#1E1F45"
#6AA2FF on #1E1F45: 6.15:1  AA PASS  AAA PASS  (large text)
#6AA2FF on #2C2560: 5.34:1  AA PASS  AAA PASS  (large text)
#F0B030 on #1E1F45: 8.20:1  AA PASS  AAA PASS  (large text)
#F0B030 on #2C2560: 7.11:1  AA PASS  AAA PASS  (large text)
#FF6B6B on #1E1F45: 5.66:1  AA PASS  AAA PASS  (large text)
#FF6B6B on #2C2560: 4.91:1  AA PASS  AAA PASS  (large text)
#3CC47E on #1E1F45: 7.02:1  AA PASS  AAA PASS  (large text)
#3CC47E on #2C2560: 6.09:1  AA PASS  AAA PASS  (large text)
#FF4F8B on #1E1F45: 5.04:1  AA PASS  AAA PASS  (large text)
#FF4F8B on #2C2560: 4.38:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #3D3080: 3.49:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #262852: 4.47:1  AA PASS  AAA FAIL  (large text)
#8A8CC4 on #1E1F45: 4.96:1  AA PASS  AAA PASS  (large text)
#8A8CC4 on #2C2560: 4.30:1  AA PASS  AAA FAIL  (large text)
#8A8CC4 on #36386A: 3.43:1  AA PASS  AAA FAIL  (large text)
#24102A on #8A8CC4: 5.61:1  AA PASS  AAA PASS  (large text)
#24102A on #FF80B5: 7.62:1  AA PASS  AAA PASS  (large text)
#24102A on #FF4F8B: 5.70:1  AA PASS  AAA PASS  (large text)
#FF80B5 on #1E1F45: 6.74:1  AA PASS  AAA PASS  (large text)
#FF80B5 on #3D3080: 4.66:1  AA PASS  AAA PASS  (large text)
#FFD23F on #1E1F45: 10.88:1  AA PASS  AAA PASS  (large text)
#AEA9DC on #3D3080: 4.92:1  AA PASS  AAA PASS  (large text)
#FF948A on #1E1F45: 7.37:1  AA PASS  AAA PASS  (large text)

$ contrast.py --large "#F6F3FF" "#FFFFFF" "#F6F3FF" "#000000" "#F6F3FF" "#2B1F27" "#F6F3FF" "#808080" "#F6F3FF" "#F6D7BE" "#F6F3FF" "#BFE6FF" "#F6F3FF" "#FFE07A" "#F6F3FF" "#FF8DB5" "#F6F3FF" "#E2382B" "#F6F3FF" "#47C26E" "#F6F3FF" "#1BA59A" "#F6F3FF" "#9B7BEA" "#F6F3FF" "#5B3A8E" "#F6F3FF" "#13306E" "#1E1F45" "#FFFFFF" "#1E1F45" "#000000" "#1E1F45" "#2B1F27" "#1E1F45" "#808080" "#1E1F45" "#F6D7BE" "#1E1F45" "#BFE6FF" "#1E1F45" "#FFE07A" "#1E1F45" "#FF8DB5" "#1E1F45" "#E2382B" "#1E1F45" "#47C26E" "#1E1F45" "#1BA59A" "#1E1F45" "#9B7BEA" "#1E1F45" "#5B3A8E" "#1E1F45" "#13306E"
#F6F3FF on #FFFFFF: 1.09:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #000000: 19.18:1  AA PASS  AAA PASS  (large text)
#F6F3FF on #2B1F27: 14.44:1  AA PASS  AAA PASS  (large text)
#F6F3FF on #808080: 3.61:1  AA PASS  AAA FAIL  (large text)
#F6F3FF on #F6D7BE: 1.25:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #BFE6FF: 1.20:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #FFE07A: 1.18:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #FF8DB5: 1.97:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #E2382B: 3.97:1  AA PASS  AAA FAIL  (large text)
#F6F3FF on #47C26E: 2.08:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #1BA59A: 2.78:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #9B7BEA: 2.99:1  AA FAIL  AAA FAIL  (large text)
#F6F3FF on #5B3A8E: 7.86:1  AA PASS  AAA PASS  (large text)
#F6F3FF on #13306E: 11.45:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #FFFFFF: 15.71:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #000000: 1.34:1  AA FAIL  AAA FAIL  (large text)
#1E1F45 on #2B1F27: 1.01:1  AA FAIL  AAA FAIL  (large text)
#1E1F45 on #808080: 3.98:1  AA PASS  AAA FAIL  (large text)
#1E1F45 on #F6D7BE: 11.50:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #BFE6FF: 11.95:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #FFE07A: 12.11:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #FF8DB5: 7.28:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #E2382B: 3.62:1  AA PASS  AAA FAIL  (large text)
#1E1F45 on #47C26E: 6.89:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #1BA59A: 5.16:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #9B7BEA: 4.80:1  AA PASS  AAA PASS  (large text)
#1E1F45 on #5B3A8E: 1.83:1  AA FAIL  AAA FAIL  (large text)
#1E1F45 on #13306E: 1.25:1  AA FAIL  AAA FAIL  (large text)
（提示框的框與底分開測；每一種底色看框或底其中一層，見 6.4。單層的 FAIL 是預期的）

$ contrast.py "#AEA9DC" "#483C41" "#CCC8F0" "#483C41" "#F6F3FF" "#483C41" "#765F6B" "#FFF3D6" "#6A5560" "#FFF3D6" "#FF6BA8" "#2C2560" "#FF6BA8" "#3D3080" "#24102A" "#F47B70" "#6EDCA2" "#2C2560" "#AEA9DC" "#4B2E4D" "#AEA9DC" "#244050"
#AEA9DC on #483C41: 4.76:1  AA PASS  AAA FAIL
#CCC8F0 on #483C41: 6.55:1  AA PASS  AAA FAIL
#F6F3FF on #483C41: 9.60:1  AA PASS  AAA PASS
#765F6B on #FFF3D6: 5.26:1  AA PASS  AAA FAIL
#6A5560 on #FFF3D6: 6.18:1  AA PASS  AAA FAIL
#FF6BA8 on #2C2560: 5.14:1  AA PASS  AAA FAIL
#FF6BA8 on #3D3080: 4.10:1  AA FAIL  AAA FAIL
#24102A on #F47B70: 6.69:1  AA PASS  AAA FAIL
#6EDCA2 on #2C2560: 8.06:1  AA PASS  AAA PASS
#AEA9DC on #4B2E4D: 5.29:1  AA PASS  AAA FAIL
#AEA9DC on #244050: 4.94:1  AA PASS  AAA FAIL

$ contrast.py "#F6F3FF" "#FFD23F" "#FFFFFF" "#FF80B5" "#FFFFFF" "#FF948A" "#FFFFFF" "#FFC94D" "#FFFFFF" "#F6F3FF" "#FFFFFF" "#8A8CC4" "#FFFFFF" "#FF4F8B" "#FFFFFF" "#FF6BA8" "#FFFFFF" "#F2559A"
#F6F3FF on #FFD23F: 1.32:1  AA FAIL  AAA FAIL
#FFFFFF on #FF80B5: 2.33:1  AA FAIL  AAA FAIL
#FFFFFF on #FF948A: 2.13:1  AA FAIL  AAA FAIL
#FFFFFF on #FFC94D: 1.53:1  AA FAIL  AAA FAIL
#FFFFFF on #F6F3FF: 1.09:1  AA FAIL  AAA FAIL
#FFFFFF on #8A8CC4: 3.17:1  AA FAIL  AAA FAIL
#FFFFFF on #FF4F8B: 3.11:1  AA FAIL  AAA FAIL
#FFFFFF on #FF6BA8: 2.65:1  AA FAIL  AAA FAIL
#FFFFFF on #F2559A: 3.21:1  AA FAIL  AAA FAIL
（不換 token 會壞的組合：現在寫死的白字、白鈕、黃底上的 text-ink 在暗色的樣子。見 6.5）

$ contrast.py "#3A1B38" "#FF80B5" "#391735" "#F2559A" "#3A1B3A" "#FF6BA8" "#F9E8EF" "#C81A60"
#3A1B38 on #FF80B5: 6.46:1  AA PASS  AAA FAIL
#391735 on #F2559A: 4.85:1  AA PASS  AAA FAIL
#3A1B3A on #FF6BA8: 5.67:1  AA PASS  AAA FAIL
#F9E8EF on #C81A60: 4.72:1  AA PASS  AAA FAIL
（兩段文字按鈕第二段的 opacity-90：on-fill 90% 疊在主粉上的實色。最後一行是亮色補驗，白 90% 在深粉上）
```

## 7. 例外：章節頁圖例「看過」的小方塊（2026-11-17）

- 來源：暗色 QA 的 QA-D01（`docs/design/dark-qa-report.md`）。圖例「看過」的 12px 小方塊原本用 `mist`，暗色 `#262852` 放在頁面底上幾乎看不見。
- 使用者在三個選項（不改／加外框／紫色實心）裡選紫色實心。新增 `mist-swatch`（`color.bg.muted-swatch`），只給這個小方塊用，數字格本身仍用 `mist`（DESIGN.md 第 3 節、7.7）。用 token 覆寫，不寫 `dark:`。

| 前景 | 背景 | 主題 | 用在哪 | 對比 | 門檻 | 結果 |
|---|---|---|---|---|---|---|
| mist `#262852` | paper `#1E1F45` | 暗色 | 原本的圖例「看過」 | 1.13 | 3.0 | 未過 → 改用 `mist-swatch` |
| mist-swatch `#F5EEF1` | paper `#FFFFFF` | 亮色 | 圖例「看過」 | 1.14 | 3.0 | **例外**（旁邊有字） |
| mist-swatch `#3D3080` | paper `#1E1F45` | 暗色 | 圖例「看過」 | 1.45 | 3.0 | **例外**（旁邊有字） |

為什麼可以例外：
- 方塊旁邊就寫著「看過」，方塊本身 `aria-hidden="true"`，狀態不靠方塊的顏色辨識。數字格本身每格有 `aria-label`，看過和還沒看也差在實心 vs 外框與字重（DESIGN.md 第 10 節）。
- 沒選加外框：還沒看的格子就是外框格，加一圈框會讓「看過」像「還沒看」。
- 亮色和原本一樣（1.14），外觀不變；暗色從 1.13 提高到 1.45，12px 的方塊看得出來。
- 例外只限這個小方塊；`mist-swatch` 不用在別的地方。

原始輸出：

```
$ contrast.py --large "#262852" "#1E1F45" "#F5EEF1" "#FFFFFF" "#3D3080" "#1E1F45"
#262852 on #1E1F45: 1.13:1  AA FAIL  AAA FAIL  (large text)
#F5EEF1 on #FFFFFF: 1.14:1  AA FAIL  AAA FAIL  (large text)
#3D3080 on #1E1F45: 1.45:1  AA FAIL  AAA FAIL  (large text)
```

## 8. 發音鈕（2026-11-18）

- 元件：DESIGN.md 7.19（`web/src/components/CardAudioButton.vue`）。只用既有 token，沒有新增顏色。
- 圖示和實心圓用圖形的門檻 3:1；「還沒有發音，下次產生發音時會補上。」是 13px 的字，用一般文字的門檻 4.5:1。
- 按鈕都放在頁面底 `paper` 上（練習回饋的答案列、單張字卡的原文旁），不放在淡粉卡裡。

| 前景 | 背景 | 主題 | 用在哪 | 對比 | 門檻 | 結果 |
|---|---|---|---|---|---|---|
| brand `#C81A60` | paper `#FFFFFF` | 亮色 | 待播放、載入中的圖示 | 5.57 | 3.0 | 通過 |
| brand `#FF80B5` | paper `#1E1F45` | 暗色 | 待播放、載入中的圖示 | 6.74 | 3.0 | 通過 |
| brand `#C81A60` | blush `#FFF0F5` | 亮色 | 待播放 hover、按下 | 5.05 | 3.0 | 通過 |
| brand `#FF80B5` | blush `#2C2560` | 暗色 | 待播放 hover、按下 | 5.85 | 3.0 | 通過 |
| on-fill `#FFFFFF` | brand `#C81A60` | 亮色 | 播放中的方塊圖示 | 5.57 | 3.0 | 通過 |
| on-fill `#24102A` | brand `#FF80B5` | 暗色 | 播放中的方塊圖示 | 7.62 | 3.0 | 通過 |
| brand `#C81A60` | paper `#FFFFFF` | 亮色 | 播放中的實心圓對頁面底 | 5.57 | 3.0 | 通過 |
| brand `#FF80B5` | paper `#1E1F45` | 暗色 | 播放中的實心圓對頁面底 | 6.74 | 3.0 | 通過 |
| ink-faint `#765F6B` | paper `#FFFFFF` | 亮色 | 「還沒有發音…」 | 5.80 | 4.5 | 通過 |
| ink-faint `#AEA9DC` | paper `#1E1F45` | 暗色 | 「還沒有發音…」 | 7.11 | 4.5 | 通過 |

- focus-visible 是全站的主粉外框，對 paper 亮 5.57、暗 6.74（第 3 節、6.3），不另外驗。
- 待播放的外框 `inset-ring-line` 是裝飾 token（DESIGN.md 第 3 節 `color.border.subtle`），不負責辨識，按鈕靠圖示辨識，和其他圓形圖示鈕一樣。下面原始輸出最後兩行是它的值（亮 1.29、暗 1.44），只是記錄，不算未過；指令的結束碼是 1，就是因為這兩行。

原始輸出：

```
$ contrast.py --large "#C81A60" "#FFFFFF" "#C81A60" "#FFF0F5" "#FFFFFF" "#C81A60" "#FF80B5" "#1E1F45" "#FF80B5" "#2C2560" "#24102A" "#FF80B5" "#F3DDE6" "#FFFFFF" "#36386A" "#1E1F45"
#C81A60 on #FFFFFF: 5.57:1  AA PASS  AAA PASS  (large text)
#C81A60 on #FFF0F5: 5.05:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #C81A60: 5.57:1  AA PASS  AAA PASS  (large text)
#FF80B5 on #1E1F45: 6.74:1  AA PASS  AAA PASS  (large text)
#FF80B5 on #2C2560: 5.85:1  AA PASS  AAA PASS  (large text)
#24102A on #FF80B5: 7.62:1  AA PASS  AAA PASS  (large text)
#F3DDE6 on #FFFFFF: 1.29:1  AA FAIL  AAA FAIL  (large text)
#36386A on #1E1F45: 1.44:1  AA FAIL  AAA FAIL  (large text)

$ contrast.py "#765F6B" "#FFFFFF" "#AEA9DC" "#1E1F45"
#765F6B on #FFFFFF: 5.80:1  AA PASS  AAA FAIL
#AEA9DC on #1E1F45: 7.11:1  AA PASS  AAA PASS
```

實心圓對頁面底和「brand 在 paper 上」是同一組顏色，對比是對稱的，直接引用第一行和第四行。

## 原始輸出（亮色，2026-11-14）

```
$ contrast.py "#2B1F27" "#FFFFFF" "#2B1F27" "#FFF0F5" "#2B1F27" "#FFE0EC" "#6A5560" "#FFFFFF" "#6A5560" "#FFF0F5" "#6A5560" "#FFE0EC" "#765F6B" "#FFFFFF" "#765F6B" "#FFF0F5" "#765F6B" "#F5EEF1" "#FFFFFF" "#C81A60" "#C81A60" "#FFFFFF" "#C81A60" "#FFF0F5" "#C81A60" "#FFE0EC" "#2B1F27" "#FFD23F"
#2B1F27 on #FFFFFF: 15.81:1  AA PASS  AAA PASS
#2B1F27 on #FFF0F5: 14.33:1  AA PASS  AAA PASS
#2B1F27 on #FFE0EC: 12.90:1  AA PASS  AAA PASS
#6A5560 on #FFFFFF: 6.82:1  AA PASS  AAA FAIL
#6A5560 on #FFF0F5: 6.18:1  AA PASS  AAA FAIL
#6A5560 on #FFE0EC: 5.56:1  AA PASS  AAA FAIL
#765F6B on #FFFFFF: 5.80:1  AA PASS  AAA FAIL
#765F6B on #FFF0F5: 5.26:1  AA PASS  AAA FAIL
#765F6B on #F5EEF1: 5.08:1  AA PASS  AAA FAIL
#FFFFFF on #C81A60: 5.57:1  AA PASS  AAA FAIL
#C81A60 on #FFFFFF: 5.57:1  AA PASS  AAA FAIL
#C81A60 on #FFF0F5: 5.05:1  AA PASS  AAA FAIL
#C81A60 on #FFE0EC: 4.54:1  AA PASS  AAA FAIL
#2B1F27 on #FFD23F: 10.95:1  AA PASS  AAA PASS

$ contrast.py "#1D63D1" "#FFFFFF" "#1D63D1" "#E8F0FD" "#1D63D1" "#FFF0F5" "#9A5B00" "#FFFFFF" "#9A5B00" "#FFF3D6" "#9A5B00" "#FFF0F5" "#C8322A" "#FFFFFF" "#C8322A" "#FDECEA" "#C8322A" "#FFF0F5" "#17734A" "#FFFFFF" "#17734A" "#E6F5EC" "#17734A" "#FFF0F5"
#1D63D1 on #FFFFFF: 5.59:1  AA PASS  AAA FAIL
#1D63D1 on #E8F0FD: 4.87:1  AA PASS  AAA FAIL
#1D63D1 on #FFF0F5: 5.07:1  AA PASS  AAA FAIL
#9A5B00 on #FFFFFF: 5.43:1  AA PASS  AAA FAIL
#9A5B00 on #FFF3D6: 4.92:1  AA PASS  AAA FAIL
#9A5B00 on #FFF0F5: 4.92:1  AA PASS  AAA FAIL
#C8322A on #FFFFFF: 5.32:1  AA PASS  AAA FAIL
#C8322A on #FDECEA: 4.65:1  AA PASS  AAA FAIL
#C8322A on #FFF0F5: 4.82:1  AA PASS  AAA FAIL
#17734A on #FFFFFF: 5.85:1  AA PASS  AAA FAIL
#17734A on #E6F5EC: 5.19:1  AA PASS  AAA FAIL
#17734A on #FFF0F5: 5.31:1  AA PASS  AAA FAIL

$ contrast.py --large "#E5484D" "#FFFFFF" "#E5484D" "#FFF0F5" "#2E6FE0" "#FFFFFF" "#2E6FE0" "#FFF0F5" "#C98400" "#FFFFFF" "#C98400" "#FFF0F5" "#2B9A5E" "#FFFFFF" "#2B9A5E" "#FFF0F5" "#FF4F8B" "#FFFFFF" "#FF4F8B" "#FFF0F5" "#FF4F8B" "#FFE0EC" "#C81A60" "#FFE0EC" "#765F6B" "#FFFFFF" "#765F6B" "#FFE0EC"
#E5484D on #FFFFFF: 3.91:1  AA PASS  AAA FAIL  (large text)
#E5484D on #FFF0F5: 3.55:1  AA PASS  AAA FAIL  (large text)
#2E6FE0 on #FFFFFF: 4.70:1  AA PASS  AAA PASS  (large text)
#2E6FE0 on #FFF0F5: 4.26:1  AA PASS  AAA FAIL  (large text)
#C98400 on #FFFFFF: 3.10:1  AA PASS  AAA FAIL  (large text)
#C98400 on #FFF0F5: 2.81:1  AA FAIL  AAA FAIL  (large text)
#2B9A5E on #FFFFFF: 3.57:1  AA PASS  AAA FAIL  (large text)
#2B9A5E on #FFF0F5: 3.23:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #FFFFFF: 3.11:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #FFF0F5: 2.82:1  AA FAIL  AAA FAIL  (large text)
#FF4F8B on #FFE0EC: 2.54:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #FFE0EC: 4.54:1  AA PASS  AAA PASS  (large text)
#765F6B on #FFFFFF: 5.80:1  AA PASS  AAA PASS  (large text)
#765F6B on #FFE0EC: 4.73:1  AA PASS  AAA PASS  (large text)

$ contrast.py --large "#B87A00" "#FFFFFF" "#B87A00" "#FFF0F5" "#B37600" "#FFFFFF" "#B37600" "#FFF0F5" "#FF4F8B" "#FFFFFF" "#C81A60" "#FFF0F5" "#A07C8C" "#FFFFFF" "#A07C8C" "#FFF0F5" "#9A7787" "#FFFFFF" "#9A7787" "#FFF0F5" "#8F7280" "#FFFFFF" "#8F7280" "#FFF0F5"
#B87A00 on #FFFFFF: 3.61:1  AA PASS  AAA FAIL  (large text)
#B87A00 on #FFF0F5: 3.27:1  AA PASS  AAA FAIL  (large text)
#B37600 on #FFFFFF: 3.81:1  AA PASS  AAA FAIL  (large text)
#B37600 on #FFF0F5: 3.46:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #FFFFFF: 3.11:1  AA PASS  AAA FAIL  (large text)
#C81A60 on #FFF0F5: 5.05:1  AA PASS  AAA PASS  (large text)
#A07C8C on #FFFFFF: 3.65:1  AA PASS  AAA FAIL  (large text)
#A07C8C on #FFF0F5: 3.31:1  AA PASS  AAA FAIL  (large text)
#9A7787 on #FFFFFF: 3.92:1  AA PASS  AAA FAIL  (large text)
#9A7787 on #FFF0F5: 3.55:1  AA PASS  AAA FAIL  (large text)
#8F7280 on #FFFFFF: 4.30:1  AA PASS  AAA FAIL  (large text)
#8F7280 on #FFF0F5: 3.90:1  AA PASS  AAA FAIL  (large text)
（候選比較：學習中圖形色選 #B87A00，控制項外框選 #A07C8C，兩者都是過門檻裡最接近預覽色調的）

$ contrast.py --large "#C81A60" "#FFFFFF" "#C81A60" "#000000" "#C81A60" "#2B1F27" "#C81A60" "#808080" "#C81A60" "#F6D7BE" "#C81A60" "#BFE6FF" "#C81A60" "#FF8DB5" "#C81A60" "#E2382B" "#C81A60" "#47C26E" "#C81A60" "#FFE07A" "#FFFFFF" "#000000" "#FFFFFF" "#2B1F27" "#FFFFFF" "#808080" "#FFFFFF" "#FF8DB5" "#FFFFFF" "#E2382B" "#FFFFFF" "#47C26E" "#FFFFFF" "#C81A60" "#FFFFFF" "#9B7BEA" "#FFFFFF" "#5B3A8E"
#C81A60 on #FFFFFF: 5.57:1  AA PASS  AAA PASS  (large text)
#C81A60 on #000000: 3.77:1  AA PASS  AAA FAIL  (large text)
#C81A60 on #2B1F27: 2.84:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #808080: 1.41:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #F6D7BE: 4.08:1  AA PASS  AAA FAIL  (large text)
#C81A60 on #BFE6FF: 4.24:1  AA PASS  AAA FAIL  (large text)
#C81A60 on #FF8DB5: 2.58:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #E2382B: 1.28:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #47C26E: 2.44:1  AA FAIL  AAA FAIL  (large text)
#C81A60 on #FFE07A: 4.29:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #000000: 21.00:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #2B1F27: 15.81:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #808080: 3.95:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #FF8DB5: 2.16:1  AA FAIL  AAA FAIL  (large text)
#FFFFFF on #E2382B: 4.34:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #47C26E: 2.28:1  AA FAIL  AAA FAIL  (large text)
#FFFFFF on #C81A60: 5.57:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #9B7BEA: 3.27:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #5B3A8E: 8.60:1  AA PASS  AAA PASS  (large text)

$ contrast.py --large "#2B1F27" "#FFFFFF" "#2B1F27" "#808080" "#2B1F27" "#FF8DB5" "#2B1F27" "#47C26E" "#2B1F27" "#E2382B" "#2B1F27" "#9B7BEA" "#2B1F27" "#F6D7BE" "#2B1F27" "#BFE6FF" "#2B1F27" "#FFE07A" "#2B1F27" "#1BA59A" "#FFFFFF" "#1BA59A" "#FFFFFF" "#5B3A8E" "#FFFFFF" "#13306E"
#2B1F27 on #FFFFFF: 15.81:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #808080: 4.00:1  AA PASS  AAA FAIL  (large text)
#2B1F27 on #FF8DB5: 7.33:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #47C26E: 6.94:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #E2382B: 3.64:1  AA PASS  AAA FAIL  (large text)
#2B1F27 on #9B7BEA: 4.83:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #F6D7BE: 11.58:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #BFE6FF: 12.03:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #FFE07A: 12.20:1  AA PASS  AAA PASS  (large text)
#2B1F27 on #1BA59A: 5.19:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #1BA59A: 3.05:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #5B3A8E: 8.60:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #13306E: 12.53:1  AA PASS  AAA PASS  (large text)

$ contrast.py "#FFFFFF" "#B01652" "#FFFFFF" "#9E1449" "#765F6B" "#F3DDE6" "#6A5560" "#F3DDE6" "#FFFFFF" "#C8322A" "#FFFFFF" "#A82820" "#C8322A" "#FDECEA" "#17734A" "#E6F5EC" "#2B1F27" "#F5EEF1" "#6A5560" "#F5EEF1" "#FFFFFF" "#2B1F27" "#C81A60" "#F5EEF1" "#C8322A" "#FFE0EC" "#B01652" "#FFFFFF" "#B01652" "#FFF0F5"
#FFFFFF on #B01652: 6.81:1  AA PASS  AAA FAIL
#FFFFFF on #9E1449: 7.92:1  AA PASS  AAA PASS
#765F6B on #F3DDE6: 4.50:1  AA PASS  AAA FAIL
#6A5560 on #F3DDE6: 5.29:1  AA PASS  AAA FAIL
#FFFFFF on #C8322A: 5.32:1  AA PASS  AAA FAIL
#FFFFFF on #A82820: 7.02:1  AA PASS  AAA PASS
#C8322A on #FDECEA: 4.65:1  AA PASS  AAA FAIL
#17734A on #E6F5EC: 5.19:1  AA PASS  AAA FAIL
#2B1F27 on #F5EEF1: 13.84:1  AA PASS  AAA PASS
#6A5560 on #F5EEF1: 5.97:1  AA PASS  AAA FAIL
#FFFFFF on #2B1F27: 15.81:1  AA PASS  AAA PASS
#C81A60 on #F5EEF1: 4.87:1  AA PASS  AAA FAIL
#C8322A on #FFE0EC: 4.34:1  AA FAIL  AAA FAIL
#B01652 on #FFFFFF: 6.81:1  AA PASS  AAA FAIL
#B01652 on #FFF0F5: 6.17:1  AA PASS  AAA FAIL

$ contrast.py --large "#FFD23F" "#2B1F27" "#A07C8C" "#FFFFFF" "#765F6B" "#FFFFFF" "#765F6B" "#FFF0F5" "#C81A60" "#FFFFFF" "#C81A60" "#FFF0F5" "#C81A60" "#FFE0EC" "#C81A60" "#F5EEF1" "#C8322A" "#FFFFFF" "#B87A00" "#FFFFFF" "#FF4F8B" "#FFFFFF"
#FFD23F on #2B1F27: 10.95:1  AA PASS  AAA PASS  (large text)
#A07C8C on #FFFFFF: 3.65:1  AA PASS  AAA FAIL  (large text)
#765F6B on #FFFFFF: 5.80:1  AA PASS  AAA PASS  (large text)
#765F6B on #FFF0F5: 5.26:1  AA PASS  AAA PASS  (large text)
#C81A60 on #FFFFFF: 5.57:1  AA PASS  AAA PASS  (large text)
#C81A60 on #FFF0F5: 5.05:1  AA PASS  AAA PASS  (large text)
#C81A60 on #FFE0EC: 4.54:1  AA PASS  AAA PASS  (large text)
#C81A60 on #F5EEF1: 4.87:1  AA PASS  AAA PASS  (large text)
#C8322A on #FFFFFF: 5.32:1  AA PASS  AAA PASS  (large text)
#B87A00 on #FFFFFF: 3.61:1  AA PASS  AAA FAIL  (large text)
#FF4F8B on #FFFFFF: 3.11:1  AA PASS  AAA FAIL  (large text)

$ contrast.py "#9A5B00" "#FFF3D6" "#17734A" "#FFFFFF" "#17734A" "#FFF0F5" "#C8322A" "#FFFFFF" "#765F6B" "#F5EEF1" "#2B1F27" "#FFFFFF" "#C81A60" "#FFE0EC" "#2B1F27" "#FFD23F" "#FFFFFF" "#2B1F27" "#9A5B00" "#FFFFFF"
#9A5B00 on #FFF3D6: 4.92:1  AA PASS  AAA FAIL
#17734A on #FFFFFF: 5.85:1  AA PASS  AAA FAIL
#17734A on #FFF0F5: 5.31:1  AA PASS  AAA FAIL
#C8322A on #FFFFFF: 5.32:1  AA PASS  AAA FAIL
#765F6B on #F5EEF1: 5.08:1  AA PASS  AAA FAIL
#2B1F27 on #FFFFFF: 15.81:1  AA PASS  AAA PASS
#C81A60 on #FFE0EC: 4.54:1  AA PASS  AAA FAIL
#2B1F27 on #FFD23F: 10.95:1  AA PASS  AAA PASS
#FFFFFF on #2B1F27: 15.81:1  AA PASS  AAA PASS
#9A5B00 on #FFFFFF: 5.43:1  AA PASS  AAA FAIL

$ contrast.py --large "#FFFFFF" "#A07C8C" "#FFFFFF" "#765F6B" "#FFFFFF" "#C81A60" "#C8322A" "#FFFFFF" "#C81A60" "#FFFFFF" "#B87A00" "#FFF0F5" "#E5484D" "#FFFFFF" "#2E6FE0" "#FFFFFF" "#2B9A5E" "#FFFFFF" "#1D63D1" "#FFF0F5" "#9A5B00" "#FFF0F5" "#C8322A" "#FFF0F5" "#17734A" "#FFF0F5" "#FFD23F" "#2B1F27"
#FFFFFF on #A07C8C: 3.65:1  AA PASS  AAA FAIL  (large text)
#FFFFFF on #765F6B: 5.80:1  AA PASS  AAA PASS  (large text)
#FFFFFF on #C81A60: 5.57:1  AA PASS  AAA PASS  (large text)
#C8322A on #FFFFFF: 5.32:1  AA PASS  AAA PASS  (large text)
#C81A60 on #FFFFFF: 5.57:1  AA PASS  AAA PASS  (large text)
#B87A00 on #FFF0F5: 3.27:1  AA PASS  AAA FAIL  (large text)
#E5484D on #FFFFFF: 3.91:1  AA PASS  AAA FAIL  (large text)
#2E6FE0 on #FFFFFF: 4.70:1  AA PASS  AAA PASS  (large text)
#2B9A5E on #FFFFFF: 3.57:1  AA PASS  AAA FAIL  (large text)
#1D63D1 on #FFF0F5: 5.07:1  AA PASS  AAA PASS  (large text)
#9A5B00 on #FFF0F5: 4.92:1  AA PASS  AAA PASS  (large text)
#C8322A on #FFF0F5: 4.82:1  AA PASS  AAA PASS  (large text)
#17734A on #FFF0F5: 5.31:1  AA PASS  AAA PASS  (large text)
#FFD23F on #2B1F27: 10.95:1  AA PASS  AAA PASS  (large text)

$ contrast.py "#FFFFFF" "#9A5B00" "#765F6B" "#FFE0EC" "#6A5560" "#FFE0EC" "#17734A" "#E6F5EC" "#6A5560" "#FFF0F5"
#FFFFFF on #9A5B00: 5.43:1  AA PASS  AAA FAIL
#765F6B on #FFE0EC: 4.73:1  AA PASS  AAA FAIL
#6A5560 on #FFE0EC: 5.56:1  AA PASS  AAA FAIL
#17734A on #E6F5EC: 5.19:1  AA PASS  AAA FAIL
#6A5560 on #FFF0F5: 6.18:1  AA PASS  AAA FAIL

$ contrast.py --large "#C81A60" "#FFE0EC" "#2B9A5E" "#FFFFFF" "#E5484D" "#FFFFFF" "#A07C8C" "#F3DDE6" "#FF4F8B" "#FFFFFF"
#C81A60 on #FFE0EC: 4.54:1  AA PASS  AAA PASS  (large text)
#2B9A5E on #FFFFFF: 3.57:1  AA PASS  AAA FAIL  (large text)
#E5484D on #FFFFFF: 3.91:1  AA PASS  AAA FAIL  (large text)
#A07C8C on #F3DDE6: 2.83:1  AA FAIL  AAA FAIL  (large text)
#FF4F8B on #FFFFFF: 3.11:1  AA PASS  AAA FAIL  (large text)
```

說明：白對某色與某色對白的比值相同（對比是對稱的），所以「白字在 `#FF4F8B` 上」＝ 3.11、「白字在 `#9A5B00` 上」＝ 5.43，直接引用。
