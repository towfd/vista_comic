# 對比驗算報告

- 日期：2026-11-14
- 依據：專案根目錄 `DESIGN.md` 第 3 節、`docs/design/design-tokens.json`
- 工具：`python3 ~/.claude/skills/website-studio/scripts/contrast.py`（不加 `--large` 為一般文字門檻 4.5；加 `--large` 為大字／圖示／UI 元件門檻 3.0）
- 標準：一般文字 ≥ 4.5:1；大字（≥ 24px，或 ≥ 18.66px 粗體）、圖示、UI 元件外框、資訊圖形 ≥ 3:1

## 結論

- **使用中的組合全部通過。**
- 驗算時沒過或太勉強的 9 項都已處理（改色、改用法，或列為禁止組合），其中 3 項是 page-design-spec 原本的寫法，已在 DESIGN.md 15.6 換成通過的 token。見第 5 節。
- 停用狀態在 WCAG 不要求對比，但本系統的停用文字仍 ≥ 4.5（blush-strong 上 ink-faint 4.73）。

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

## 原始輸出

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
