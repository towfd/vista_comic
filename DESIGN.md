# DESIGN.md — vista_comic（網頁版）

> 本檔是 `web/` 唯一的設計依據，由 design-system-architect 維護。其他 agent 要改 token 請提出變更請求（token、現值、建議值、理由、影響範圍），由總控轉交；接受的變更寫進最後的 Changelog。
> 機器可讀版本：`docs/design/design-tokens.json`　對比驗算：`docs/design/contrast-report.md`
> 視覺依據：`docs/design/visual-decision.md`（第 2 輪方向 C 粉紅貼紙）、`docs/design/previews/round2/direction-c.html`
> 分工：各頁的版面、內容、狀態由 `docs/design/page-design-spec.md` 負責；本檔定 token、元件、規則。兩份不一致時，**顏色、字級、圓角、陰影、時長以本檔為準**（對照見第 15.6 節），版面與文字以 page-design-spec 為準。

---

## 1. Brand Identity

- **品牌一句話**：下班看越南文漫畫、順手把不懂的句子收成字卡的自用 App，打開就像翻自己的貼紙本。
- **個性關鍵字**：輕快、圓潤、封面優先、可愛但不幼稚、像自己的東西
- **語氣**：像自己的 App 在旁邊提醒你：短句、口語、具體，不說教、不撒嬌。
- **不是什麼**：
  - 不是暗色的閱讀器（只做亮色，手機開深色模式也一樣）。
  - 不是學習平台的儀表板（不做大數字統計卡、不做成就牆）。
  - 不是童書（不用表情符號、不到處歪斜、不用彩虹漸層）。
  - 不是 Webtoon 或 LINE 漫畫（借骨架，不借它們的綠色、商標與圖示）。

## 2. Design Principles

1. **封面是畫面上唯一的大面積彩色。** 介面只用白、淡粉和一個深粉，彩度留給封面。
   例：書庫格子裡的封面不加白邊、不加陰影；介面元件不用漸層。
2. **鮮粉是顏料，深粉是墨水。** `#FF4F8B` 只畫圖形（進度條、載入圓點、整句裡被挖空那個字的底線），而且只放白底；所有粉色的字、按鈕、外框都用 `#C81A60`。
   例：「繼續看」卡片的進度條用鮮粉；同一張卡片上的播放鈕用深粉。
3. **一個畫面只有一張貼紙。** 歪斜、白邊、黃色點綴都是「這裡最重要」的記號，一個畫面只用在一個焦點。
   例：書庫只有「繼續看」那張封面往左歪 4°；下面的兩欄封面全部擺正。
4. **粉圓沒有粗體，層級靠字級、顏色和越南文的粗細。** 中文永遠是 Huninn 的單一字重；要強調就放大、換深粉，或交給 Nunito 的數字和越南文去粗。
   例：「今天有 20 張要複習」：中文 Huninn 24px 墨色，「20」Nunito 900 28px 深粉，靠同一行的粗細對比就分出主次。
5. **漫畫頁不被設計。** 閱讀器只加最少、在任何漫畫圖上都看得清楚的東西。
   例：選中的泡泡框用「深粉／白／墨」三層框，不管底下是白色對話框、黑色網點還是粉紅背景都看得見。

## 3. Color Palette

只有亮色。`:root { color-scheme: light; }`，不寫 `prefers-color-scheme: dark` 和 `[data-theme="dark"]`。

### 原始色票（元件不可直接用）

| token | HEX | 備註 |
|---|---|---|
| palette.white | `#FFFFFF` | |
| palette.pink.50 | `#FFF0F5` | 預覽的 `--blush` |
| palette.pink.100 | `#FFE0EC` | 預覽的 `--blush-2` |
| palette.pink.400 | `#FF4F8B` | 鮮粉（預覽的 `--pink`，圖形用） |
| palette.pink.600 | `#C81A60` | 深粉（預覽的 `--pink-strong`） |
| palette.pink.700 | `#B01652` | hover |
| palette.pink.800 | `#9E1449` | pressed |
| palette.pink.900 | `#8F1244` | 按鈕厚邊 |
| palette.mauve.50 | `#F5EEF1` | 看過、封面失敗、漫畫頁佔位 |
| palette.mauve.100 | `#F3DDE6` | 預覽的 `--line` |
| palette.mauve.400 | `#A07C8C` | 控制項外框（新加） |
| palette.mauve.600 | `#765F6B` | 預覽的 `--text-3` |
| palette.mauve.700 | `#6A5560` | 預覽的 `--text-2` |
| palette.mauve.950 | `#2B1F27` | 預覽的 `--text`，墨色 |
| palette.sun.400 | `#FFD23F` | 黃色點綴 |
| palette.blue.50 / 500 / 600 | `#E8F0FD` / `#2E6FE0` / `#1D63D1` | 新卡 |
| palette.amber.50 / 600 / 700 | `#FFF3D6` / `#B87A00` / `#9A5B00` | 學習中（600 由 `#C98400` 調深） |
| palette.red.50 / 500 / 600 / 700 | `#FDECEA` / `#E5484D` / `#C8322A` / `#A82820` | 重新學習、錯誤 |
| palette.green.50 / 500 / 700 | `#E6F5EC` / `#2B9A5E` / `#17734A` | 間隔複習、成功 |

### 語意 token

「Tailwind」欄是 `web/src/style.css` `@theme` 的變數名（第 15 節），utility 就是去掉 `--color-` 的名字（`bg-paper`、`text-ink-soft`）。對比值全部出自 `contrast.py`。

| token | 值 | Tailwind | 用途 | 搭配文字 | 對比 |
|---|---|---|---|---|---|
| color.bg.canvas | `#FFFFFF` | `--color-paper` | 頁面底 | text.primary | 15.81 |
| color.bg.surface | `#FFFFFF` | `--color-paper` | 卡片、分頁列、頂端列、面板、提示框 | text.primary | 15.81 |
| color.bg.tint | `#FFF0F5` | `--color-blush` | 淡粉頂區、練習大卡、搜尋框、柔和按鈕、唯讀輸入框、寬螢幕閱讀欄兩側 | primary / secondary / muted / brand | 14.33 / 6.18 / 5.26 / 5.05 |
| color.bg.tint-strong | `#FFE0EC` | `--color-blush-strong` | 選中分頁的圖示底、按下、停用按鈕、「畢業」標籤、封面載入中 | primary / secondary / muted / brand | 12.90 / 5.56 / 4.73 / 4.54 |
| color.bg.muted | `#F5EEF1` | `--color-mist` | 看過的數字格、封面載入失敗、漫畫頁佔位 | primary / secondary / muted | 13.84 / 5.97 / 5.08 |
| color.bg.scrim | `#2B1F27` 45% | `--color-scrim` | 強制回應的面板後的遮罩（目前沒有頁面用到） | — | — |
| color.text.primary | `#2B1F27` | `--color-ink` | 主要文字、標題 | — | 白 15.81 |
| color.text.secondary | `#6A5560` | `--color-ink-soft` | 次要說明、中文翻譯、話數、文字按鈕 | — | 白 6.82 |
| color.text.muted | `#765F6B` | `--color-ink-faint` | 看過的數字、到期時間、未選分頁、提示字、停用文字 | — | 白 5.80 |
| color.text.brand | `#C81A60` | `--color-brand` | 粉色文字（數量、正在看的話數、強調數字） | — | 白 5.57 |
| color.text.inverse | `#FFFFFF` | `--color-white` | 實心底上的字 | — | — |
| color.brand.primary | `#C81A60` | `--color-brand` | 主要按鈕、選中、正在看的數字格、開關開、分段選擇的選中 | brand.on-primary | 5.57 |
| color.brand.primary-hover | `#B01652` | `--color-brand-hover` | 主要按鈕 hover（只在有滑鼠的裝置） | on-primary | 6.81 |
| color.brand.primary-pressed | `#9E1449` | `--color-brand-pressed` | 主要按鈕按下 | on-primary | 7.92 |
| color.brand.edge | `#8F1244` | `--color-brand-edge` | 按鈕下緣的厚邊 | — | 裝飾 |
| color.brand.on-primary | `#FFFFFF` | `--color-white` | 深粉上的字與圖示 | — | 5.57 |
| color.brand.vivid | `#FF4F8B` | `--color-brand-vivid` | 進度條填色、載入圓點、桌機 hover 外框、被挖空那個字的底線、停用但開著的開關軌道；**只放白底、不放字** | — | 白 3.11（圖形） |
| color.brand.wash | `#FF4F8B` 16% | `--color-brand-wash` | 閱讀器選中泡泡框的填色 | — | 疊在漫畫上，靠外框辨識 |
| color.accent.sun | `#FFD23F` | `--color-sun` | 徽章、「繼續看」「本話完」標籤、完成貼紙、正在看小圓點、載入圓點 | accent.on-sun | 10.95 |
| color.accent.on-sun | `#2B1F27` | `--color-ink` | 黃色上的字與圖示 | — | 10.95 |
| color.border.subtle | `#F3DDE6` | `--color-line` | 卡片框、數字格框、分隔線（裝飾，不負責辨識） | — | — |
| color.border.control | `#A07C8C` | `--color-line-strong` | 輸入框預設外框、開關關的軌道 | — | 白 3.65、淡粉 3.31 |
| color.border.ink | `#2B1F27` | `--color-ink` | 閱讀器提示框外框、浮在漫畫上的外圈 | — | — |
| color.focus.ring | `#C81A60` | `--color-brand` | focus-visible 外框 3px | — | 白 5.57、淡粉 5.05、淡粉 2 4.54、mist 4.87 |
| color.feedback.danger | `#C8322A` | `--color-danger` | 錯誤文字、無效輸入框外框、確認刪除按鈕底 | 白字 5.32 | 白 5.32、淡粉 4.82 |
| color.feedback.danger-hover | `#A82820` | `--color-danger-hover` | 危險按鈕 hover／按下 | 白字 7.02 | |
| color.feedback.danger-bg | `#FDECEA` | `--color-danger-tint` | 錯誤訊息框底 | danger 4.65 | |
| color.feedback.success | `#17734A` | `--color-success` | 「已儲存」「已加入」「正確」 | — | 白 5.85、淡粉 5.31 |
| color.feedback.success-bg | `#E6F5EC` | `--color-success-tint` | 成功訊息框、「已加入」膠囊 | success 5.19 | |
| color.feedback.warning | `#9A5B00` | `--color-warning` | 「已經收過了」等提醒、確認重設按鈕底 | 白字 5.43 | 白 5.43、淡粉 4.92 |
| color.feedback.warning-bg | `#FFF3D6` | `--color-warning-tint` | 提醒訊息框底 | warning 4.92 | |

### 字卡狀態色

每個狀態一定同時有文字（「新卡」「學習中 1/2」「重新學習 1/2」「間隔 7 天」），顏色只是輔助。

| 狀態 | 文字色 text（Tailwind） | 淡底 bg | 圖形色 graphic | 文字／白 | 文字／淡底 | 文字／淡粉 | 圖形／白 | 圖形／淡粉 |
|---|---|---|---|---|---|---|---|---|
| 新卡 new | `#1D63D1` `--color-st-new` | `#E8F0FD` `--color-st-new-tint` | `#2E6FE0` `--color-st-new-graphic` | 5.59 | 4.87 | 5.07 | 4.70 | 4.26 |
| 學習中 learning | `#9A5B00` `--color-st-learn` | `#FFF3D6` `--color-st-learn-tint` | `#B87A00` `--color-st-learn-graphic` | 5.43 | 4.92 | 4.92 | 3.61 | 3.27 |
| 重新學習 relearning | `#C8322A` `--color-st-relearn` | `#FDECEA` `--color-st-relearn-tint` | `#E5484D` `--color-st-relearn-graphic` | 5.32 | 4.65 | 4.82 | 3.91 | 3.55 |
| 間隔複習 review | `#17734A` `--color-st-review` | `#E6F5EC` `--color-st-review-tint` | `#2B9A5E` `--color-st-review-graphic` | 5.85 | 5.19 | 5.31 | 3.57 | 3.23 |

- **文字色**：狀態標籤的字、泡泡的數字與外框、「已到期」（用 relearning）。白底、自己的淡底、淡粉底都 ≥ 4.5。
- **圖形色**：比例條每一段、圖例圓點、作答欄的對錯外框（答對 review、答錯 relearning）。白底與淡粉底都 ≥ 3。
- 「答對」用 review、「答錯」用 relearning、「畢業」用 brand 字＋tint-strong 底（4.54）。
- 成功／錯誤／提醒訊息框和狀態色是同一組顏色（success = review、danger = relearning、warning = learning），所以語意 token 分開取名、色碼共用。
- 重新學習的紅 `#C8322A` 和深粉 `#C81A60` 色相接近；所以重新學習永遠帶文字，深粉永遠不拿來表示狀態。

### 不可用的組合（驗算沒過，禁止使用）

| 組合 | 對比 | 改用 |
|---|---|---|
| brand.vivid `#FF4F8B` 放在 tint `#FFF0F5` 上 | 2.82 | 淡粉底上的圖形改用 brand.primary（5.05） |
| brand.vivid 放在 tint-strong `#FFE0EC` 上（預覽的進度條、解析中進度條） | 2.54 | 進度條軌道改白底＋淡框（7.12）；不定進度條的滑塊改 brand（4.54） |
| 學習中原圖形色 `#C98400` 放在淡粉上 | 2.81 | 改為 `#B87A00`（3.27） |
| danger `#C8322A` 文字放在 tint-strong 上 | 4.34 | 不出現；錯誤一律用 danger-bg |
| 單一顏色的泡泡框外框疊在漫畫上 | 最低 1.28 | 三層框（7.17） |
| 輸入框用 `line` 當唯一外框 | 約 1.3 | 改 `line-strong`（3.65） |

## 4. Typography

### 字體

| 角色 | 字體 | 字重 | 來源 |
|---|---|---|---|
| 越南文、拉丁字、數字 | **Nunito** | 600（內文）、700（次要數字、原文）、800（書名、標題數字）、900（大數字、徽章） | Google Fonts，有越南文子集 |
| 中文 | **粉圓 Huninn** | 只有 400 一個字重 | Google Fonts（CJK 依 unicode-range 分片，只下載用到的字） |
| 退路 | PingFang TC → Heiti TC → Microsoft JhengHei → system-ui | | |

一條字體堆疊就夠：Nunito 沒有中文字，中文會自動落到 Huninn；同一行裡的數字與越南文會用 Nunito。

```
font-family: "Nunito", "Huninn", "PingFang TC", "Heiti TC", "Microsoft JhengHei", system-ui, sans-serif;
```

**載入**（放在 `web/index.html` 的 `<head>`）：

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Huninn&family=Nunito:wght@600;700;800;900&display=swap" />
```

- 不載入 Nunito 400／500。內文用 600：Huninn 的筆畫本身偏中等，Nunito 400 放在它旁邊會顯得太細（預覽也是這個效果：只載 600 以上，內文實際就是 600）。
- `html { font-synthesis-weight: none; }`：Huninn 沒有粗體，禁止瀏覽器假粗體。標題設 `font-extrabold` 時，同一行的中文維持原樣、數字與越南文變粗，這正是想要的效果。
- 中文不用斜體。
- `display=swap`：字型沒到前先用 PingFang TC 顯示，不留白。
- 實機要看一次越南文聲調：`Đ`、`ộ`、`ữ`、大寫 `THỨ`。

### 粉圓只有一個字重：中文層級怎麼分

1. **字級**：相鄰兩層至少差一階（28 → 24 → 20 → 16 → 14 → 13），不要在同一區塊用 16 和 18 分層。
2. **顏色**：主次靠 `ink` → `ink-soft` 兩階；`ink-faint` 只給「看過、已過去、提示字」這類刻意退後的資訊，不當內文。
3. **Nunito 的粗**：同一行有數字或越南文時，讓它們用 800／900 扛重量（「今天有 **20** 張」、「看到第 **54** 話」）。
4. **深粉**：一段標題裡最重要的數字可以換 `text-brand`；一個畫面最多一處。
5. **位置與留白**：區塊標題上方 22、下方 12，靠節奏分組，不靠加粗或底線。

### Type scale（手機為基準）

| token | Tailwind | size | line-height | 字重（Nunito） | letter-spacing | 用途 |
|---|---|---|---|---|---|---|
| type.display | `text-display` | 34px | 1.1 | 900 | 0 | 練習泡泡最大的數字 |
| type.page | `text-page` | 28px（≥ 768：32px） | 1.3 | 800 | 0 | 頁名：書庫、字卡庫、今天、設定；「今天有 **20** 張」裡的數字 |
| type.headline | `text-headline` | 24px | 1.4 | 800 | 0 | 「今天有 N 張要複習」「今天做完了」「這一輪做完了」、單張字卡的原文、填空題句子與整句題（加 `leading-relaxed`）、回饋的答案字、泡泡第二大數字 |
| type.heading | `text-heading` | 20px | 1.35 | 800 | 0 | 區塊標題、面板標題、作品頁書名、字卡庫的原文、錯誤與空狀態標題、作答欄文字、判定「正確」「不對」 |
| type.label | `text-label` | 18px | 1.4 | 800 | 0 | 大按鈕文字、數字格的數字、表單欄位標籤、中文提示內容、整句（回饋） |
| type.body | `text-body` | 16px | 1.7 | 600 | 0 | 內文、輸入框文字、訊息框、提示框譯文；書名用 800 並改 `leading-title`（1.35） |
| type.meta | `text-meta` | 14px | 1.6 | 600 | 0 | 次要說明、話數、中文翻譯、數量標籤、設定膠囊鈕 |
| type.caption | `text-caption` | 13px | 1.5 | 700 | 0 | 狀態標籤、徽章、分頁列文字、到期時間、圖例、欄位說明、小標 |

- **最小字級 13px**。預覽與 page-design-spec 中 12px 的字（分頁列、「中文提示」小標、閱讀器話數、詞性標籤、字數計數、徽章）一律用 13px。
- 數字一律 `tabular-nums`（數字格、徽章、還剩 N 張、54 / 149）。數字格話數 ≥ 5 個字元（`1162.5`）時用 `text-meta`（14）＋`font-extrabold`。
- 越南文大寫（THỨ HAI…）的聲調會疊高，`leading-title` 1.35 是下限，不要再壓。
- 一行字數：內文欄寬 ≤ 40rem（中文約 36 字、越南文約 70 字元）。
- **≥ 768px**：`--text-page` 改 32px；`body` 字重 600 → 700（Nunito 加粗一級；Huninn 不變）。其他字級不變。
- **輸入框字級不可小於 16px**，否則 iOS 聚焦時會放大整頁。
- 不用全大寫小標、不加字距、不用中點串接資訊。

## 5. Spacing

沿用 Tailwind v4 的 `--spacing: 0.25rem`（4px 基準），utility 的數字 × 4 = px。

| token | px | Tailwind |
|---|---|---|
| space.1 | 4 | `1` |
| space.2 | 8 | `2` |
| space.2-5 | 10 | `2.5` |
| space.3 | 12 | `3` |
| space.3-5 | 14 | `3.5` |
| space.4 | 16 | `4` |
| space.4-5 | 18 | `4.5` |
| space.5 | 20 | `5` |
| space.5-5 | 22 | `5.5` |
| space.6 | 24 | `6` |
| space.7 | 28 | `7` |
| space.8 | 32 | `8` |
| space.12 | 48 | `12` |
| space.16 | 64 | `16` |
| space.24 | 96 | `24` |

10、14、18、22 是預覽沿用的半格，page-design-spec 會用到，可以用；不要再加其他數值（6 只用在圖示與文字之間，`gap-1.5`）。

規則：
- **元件內**：8–16（`gap-2`、`p-3`、`px-4`）；圖示與文字之間 6–8。
- **同類元件之間**：10–12（字卡 `gap-2.5`、數字格 `gap-2.5`、按鈕列 `gap-3`）；封面格 `gap-x-3.5 gap-y-5`。
- **卡與卡之間**：18–24。
- **區塊之間**：區塊標題 `pt-5.5 pb-3`；表單欄位區塊之間 28（`space-y-7`）。
- **頁面左右**：手機 16（`px-4`）；頁名列左 20、右 16（右邊是 44px 圓鈕，視覺上對齊）。
- **頁面下緣**：有分頁列的頁面，最後一個元素下面留 分頁列 52 + safe-area + 24：`pb-[calc(4.75rem+env(safe-area-inset-bottom))]`。

## 6. Layout and Grid

| 斷點 | 寬度 | 書庫封面欄數 | 數字格 | 頁面左右 | 備註 |
|---|---|---|---|---|---|
| mobile | < 640 | 2 | `grid-cols-5` | 16 | 主要情境：iPhone 直式 |
| sm | ≥ 640 | 3 | `grid-cols-[repeat(auto-fill,minmax(4.5rem,1fr))]` | 16 | 繼續看卡最寬 560 |
| md | ≥ 768 | 3 | 同上 | 24 | 頁名 32、內文字重 700 |
| lg | ≥ 1024 | 4 | 同上 | 24 | 章節頁頂區改左右排；閱讀欄兩側 `bg-blush` |
| xl | ≥ 1280 | 5 | 同上 | 24 | |
| dock | ≥ 1344 | — | — | — | 收卡、深入查詢面板靠在閱讀欄右側（既有） |

- 斷點沿用 Tailwind 預設（sm 40rem、md 48rem、lg 64rem、xl 80rem、2xl 96rem）與既有的 `dock: 84rem`。
- **版寬 token**（`max-w-*`）：

| token | 值 | Tailwind | 用在 |
|---|---|---|---|
| container.narrow | 560 | `max-w-narrow` | 練習總覽、練習設定 |
| container.page | 640 | `max-w-page` | 單張字卡、練習中、字卡庫 |
| container.wide | 760 | `max-w-wide` | 章節列表 |
| container.reader | 800 | `max-w-reader` | 閱讀欄（原本的 `max-w-[800px]`）、手機收卡面板內容 |
| container.shelf | 1080 | `max-w-shelf` | 書庫 |
| container.tabs | 420 | `max-w-tabs` | 寬螢幕分頁列的三格 |

- 對齊：頁名、清單、卡片內容都**靠左**；只有章節頁頂區（手機）、空狀態、錯誤狀態、完成頁**置中**。
- 淡粉頂區的底色延伸到全寬，內容依上表置中。
- 垂直節奏：頁名列 → 淡粉頂區或主卡 → 區塊標題 → 內容。

### Radius（三種非零圓角＋全圓）

| token | 值 | Tailwind | 用在 |
|---|---|---|---|
| radius.sm | 16px | `rounded-tile` | 數字格、貼紙封面外框、訊息框、提示小卡、訊息框裡的白色小框、閱讀器泡泡框、淡粉卡裡的白色單列 |
| radius.md | 20px | `rounded-card` | 書庫封面、字卡、白卡（含繼續看卡）、輸入框、閱讀器提示框、寬螢幕側邊面板 |
| radius.lg | 28px | `rounded-panel` | 淡粉頂區下緣、淡粉大卡、分頁列與面板上緣、閱讀器頂端列與章節頁小頂列下緣 |
| radius.full | 9999px | `rounded-full` | 按鈕、狀態標籤、徽章、搜尋框、開關、進度條、分段選擇、圓形圖示鈕、「已加入」膠囊 |

層級規則：越大的面越圓；**封面 ≤ 20、卡片 20、面板 28、能按的東西全圓**（數字格例外，見第 12 節）。貼紙封面的外框 16、白邊 4px，裡面的圖片自然是 12，不用另外設。

### Elevation（三層）

| token | Tailwind | 值 | 用途 |
|---|---|---|---|
| shadow.raised（第 1 層） | `shadow-raised` | `0 10px 22px -10px rgb(120 30 70 / .55)` | 貼紙封面 |
| shadow.chrome（第 2 層） | `shadow-chrome-up`／`shadow-chrome-down` | 1px `line` 框線＋往外 20–24px 淡粉陰影 | 分頁列與手機面板（往上）、閱讀器頂端列與章節頁小頂列（往下） |
| shadow.overlay（第 3 層） | `shadow-overlay` | `0 18px 40px -12px rgb(120 30 70 / .45)` | 閱讀器提示框、寬螢幕的側邊面板 |

不是高度層級、但也用 box-shadow 實作的：
- `shadow-edge`／`shadow-edge-sm`／`shadow-edge-pressed`：主要按鈕、播放鈕、正在看的數字格下緣的深粉厚邊（像可以按下去的實體按鈕）。
- `shadow-float`：浮在漫畫上的控制項的白邊＋墨線＋貼紙陰影。
- `shadow-ring-selected`／`shadow-ring-hint`／`shadow-ring-hint-plain`：閱讀器泡泡框（7.17）。
- 卡片一律不加陰影；白卡靠 `inset-ring-2 inset-ring-line`，淡粉卡靠底色。

## 7. Component Guidelines

通用狀態規則：
- **hover** 只在有滑鼠的裝置出現（Tailwind v4 的 `hover:` 本來就包在 `@media (hover: hover)` 裡），不能只靠 hover 傳達資訊。
- **focus-visible**：全站統一 `outline: 3px solid var(--color-brand); outline-offset: 2px`（寫在 base，元件不用各自寫；圓角跟著元件）。疊在漫畫上的元件改用 `shadow-ring-selected` 的三層框。
- **active（按下）**：iOS Safari 預設不觸發 `:active`，要在 `main.ts` 加一行 `document.addEventListener('touchstart', () => {}, { passive: true })`。
- **disabled**：不用整顆 `opacity`（半透明的粉看起來像壞掉），改用停用色：`bg-blush-strong text-ink-faint`（4.73），移除厚邊與按下效果，`cursor-not-allowed`。
- **loading（處理中）**：按鈕寬度不變，文字換成同一個動詞的進行式（「儲存中…」），`aria-busy="true"`，不接受第二次按下；底色維持（不是停用），不加轉圈。
- **error**：外框或文字變 danger，旁邊一定有文字說明怎麼修。

### 7.1 Button

| 變體 | 尺寸 | default | hover | focus-visible | active（按下） | disabled | loading |
|---|---|---|---|---|---|---|---|
| primary | lg 56／md 44／sm 36 | `bg-brand text-white`＋lg `shadow-edge`、md/sm `shadow-edge-sm` | `bg-brand-hover` | 3px brand 外框 | 下沉 `translate-y-0.75`（sm `translate-y-0.5`）＋`shadow-edge-pressed`＋`bg-brand-pressed` | `bg-blush-strong text-ink-faint shadow-none` | 「…中…」，底色不變 |
| secondary | 跟著旁邊的主要按鈕（56／44／36） | `bg-paper text-ink inset-ring-2 inset-ring-line` | `bg-blush` | 同上 | `bg-blush` | `text-ink-faint` | 同上 |
| soft | 36（觸控區補到 44） | `bg-blush text-brand` | `bg-blush-strong` | 同上 | `bg-blush-strong` | `bg-mist text-ink-faint` | 同上 |
| text | 高 44、左右 8 | `text-ink-soft` 無底 | `bg-blush` | 同上 | `bg-blush` | `text-ink-faint` | — |
| danger | md 44 | `bg-danger text-white` | `bg-danger-hover` | 同上 | `bg-danger-hover` | 停用色 | 同上 |
| warning | md 44 | `bg-warning text-white`（5.43） | 底不變 | 同上 | `active:scale-98`（減少動態時不縮） | 停用色 | 同上 |

- 文字：lg 用 `text-label`（18）、md 用 `text-body font-extrabold`、sm 用 `text-meta font-extrabold`。中文字在 Huninn 不會變粗，越南文與數字會。
- 全部 `rounded-full`。lg 在手機上 `w-full`（最寬 360 的地方由 page-design-spec 指定）。
- 一個畫面只有一顆 primary lg（「繼續閱讀」「開始複習」「送出」「下一題」「儲存」「回到總覽」）。
- 兩段文字的按鈕（「繼續閱讀」＋「第 54 話」、「下一話」＋「第 55 話」）：第二段 `font-bold text-meta opacity-90`（白字在深粉上 90% 仍 ≥ 4.5），間距 10，不用中點。
- **次要按鈕當危險動作**（「刪除卡片」）：secondary 的字改 `text-danger`；確認中換成 danger 實心。「重設為新卡」確認中換成 warning 實心。
- **有改動才亮的儲存鈕**（單張字卡）：沒改動 secondary＋disabled；有改動換成 primary md。
- 圓形圖示鈕（返回、重新整理、結束）：`size-11 rounded-full grid place-items-center`；白底版 `bg-paper text-ink-soft inset-ring-2 inset-ring-line`、淡粉版 `bg-blush text-ink-soft`。必須有 `aria-label`。**一律 44**，閱讀器頂端列與章節頁小頂列也是（預覽的 40 改 44）。
- 播放鈕：`size-13 rounded-full bg-brand text-white shadow-edge-sm grid place-items-center`。
- `prefers-reduced-motion`：按下不位移、不縮放，只換成 pressed 底色（`motion-reduce:active:translate-y-0 motion-reduce:active:scale-100`）。
- 觸控區不足 44 的（sm 36、soft 36）：`relative before:absolute before:-inset-1 before:content-['']` 補到 44。

### 7.2 Link

- 段落裡的文字連結（「到字卡庫修改」「到那張卡片」「這張卡片有問題？到字卡庫修改」）：`text-ink-soft underline decoration-2 decoration-line-strong underline-offset-4`；hover 時 `decoration-brand`；`text-meta`。
- 開新分頁的連結：文字後面接一個 `↗` 圖示 SVG（`aria-hidden`），連結的 `aria-label` 補「（開新分頁）」。不用 `→` 字元。
- 看起來像按鈕的連結（RouterLink）照 Button 的變體寫。

### 7.3 Navigation：底部分頁列

- 只有書庫、字卡庫、練習總覽三頁顯示（page-design-spec 1.5）。
- 容器：`fixed inset-x-0 bottom-0 z-30 rounded-t-panel bg-paper pb-[env(safe-area-inset-bottom)] shadow-chrome-up`；內層 `mx-auto grid max-w-tabs grid-cols-3`。
- 每格：`relative flex h-13 flex-col items-center justify-center gap-0.5 text-caption text-ink-faint`（52px 高、約 130px 寬，整格可點）。
- 圖示 24、2px 圓頭線條；外包 `grid h-7 w-14 place-items-center rounded-full`。
- 選中：整格 `text-brand`、圖示底 `bg-blush-strong`、`aria-current="page"`。選中有圖示底塊＋顏色兩種差異，不只靠顏色。
- 按下：圖示底先出現 `bg-blush`，`active:scale-92`（`duration-120`）。
- 切換分頁不做動畫。

### 7.4 Badge

| 變體 | 樣式 | 用途 |
|---|---|---|
| 計數徽章 | `absolute -top-1 left-[calc(50%+10px)] h-5 min-w-5.5 rounded-full bg-sun px-1.5 text-caption font-black leading-5 text-ink tabular-nums ring-2 ring-paper` | 練習分頁的 `standing.remaining`；0 或抓不到時不顯示 |
| 數量標籤 | `rounded-full bg-blush px-2.5 text-meta text-brand tabular-nums` | 「8 部」「共 316 張」「171」 |
| 點綴標籤 | `rounded-full bg-sun px-2.5 text-caption text-ink` | 「繼續看」；「本話完」加 `-rotate-3` |
| 小標籤 | `rounded-full bg-blush px-2 text-caption text-ink-soft` | 深入查詢裡的詞性 |

數字變化時 `animate-bump`（第 9 節）。徽章的數字要在分頁的 `aria-label` 裡讀出來（「N 張等待複習」，現有）。

### 7.5 Card

| 變體 | 樣式 | 用途 |
|---|---|---|
| 白卡 | `rounded-card bg-paper inset-ring-2 inset-ring-line` | 字卡、今天做完了的字卡分布 |
| 淡粉大卡 | `rounded-panel bg-blush px-5 pt-5.5 pb-6` | 練習總覽「今天」、題目卡、玩法、「這一輪做完了」結果 |
| 繼續看卡 | `rounded-card bg-paper p-4 grid grid-cols-[6rem_1fr] gap-4` | 書庫頂區裡唯一的一張 |
| 書架封面 | `relative aspect-3/4 overflow-hidden rounded-card bg-blush-strong`＋`<img class="size-full object-cover object-top">`＋`after:absolute after:inset-0 after:rounded-card after:inset-ring-1 after:inset-ring-ink/8` | 書庫兩欄封面；不歪、不加白邊、不加陰影 |
| 貼紙封面 | `aspect-3/4 overflow-hidden rounded-tile border-4 border-paper bg-blush-strong shadow-raised -rotate-4 backface-hidden`（章節頁 `rotate-3`） | 只用在「繼續看」與章節頁頂區 |

- 能點的卡片整張是一個連結。字卡按下 `active:bg-blush`；封面按下 `active:scale-97`。不做 hover 浮起；桌機 hover 時封面外框 `hover:outline-2 hover:outline-brand-vivid`（白底 3.11）。
- 封面載入中底色 `bg-blush-strong`，載入完淡入（`duration-200`）；失敗時 `bg-mist`＋中間 32px 書本線條圖示 `text-ink-faint`（5.08）。
- 卡片標題（越南文）`text-heading`；中文翻譯 `text-meta text-ink-soft`；截斷用 `line-clamp-2`／`line-clamp-3`。

### 7.6 清單列（List row）

- 組：放在白卡或淡粉卡裡，列之間 `divide-y divide-line`（1px）。
- 列：`flex min-h-13 items-center gap-3 py-2.5 text-body`；左邊標題 `text-ink`、右邊數值 `ml-auto font-extrabold tabular-nums`。
- 開關列：整列是 `role="switch"` 的按鈕（7.9）。
- 淡粉卡裡的單列（「明天到期 9 張」）：`flex items-center gap-2 rounded-tile bg-paper px-3.5 py-2 text-body text-ink-soft`，左邊圖示 `text-brand`，數字 `ml-auto text-label font-black text-ink`。
- 深入查詢的單字列：`py-2.5`，右側 soft 按鈕「加入」。
- 可點的列：`active:bg-blush`；右邊不加箭頭字元。

### 7.7 數字格（章節）

- 容器：`<ol class="grid grid-cols-5 gap-2.5">`（≥ 640 改 auto-fill，見第 6 節）。
- 格子（連結）：`relative grid h-13 place-items-center rounded-tile text-label font-extrabold tabular-nums transition-transform duration-120 ease-standard`（52 高、390 寬時約 63 寬）。

| 狀態 | 樣式 | 對比 |
|---|---|---|
| 還沒看（含看到一半但不是正在看） | `bg-paper text-ink inset-ring-2 inset-ring-line` | 15.81 |
| 看過 | `bg-mist text-ink-faint font-bold` | 5.08 |
| 正在看 | `bg-brand text-white shadow-edge-sm`＋右上黃點 `after:absolute after:-top-1 after:-right-1 after:size-3.5 after:rounded-full after:bg-sun after:ring-2 after:ring-paper` | 5.57 |
| 按下 | `active:scale-94`；減少動態時改 `active:bg-blush` | — |
| hover（桌機） | `hover:outline-2 hover:outline-brand-vivid` | 3.11 |
| focus-visible | 全站外框 | 5.57 |

- 「看過」與「還沒看」除了顏色還差在「實心底 vs 外框」與字重；每格 `aria-label` 寫狀態（page-design-spec 2.2）。
- 圖例的小方塊：`size-3 rounded-[4px]`，三種狀態同上。
- 打開時捲到正在看：瞬間定位，不做平滑捲動（規則見 page-design-spec 2.2）。

### 7.8 Input / Textarea / Search

| 狀態 | 文字輸入框、textarea |
|---|---|
| default | `rounded-card bg-paper px-4 py-3 text-body text-ink inset-ring-2 inset-ring-line-strong`（3.65） |
| placeholder | `placeholder:text-ink-faint`（5.80）；placeholder 不能取代 label |
| hover | 不變 |
| focus | `focus:inset-ring-3 focus:inset-ring-brand focus-visible:outline-none`（變色＋變粗兩種差異） |
| read-only | `read-only:bg-blush read-only:text-ink-soft read-only:inset-ring-line` |
| disabled | `disabled:bg-mist disabled:text-ink-faint disabled:inset-ring-line` |
| error | `aria-[invalid=true]:inset-ring-3 aria-[invalid=true]:inset-ring-danger`＋下方 `text-meta text-danger` 說明怎麼修 |

- **作答欄**：`text-heading font-extrabold`、`lang="vi"`、預設 `inset-ring-3 inset-ring-brand`（一進題目就是聚焦狀態）；回饋時變唯讀，外框換 `inset-ring-st-review-graphic`（答對）或 `inset-ring-st-relearn-graphic`（答錯），底 `bg-blush`。
- textarea `resize-none`，自動長高（沿用）。
- label 在輸入框上方：`text-label text-ink`（表單）或 `text-caption text-ink-soft`（收卡面板）；說明文字 `text-caption text-ink-soft`，在 label 下、框上。
- 字數計數：`text-caption text-ink-faint text-right`。
- **搜尋框**：`flex h-12 items-center gap-2 rounded-full bg-blush px-4 text-body`，放大鏡 `size-5 text-ink-faint`；`focus-within:inset-ring-3 focus-within:inset-ring-brand`。不畫 ≥ 3:1 的外框，見第 12 節。

### 7.9 Switch（開關）

- 整列是 `<button role="switch" :aria-checked>`，標籤在左、軌道在右，整列 `min-h-13`（或膠囊版 `h-9`，觸控區補到 44）。
- 軌道：`relative h-7 w-11 rounded-full transition-colors duration-120`；關 `bg-line-strong`（白鈕 3.65、對白 3.65、對淡粉 3.31）、開 `bg-brand`（5.57）。
- 圓鈕：`absolute top-0.75 left-0.75 size-5.5 rounded-full bg-white transition-[translate] duration-120 ease-standard`；開時 `translate-x-4`。
- disabled（玩法只剩一個開著時，那一個不能關）：開著的軌道改 `bg-brand-vivid`（白鈕 3.11，仍看得出是開），標籤 `text-ink-faint`，`cursor-not-allowed`；旁邊說明為什麼不能關（現有字）。
- 閱讀器「標示」膠囊：`inline-flex h-9 items-center gap-2 rounded-full bg-paper px-3 text-meta text-ink-soft shadow-float`，裡面同一個開關。

### 7.10 狀態標籤（Chip）

- `inline-flex h-6.5 items-center rounded-full px-2.5 text-caption`＋狀態色：
  - 新卡 `bg-st-new-tint text-st-new`、學習中 `bg-st-learn-tint text-st-learn`、重新學習 `bg-st-relearn-tint text-st-relearn`、間隔 `bg-st-review-tint text-st-review`。
- 結果膠囊（答對／答錯／畢業）：`inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-meta`，數字 `text-label font-black`。畢業 `bg-blush-strong text-brand`。
- 不可點。

### 7.11 分段選擇（Segmented control）

- 軌道：`inline-flex rounded-full bg-blush p-1`。
- 選項：`h-9 rounded-full px-4 text-meta text-ink-soft`（深入查詢的模型選擇可用 `px-3`）；選中 `bg-brand text-white`。整個軌道 44 高。
- 語意：互斥選擇用 `role="radiogroup"`／`role="radio"`＋`aria-checked`；切換型用 `aria-pressed`（沿用現有）。
- 處理中整組 `disabled`，文字 `text-ink-faint`。

### 7.12 Progress（進度條）

- **確定進度**：軌道 `h-2.5 overflow-hidden rounded-full bg-paper inset-ring-2 inset-ring-line`（練習中 `h-3`）；填色 `h-full rounded-full bg-brand-vivid transition-[width] duration-200 ease-standard`（對白色軌道 3.11）。
  - 放在淡粉底上時填色改 `bg-brand`（鮮粉在淡粉上 2.82）。
  - 一定搭配文字數字（「54 / 149」「還剩 12 張」）；`role="progressbar"`＋`aria-valuenow`／`aria-valuemax`／`aria-label`。
- **不定進度**（深入查詢解析中）：軌道 `h-1 overflow-hidden rounded-full bg-blush-strong`；滑塊 30% 寬 `bg-brand`（4.54）來回滑 1.4s；減少動態時靜止。旁邊一定有「解析中… N 秒」。
- **比例條**（字卡分布）：`flex h-4 gap-0.75`，每段 `min-w-2 rounded-full bg-st-*-graphic`，`role="img"`＋完整數字的 `aria-label`。

### 7.13 Panel／面板

| 變體 | 樣式 | 用途 |
|---|---|---|
| 手機底部面板（不擋閱讀） | `fixed inset-x-0 bottom-0 z-40 max-h-[70dvh] overflow-y-auto rounded-t-panel bg-paper px-4 pt-5 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-chrome-up`；內容 `mx-auto max-w-reader` | 收卡、深入查詢 |
| 寬螢幕側邊面板 | `dock:rounded-card dock:shadow-overlay dock:inset-ring-2 dock:inset-ring-line`，位置沿用現有 `dock:` 規則 | 同上 |
| 強制面板 | 同手機底部面板，背後 `fixed inset-0 bg-scrim` | 目前沒有；之後若有需要回答的問題才用 |

- 標題列：左 `text-heading`、右「收合」／「關閉」secondary sm；下一行 `text-caption text-ink-soft`（第 12 頁）。
- 開啟：從下往上 `duration-280 ease-standard`；收起 `duration-200`。不畫拖曳把手（沒有拖曳功能）。
- 開啟後焦點移到第一個輸入框（沿用）；Esc 收合。

### 7.14 訊息框（成功／錯誤／提醒）

| 種類 | 樣式 | role |
|---|---|---|
| 成功 | `rounded-tile bg-success-tint px-3.5 py-3 text-body text-success` | `status` |
| 錯誤 | `rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger` | `alert` |
| 提醒 | `rounded-tile bg-warning-tint px-3.5 py-3 text-body text-warning` | `alert` 或 `status` |

- 框裡要再放另一張卡的內容：`mt-2 rounded-tile bg-paper p-3`，原文 `text-body font-bold text-ink lang="vi"`、譯文 `text-meta text-ink-soft`。
- 成功的短訊（「已儲存」）可用膠囊：`inline-flex h-9 items-center gap-1.5 rounded-full bg-success-tint px-3.5 text-meta text-success`，前面打勾圖示。

### 7.15 Empty state／Error state

同一個骨架（page-design-spec 1.4）：

- 置中欄，上方留 64：貼紙 → 標題 `text-heading text-ink`（`mt-4`）→ 說明 `text-meta text-ink-soft max-w-[22em]`（`mt-1.5`）→ 按鈕列 `mt-6 flex gap-3`（primary md＋secondary md）。
- **錯誤貼紙**：`grid size-18 place-items-center rounded-full bg-blush-strong text-brand -rotate-6 ring-5 ring-paper outline-2 outline-blush-strong`，圖示 32、2px 線條。
- **空狀態貼紙**：同上，改 `bg-sun text-ink -rotate-8`。
- 錯誤的標題說發生什麼、說明說怎麼修；空狀態說下一步。一個畫面一定有一顆 primary（只剩次要動作時把它升成 primary）。
- 漫畫頁載入失敗：保留頁面比例的 `bg-mist` 方塊，中間 `text-meta text-ink-soft`「第 n 頁載入失敗」＋secondary md「重試」。

### 7.16 Loading（載入中）

- **共用載入指示**：內容區上方 96、置中；三顆 `size-2 rounded-full` 圓點（`bg-brand-vivid`、`bg-sun`、`bg-brand`）依序上下跳（900ms 循環，`motion-safe:` 才動）；下面一行 `text-meta text-ink-faint`「載入中…」或該頁原本的字。圓點是裝飾，資訊在文字。
- **有快取資料時不顯示**（沿用 stale-while-revalidate），只有第一次沒有資料時才出現。
- 章節頁頂區骨架：返回鍵可用，封面位置 `bg-blush-strong` 色塊。
- 漫畫頁：維持現有 900:1549 佔位，底色 `bg-mist`，不放轉圈。
- 重新整理鈕處理中：圖示 `motion-safe:animate-spin`，減少動態時 `opacity-50`；按鈕停用。
- 按鈕處理中：見通用規則。

### 7.17 閱讀器專用

**頂端列**（行為沿用 `reader/headerReveal.ts`）：
- `sticky top-[env(safe-area-inset-top)] z-10 rounded-b-panel bg-paper shadow-chrome-down transition-transform duration-200 ease-standard`；藏起時 `-translate-y-[calc(100%+1rem)]`（連陰影一起移出畫面）。
- 底色**不透明**。
- 內容：淡粉圓鈕返回（44）→ 書名 `text-body font-extrabold truncate leading-title`＋話數 `text-caption text-ink-soft` → 右側留白給浮動控制項。

**浮在漫畫上的控制項**（固定在右上角的「標示」與「＋收卡」，頂端列藏起時也留著）：一律加 `shadow-float`（白 2px＋墨 1px＋貼紙陰影），不管底下是什麼顏色都有一圈看得見。「＋收卡」是 primary sm，但浮動時用 `shadow-float` 取代 `shadow-edge-sm`（白邊會蓋住厚邊），按下只換 `bg-brand-pressed`、不位移。

**泡泡框**（`ReaderPage.vue` 的 OCR 框）：

| 狀態 | 樣式 | 為什麼 |
|---|---|---|
| 有翻譯，標示開 | `rounded-tile shadow-ring-hint`（深粉 1.5／白 1／墨 1） | 三層裡至少一層對任何底色 ≥ 3:1 |
| 還沒翻譯，標示開 | `rounded-tile shadow-ring-hint-plain`（白 1／墨 1，沒有粉色） | 和有翻譯的差在「有沒有粉色那圈」，不只是換色 |
| 標示關 | 無外框，仍可點 | |
| hover（滑鼠） | 再加 `bg-brand-wash` | |
| 選中 | `rounded-tile bg-brand-wash shadow-ring-selected`（深粉 3／白 2／墨 1）；標示關也顯示 | 比提示粗一倍以上，且有填色 |
| focus-visible | 同選中 | |

驗算見 contrast-report 第 4 節：深粉在中灰只有 1.41、白在粉紅只有 2.16，單色框做不到「任何漫畫上都看得清楚」，所以一定三層一起用。

**提示框**（點泡泡後的翻譯框）：白底墨框，像漫畫的對話框。
- `absolute z-10 my-3 w-72 max-w-[90%] rounded-card border-2 border-ink bg-paper p-3.5 shadow-overlay`；定位沿用 `popoverStyle`。
- 譯文 `text-body text-ink`；分隔 `my-2 border-t border-line`；原文 `text-meta font-bold text-ink-soft lang="vi"`。
- 沒有翻譯時「（這句還沒有翻譯）」`text-ink-faint`。
- 動作列 `mt-3 flex justify-end gap-2`：secondary sm「深入查詢」、primary sm「加入句子」。
- 出現：`opacity 0→1`＋`scale .96→1`，`duration-120 ease-standard`。

**「已加入」膠囊**（收卡成功後 4 秒）：成功膠囊（7.14）加 `max-w-64 truncate shadow-float`，原文 `lang="vi"`；`role="status"`。

**寬螢幕**：≥ 1024 閱讀欄兩側 `bg-blush`。

**章末**：「本話完」點綴標籤 `-rotate-3`；「下一話」primary lg（最寬 360）；「回到章節列表」text 按鈕。

## 8. Responsive Guidelines

- **色彩模式**：只有亮色。`:root { color-scheme: light; }`＋`<meta name="color-scheme" content="light">`；不寫任何暗色樣式。手機開深色模式時，表單控制項、捲軸也維持亮色。
- **iPhone 主畫面 PWA**（主要情境）：
  - `index.html`：`theme-color` 改 `#FFFFFF`；`apple-mobile-web-app-status-bar-style` 從 `black-translucent` 改成 **`default`**（black-translucent 的時鐘永遠是白字，在白底上看不到）。改了之後如果狀態列還是白字，要把主畫面圖示刪掉重新加入。
  - `manifest.webmanifest`：`background_color` 與 `theme_color` 都改 `#FFFFFF`。
  - safe-area 的處理全部保留：`viewport-fit=cover`、`body` 的四邊 `env(safe-area-inset-*)`、狀態列下的固定色條（色條改 `--color-paper`）。改成 `default` 後直式的上方 inset 會是 0，色條自然沒有高度；橫式與一般瀏覽器分頁仍照舊。
  - 既有的 `overscroll-behavior: none`、`-webkit-tap-highlight-color: transparent`、`text-size-adjust`、圖片長按、按鈕不可選取，全部保留。
- **字重**：≥ 768px 時 Nunito 內文 600 → 700；Huninn 不變。
- **手機導覽**：底部分頁列只在三個分頁的第一頁（7.3）；子頁用左上圓形返回鈕。
- **觸控區** ≥ 44×44px：圓鈕 `size-11`；36 高的按鈕用 `before:-inset-1` 補足；數字格 52 高；分頁格 52 高；開關整列可點。
- **各斷點的版面**：見第 6 節。寬螢幕不改成側邊欄，分頁列維持在底部（page-design-spec 6.1）。
- **閱讀器**：閱讀欄 800 上限、窄頁不放大（沿用）；≥ dock 面板改到閱讀欄旁邊（沿用）。

## 9. Interaction and Motion

| token | 值 | Tailwind |
|---|---|---|
| duration.fast | 120ms | `duration-120` |
| duration.base | 200ms | `duration-200` |
| duration.slow | 280ms | `duration-280` |
| duration.pop | 300ms | `animate-pop` 內建 |
| easing.standard | `cubic-bezier(0.2, 0, 0, 1)`（快出慢停） | `ease-standard` |
| easing.emphasized | `cubic-bezier(0.34, 1.56, 0.64, 1)`（稍微超過再回彈） | `ease-emphasized` |

所有時長 ≤ 300ms（slow 由預設的 360 改成 280，配合 page-design-spec「全部 ≤ 300ms」）。進場與離場都用 standard；回彈只給貼紙和徽章。

**可以動的地方**（全部是回應操作；細節見 page-design-spec 第 4 節，時長換成上面的 token）：
1. 按鈕按下：往下沉、厚邊變薄（fast）。
2. 數字格、封面、分頁圖示底按下：縮到 94–97%（fast）。
3. 答對時黃色貼紙「啪」一下：`animate-pop`（60% → 112% → 100%，300ms、emphasized）。「今天做完了」「這一輪做完了」的貼紙出現時也用。
4. 徽章數字改變：`animate-bump`（100% → 115% → 100%，200ms、emphasized）；變 0 時縮小淡出（fast）。
5. 進子頁時整頁淡入（只動 opacity，base）；分頁之間、閱讀器不做。
6. 面板開關（slow 開／base 關）、提示框出現（fast）、「已加入」膠囊淡入（base）。
7. 閱讀器頂端列、章節頁小頂列滑入滑出（base）。
8. 進度條寬度變化（base）；封面載入完淡入（base）。
9. 循環動畫只有三種：載入圓點、重新整理圖示旋轉、不定進度條。

**不動的地方**：分頁切換、元素逐一進場、捲動進場、卡片 hover 浮起、答錯、封面歪斜（是靜態的）、章節頁捲到正在看（瞬間定位）。

**`prefers-reduced-motion: reduce`**：所有 transition 與 animation 縮成 0.01ms（base 層一次處理）；循環動畫改 `motion-safe:` 才加；按下不位移、不縮放，改成按下的底色；閱讀器頂端列直接出現／消失（藏與出的行為照舊）。

## 10. Accessibility

- **對比**：內文 ≥ 4.5:1；大字（≥ 24px，或 ≥ 18.66px 粗體）、圖示、UI 元件外框、資訊圖形 ≥ 3:1。全部組合見 `docs/design/contrast-report.md`；第 3 節列出的組合全部通過。停用狀態 WCAG 不要求對比，但本系統的停用文字仍 ≥ 4.5（淡粉 2 上 ink-faint 4.73）。
- **focus**：全站 `:focus-visible` 3px 深粉外框、offset 2px。輸入框聚焦用 3px 深粉內框（變粗＋變色）。疊在漫畫上的元件用三層框。
- **不只靠顏色**：狀態標籤一定有字；數字格的看過／還沒看差在實心 vs 外框；選中分頁有圖示底塊；泡泡框有翻譯／沒翻譯差在有沒有粉色那圈；錯誤一定有文字；開關有圓鈕位置。
- **鍵盤**：Tab 順序照視覺順序；Esc 關提示框與面板；開關 `role="switch"`；分段選擇 `role="radio"` 或 `aria-pressed`；數字格是 `<ol>` 裡的連結；分組收合用原生 `<details>`；圓形圖示鈕都有 `aria-label`。
- **語言**：越南文內容一律 `lang="vi"`（書名、字卡原文、填空句、提示框原文、作答欄、「已加入」的原文）。
- **alt 文字**：封面 `alt` 用顯示用書名；漫畫頁沿用 `alt="第 n 頁"`；裝飾圖示 `aria-hidden="true"`；泡泡圖、比例條用 `role="img"`＋完整數字的 `aria-label`。
- **表單錯誤**：`aria-invalid="true"`＋`aria-describedby` 指向錯誤文字；錯誤文字說怎麼修（沿用現有寫法）；失敗 `role="alert"`，成功 `role="status"`。
- **觸控區** ≥ 44×44px（第 8 節）。
- **動態**：尊重 `prefers-reduced-motion`（第 9 節）。

## 11. Design Anti-Patterns

通用：
- 沒有理由的紫藍漸層、霓虹光暈、毛玻璃疊在每張卡片上。
- 每個區塊都是「圖示＋標題＋一段字」的三欄卡片；大數字統計卡填版面。
- 全大寫加字距的小標、用中點串的資訊（「A · B · C」）、連結後面加「→」。
- 一頁超過兩種字體家族、超過三種非零圓角。
- 為了動而動、所有元素都 fade-up。
- 灰色小字當內文、對比不足的 placeholder 當 label。
- 表情符號當圖示（「⚙」也算，改用 SVG）。

這個品牌專屬：
- **鮮粉 `#FF4F8B` 放字，或放在淡粉／淡粉 2 上。**
- **黃色 `#FFD23F` 當文字色，或黃底配白字。** 黃色只當底，上面只放墨色。
- **一個畫面超過一張歪斜的貼紙**；書架封面加白邊或歪斜。
- **中文加粗、中文斜體**（Huninn 沒有粗體，假粗體會糊）。
- **到處都是深粉**：深粉只給一顆主要按鈕、選中狀態、正在看、少量粉色數字。一整列重複的動作用 soft 按鈕。
- 介面用漸層（漸層只存在於預覽的封面佔位）。
- 任何暗色樣式、`prefers-color-scheme: dark`、深色卡片或深色提示訊息。
- 寫死色碼、`bg-neutral-*`、`text-sky-*` 等 Tailwind 內建色票；`text-sm` 這類內建字級。
- 用整顆 `opacity` 做停用或次要文字。
- 紅色（重新學習、錯誤）和深粉用在同一個元件裡互相緊鄰。
- 12px 以下的字。

## 12. Page-Specific Exceptions

| 頁面／區塊 | 例外 | 理由 |
|---|---|---|
| 閱讀器：漫畫頁 | 漫畫圖本身不做任何處理（不加圓角、不加框、不調色）；頁面之間不留縫 | 漫畫頁不被設計（原則 5） |
| 閱讀器：泡泡框、提示框、浮動控制項、「已加入」 | 唯一使用墨色外圈（`shadow-ring-*`、`border-ink`、`shadow-float`）的地方 | 疊在任意圖上要都看得見；單一顏色做不到 |
| 閱讀器：泡泡框 | 用 `rounded-tile`，小框會自動變成膠囊形 | 跟對話框的形狀一致 |
| 書庫「繼續看」卡 | 封面貼紙 −4°、白邊 4px、`shadow-raised`；黃色「繼續看」標籤 | 一個畫面一張貼紙（原則 3） |
| 章節頁頂區 | 封面貼紙 +3° 置中；手機上頂區內容置中 | 同上；頂區是這頁唯一的焦點 |
| 閱讀器章末 | 「本話完」黃標籤 −3° | 這一屏唯一的貼紙 |
| 章節頁數字格 | 能按的東西不是全圓，而是 `rounded-tile` | 一排五格的方塊比圓形好掃讀、好點 |
| 練習總覽泡泡 | 圓的大小照張數比例，最小直徑 64；數字依大小用 `text-display`／`text-headline`／`text-heading` | 大小本身就是資訊 |
| 今天做完了、這一輪做完了 | 黃色貼紙 −8°、`animate-pop` | 完成時刻 |
| 錯誤與空狀態貼紙 | −6°／−8° | 同一家族；這個畫面沒有其他貼紙 |
| 搜尋框 | 不畫 ≥ 3:1 的外框，靠放大鏡圖示（5.26）與提示字（5.26）辨識；聚焦時出現深粉框 | 淡粉膠囊搜尋框是方向 C 的造型；圖示與提示字已足以辨識它是輸入框 |
| 練習中的填空格 | 白底膠囊 `inset-ring-2 inset-ring-brand`（在淡粉題目卡裡，不用鮮粉） | 鮮粉在淡粉上只有 2.82 |
| 練習中的「送出」「下一題」 | 放在作答欄下方的一般流排，不做預覽的貼底容器 | iPhone 鍵盤彈出時貼底元素會被蓋住（page-design-spec 2.7） |

## 13. Voice and Microcopy

- **語氣**：短句、口語、具體。像 App 在旁邊提醒，不像系統公告。不用驚嘆號，不撒嬌，不道歉。
- **稱呼**：需要時用「你」，大多數時候省略主詞。
- **按鈕寫動作，完成提示用同一個詞**：
  - 「＋收卡」「加入單字」「加入句子」→「已加入：（原文）」
  - 「儲存」→「已儲存」
  - 「開始複習」→ 做完時「今天做完了」／「這一輪做完了」
  - 「刪除卡片」→ 確認「確定刪除？無法復原」
- **錯誤訊息**：先說發生什麼，再說怎麼修：「連不上伺服器，卡片沒有存進去。內容還在，請再按一次。」（沿用現有寫法）。不寫「發生錯誤」「請稍後再試」這種沒有下一步的句子。
- **空狀態**：說接下來可以做什麼，並給一顆按鈕：「還沒有卡片。在手機上閱讀時把單字或句子加入，就會出現在這裡。」＋「到書庫」。
- **用詞對照（全站統一）**：

| 用這個 | 不用這個 |
|---|---|
| 話（第 54 話、149 話） | 章、集、回 |
| 書庫 | 首頁、圖書館 |
| 漫畫（「全部漫畫」「8 部」） | 作品、項目 |
| 字卡庫（頁名）、字卡（分頁） | 卡片庫、單字本 |
| 收卡（動作）、加入單字／句子 | 收藏、儲存卡片 |
| 練習（分頁）、複習（動作） | 學習、測驗 |
| 新卡、學習中、重新學習、間隔 N 天、到期、間隔複習（分布圖例） | new、learning、待複習 |
| 看過、正在看、還沒看、看到一半 | 已讀、未讀、閱讀中 |
| 標示（泡泡框開關） | 提示、高亮 |
| 深入查詢 | 分析、AI 解說 |

- 不在介面上出現內部用語（`standing.remaining`、`.env`、`npm run dev`）。現有 `ErrorState` 的「無法通過 Cloudflare 驗證」說明提到 `web/.env` 與 `npm run dev`，是給開發者看的；page-design-spec 決定沿用現有字，這裡只標記，之後要改由使用者決定。
- 新加的字列在 page-design-spec 第 8 節；本節只定規則。

## 14. Changelog

| 日期 | 變更 | 理由 | 提出者 |
|---|---|---|---|
| 2026-11-14 | 建立第一版，token 取自 `previews/round2/direction-c.html`，元件狀態對齊 `page-design-spec.md` | 使用者選定方向 C 粉紅貼紙，只做亮色 | design-system-architect |
| 2026-11-14 | 進度條軌道：`#FFE0EC` → 白底＋2px `line` 內框 | 鮮粉填色對 `#FFE0EC` 只有 2.54:1，對白 3.11:1 | design-system-architect |
| 2026-11-14 | 學習中圖形色：`#C98400` → `#B87A00` | 原色在淡粉上 2.81:1；新色白 3.61、淡粉 3.27 | design-system-architect |
| 2026-11-14 | 鮮粉只放白底；填空格外框、解析中滑塊改深粉 | 鮮粉在淡粉上 2.82、淡粉 2 上 2.54 | design-system-architect |
| 2026-11-14 | 新增 `border.control` `#A07C8C`，輸入框預設外框與開關關閉軌道都用它（page-design-spec 的 `--line` 外框與 `#9C8592` 軌道改用這個） | 控制項外框需 ≥ 3:1；`line` 約 1.3；統一成一個色 | design-system-architect |
| 2026-11-14 | 最小字級 12 → 13 | 手機最小字級 13px | design-system-architect |
| 2026-11-14 | 字級收斂為 34／28／24／20／18／16／14／13 八階（對照見 15.6） | 預覽與頁面規格有 12–28 共十餘種字級 | design-system-architect |
| 2026-11-14 | 閱讀器與小頂列的圓鈕 40 → 44；頂端列 97% 白 → 不透明 | 觸控區 ≥ 44；漫畫會從底下透出 | design-system-architect |
| 2026-11-14 | 圓角收斂為 16／20／28＋全圓（預覽有 10–32 多種） | 同一品牌不超過三種非零圓角 | design-system-architect |
| 2026-11-14 | 閱讀器泡泡框改「深粉／白／墨」三層；提示框改白底墨框；浮動控制項與「已加入」加白邊墨線 | 單一顏色在某些漫畫底色上 < 3:1（深粉在中灰 1.41、白在粉紅 2.16） | design-system-architect |
| 2026-11-14 | `duration.slow` 360 → 280 | 配合頁面規格「所有動態 ≤ 300ms」 | design-system-architect |
| 2026-11-14 | 停用開關（開著）改鮮粉軌道，不用整顆半透明 | 停用規則一致；白鈕對鮮粉 3.11 | design-system-architect |
| 2026-11-14 | `apple-mobile-web-app-status-bar-style` 改 `default`、`theme-color` 與 manifest 顏色改 `#FFFFFF`（與 page-design-spec 1.1 一致） | 亮色底配 black-translucent 時鐘會看不到 | design-system-architect |

---

## 15. 實作對照（Tailwind v4）

> 給實作的人直接照抄。只改 `web/src/style.css`、`web/index.html`、`web/public/manifest.webmanifest`；元件一律用下面的 utility，不寫死色碼、不用 `neutral-*`／`sky-*`／`amber-*`／`emerald-*`／`rose-*`。

### 15.1 `web/src/style.css`

```css
@import 'tailwindcss';

@theme {
  /* 全部頁面都換成新 token 之後，打開這三行，讓內建色票、字級、圓角再也用不到。 */
  /* --color-*: initial; */
  /* --text-*: initial; */
  /* --radius-*: initial; */

  /* 既有：收卡面板改放閱讀欄旁邊的寬度（保留） */
  --breakpoint-dock: 84rem;

  /* ---- 顏色：底 ---- */
  --color-paper: #ffffff;
  --color-blush: #fff0f5;
  --color-blush-strong: #ffe0ec;
  --color-mist: #f5eef1;
  --color-scrim: rgb(43 31 39 / 0.45);
  /* ---- 顏色：字（ink 也是提示框的墨框） ---- */
  --color-ink: #2b1f27;
  --color-ink-soft: #6a5560;
  --color-ink-faint: #765f6b;
  --color-white: #ffffff;
  /* ---- 顏色：線 ---- */
  --color-line: #f3dde6;
  --color-line-strong: #a07c8c;
  /* ---- 顏色：主色與點綴 ---- */
  --color-brand: #c81a60;
  --color-brand-hover: #b01652;
  --color-brand-pressed: #9e1449;
  --color-brand-edge: #8f1244;
  --color-brand-vivid: #ff4f8b;
  --color-brand-wash: rgb(255 79 139 / 0.16);
  --color-sun: #ffd23f;
  /* ---- 顏色：回饋 ---- */
  --color-danger: #c8322a;
  --color-danger-hover: #a82820;
  --color-danger-tint: #fdecea;
  --color-success: #17734a;
  --color-success-tint: #e6f5ec;
  --color-warning: #9a5b00;
  --color-warning-tint: #fff3d6;
  /* ---- 顏色：字卡狀態（文字／淡底／圖形） ---- */
  --color-st-new: #1d63d1;
  --color-st-new-tint: #e8f0fd;
  --color-st-new-graphic: #2e6fe0;
  --color-st-learn: #9a5b00;
  --color-st-learn-tint: #fff3d6;
  --color-st-learn-graphic: #b87a00;
  --color-st-relearn: #c8322a;
  --color-st-relearn-tint: #fdecea;
  --color-st-relearn-graphic: #e5484d;
  --color-st-review: #17734a;
  --color-st-review-tint: #e6f5ec;
  --color-st-review-graphic: #2b9a5e;

  /* ---- 字體 ---- */
  --font-sans: 'Nunito', 'Huninn', 'PingFang TC', 'Heiti TC', 'Microsoft JhengHei', system-ui, sans-serif;

  /* ---- 字級（utility：text-display、text-page …） ---- */
  --text-display: 2.125rem;
  --text-display--line-height: 1.1;
  --text-page: 1.75rem;
  --text-page--line-height: 1.3;
  --text-headline: 1.5rem;
  --text-headline--line-height: 1.4;
  --text-heading: 1.25rem;
  --text-heading--line-height: 1.35;
  --text-label: 1.125rem;
  --text-label--line-height: 1.4;
  --text-body: 1rem;
  --text-body--line-height: 1.7;
  --text-meta: 0.875rem;
  --text-meta--line-height: 1.6;
  --text-caption: 0.8125rem;
  --text-caption--line-height: 1.5;
  --leading-title: 1.35;

  /* ---- 圓角（utility：rounded-tile、rounded-card、rounded-panel；全圓用內建 rounded-full） ---- */
  --radius-tile: 1rem;
  --radius-card: 1.25rem;
  --radius-panel: 1.75rem;

  /* ---- 陰影與框 ---- */
  --shadow-raised: 0 10px 22px -10px rgb(120 30 70 / 0.55);
  --shadow-chrome-up: 0 -1px 0 #f3dde6, 0 -8px 24px -12px rgb(200 26 96 / 0.25);
  --shadow-chrome-down: 0 1px 0 #f3dde6, 0 8px 20px -14px rgb(120 30 70 / 0.4);
  --shadow-overlay: 0 18px 40px -12px rgb(120 30 70 / 0.45);
  --shadow-edge: 0 5px 0 -1px #8f1244;
  --shadow-edge-sm: 0 4px 0 -1px #8f1244;
  --shadow-edge-pressed: 0 2px 0 -1px #8f1244;
  --shadow-float: 0 0 0 2px #ffffff, 0 0 0 3px #2b1f27, 0 10px 22px -10px rgb(120 30 70 / 0.55);
  --shadow-ring-selected: 0 0 0 3px #c81a60, 0 0 0 5px #ffffff, 0 0 0 6px #2b1f27;
  --shadow-ring-hint: 0 0 0 1.5px #c81a60, 0 0 0 2.5px #ffffff, 0 0 0 3.5px #2b1f27;
  --shadow-ring-hint-plain: 0 0 0 1px #ffffff, 0 0 0 2px #2b1f27;

  /* ---- 版寬（utility：max-w-narrow、max-w-page …） ---- */
  --container-narrow: 35rem;
  --container-page: 40rem;
  --container-wide: 47.5rem;
  --container-reader: 50rem;
  --container-shelf: 67.5rem;
  --container-tabs: 26.25rem;

  /* ---- 動態（時長用內建的 duration-120／200／280） ---- */
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --ease-emphasized: cubic-bezier(0.34, 1.56, 0.64, 1);
  --animate-pop: pop 300ms var(--ease-emphasized) both;
  --animate-bump: bump 200ms var(--ease-emphasized);

  @keyframes pop {
    0% { scale: 0.6; }
    60% { scale: 1.12; }
    100% { scale: 1; }
  }
  @keyframes bump {
    50% { scale: 1.15; }
  }
}

@layer base {
  /* 只有亮色：瀏覽器自己的控制項、捲軸也是亮的。手機開深色模式也不變。 */
  :root {
    color-scheme: light;
  }

  html {
    /* Huninn 只有一個字重，不准瀏覽器做假粗體 */
    font-synthesis-weight: none;
  }

  body {
    background-color: var(--color-paper);
    color: var(--color-ink);
    font-weight: 600; /* Nunito 內文字重；中文 Huninn 不受影響 */
  }

  :focus-visible {
    outline: 3px solid var(--color-brand);
    outline-offset: 2px;
  }

  @media (width >= 48rem) {
    :root {
      --text-page: 2rem;
    }
    body {
      font-weight: 700;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    *,
    *::before,
    *::after {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
      scroll-behavior: auto !important;
    }
  }
}

/* ---- 以下是現有的 PWA 規則：保留，只改顏色 ---- */
/* 刪除：html { color-scheme: dark; }（由上面的 :root 取代） */
body {
  /* 刪除原本的 background-color: #0a0a0a（改由 base 的 --color-paper） */
  padding: env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);
}

body::before {
  content: '';
  position: fixed;
  inset: 0 0 auto;
  z-index: 50;
  height: env(safe-area-inset-top);
  background-color: var(--color-paper); /* 原本 #0a0a0a */
}
/* overscroll-behavior、tap-highlight、text-size-adjust、img touch-callout、a/button/nav user-select：原樣保留 */
```

注意：
- `body` 的 `padding` 與 `body::before` 沿用現狀不包 layer（會贏過 utility），不要搬進 `@layer base`。
- `--shadow-*` 裡的色碼寫死，是因為陰影要能在任何元素上獨立使用；改顏色時這裡要一起改（design-tokens.json 有對照）。
- `rotate-*`、`scale-*` 在 v4 用的是獨立的 `rotate`／`scale` 屬性，所以貼紙的 `-rotate-8` 和 `animate-pop` 的縮放可以同時存在，不會互相蓋掉。

### 15.2 `web/index.html`

```html
<meta name="theme-color" content="#FFFFFF" />
<meta name="color-scheme" content="light" />
<meta name="apple-mobile-web-app-status-bar-style" content="default" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Huninn&family=Nunito:wght@600;700;800;900&display=swap" />
```

`viewport-fit=cover`、manifest（`crossorigin="use-credentials"`）、apple-touch-icon 等其他標籤不動。

### 15.3 `web/public/manifest.webmanifest`

```json
"background_color": "#FFFFFF",
"theme_color": "#FFFFFF"
```

### 15.4 元件 utility 速查

| 元件 | class |
|---|---|
| 主要按鈕 lg | `inline-flex h-14 w-full items-center justify-center gap-2.5 rounded-full bg-brand px-6 text-label font-extrabold text-white shadow-edge transition-[translate,box-shadow,background-color] duration-120 ease-standard hover:bg-brand-hover active:translate-y-0.75 active:bg-brand-pressed active:shadow-edge-pressed motion-reduce:active:translate-y-0 disabled:translate-y-0 disabled:bg-blush-strong disabled:text-ink-faint disabled:shadow-none disabled:cursor-not-allowed` |
| 主要按鈕 sm（＋收卡、加入句子） | `relative inline-flex h-9 items-center rounded-full bg-brand px-3.5 text-meta font-extrabold text-white shadow-edge-sm before:absolute before:-inset-1 before:content-[''] hover:bg-brand-hover active:translate-y-0.5 active:bg-brand-pressed active:shadow-edge-pressed motion-reduce:active:translate-y-0` |
| 次要按鈕 md | `inline-flex h-11 items-center justify-center gap-1.5 rounded-full bg-paper px-4 text-body font-extrabold text-ink inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush disabled:text-ink-faint` |
| 柔和按鈕 | `relative inline-flex h-9 items-center rounded-full bg-blush px-3.5 text-meta font-extrabold text-brand before:absolute before:-inset-1 before:content-[''] hover:bg-blush-strong active:bg-blush-strong` |
| 文字按鈕 | `inline-flex h-11 items-center rounded-full px-2 text-body text-ink-soft hover:bg-blush active:bg-blush` |
| 危險按鈕（確認中） | `inline-flex h-11 items-center justify-center rounded-full bg-danger px-4 text-body font-extrabold text-white hover:bg-danger-hover active:bg-danger-hover` |
| 圓形圖示鈕 | `grid size-11 place-items-center rounded-full bg-paper text-ink-soft inset-ring-2 inset-ring-line`（淡粉版 `bg-blush` 無框） |
| 設定膠囊鈕 | `inline-flex h-10 items-center gap-1.5 rounded-full bg-paper pr-3.5 pl-3 text-meta text-ink-soft inset-ring-2 inset-ring-line` |
| 頁名 | `text-page` |
| 區塊標題 | `text-heading` |
| 書名（越南文） | `text-body font-extrabold leading-title line-clamp-2`（作品頁 `text-heading`、不截斷） |
| 次要說明 | `text-meta text-ink-soft` |
| 數量標籤 | `rounded-full bg-blush px-2.5 text-meta text-brand tabular-nums` |
| 分頁列 | 見 7.3 |
| 白卡 | `rounded-card bg-paper inset-ring-2 inset-ring-line` |
| 淡粉大卡 | `rounded-panel bg-blush px-5 pt-5.5 pb-6` |
| 淡粉頂區 | `rounded-b-panel bg-blush pb-5` |
| 書架封面 | 見 7.5 |
| 貼紙封面 | 見 7.5 |
| 數字格 | 見 7.7 |
| 狀態標籤 | `inline-flex h-6.5 items-center rounded-full px-2.5 text-caption bg-st-new-tint text-st-new`（四種換顏色） |
| 進度條 | 軌道 `h-2.5 overflow-hidden rounded-full bg-paper inset-ring-2 inset-ring-line`；填色 `h-full rounded-full bg-brand-vivid transition-[width] duration-200 ease-standard` |
| 比例條一段 | `min-w-2 rounded-full bg-st-new-graphic`（四種換顏色），容器 `flex h-4 gap-0.75` |
| 輸入框 | `w-full rounded-card bg-paper px-4 py-3 text-body text-ink inset-ring-2 inset-ring-line-strong placeholder:text-ink-faint focus:inset-ring-3 focus:inset-ring-brand focus-visible:outline-none aria-[invalid=true]:inset-ring-3 aria-[invalid=true]:inset-ring-danger read-only:bg-blush read-only:text-ink-soft read-only:inset-ring-line` |
| 搜尋框 | `flex h-12 items-center gap-2 rounded-full bg-blush px-4 text-body focus-within:inset-ring-3 focus-within:inset-ring-brand` |
| 開關 | 見 7.9 |
| 分段選擇 | 軌道 `inline-flex rounded-full bg-blush p-1`；選項 `h-9 rounded-full px-4 text-meta text-ink-soft aria-checked:bg-brand aria-checked:text-white`（`aria-pressed:` 同理） |
| 訊息框 | 見 7.14 |
| 面板 | 見 7.13 |
| 閱讀器泡泡框 | 見 7.17 |
| 提示框 | `absolute z-10 my-3 w-72 max-w-[90%] rounded-card border-2 border-ink bg-paper p-3.5 shadow-overlay` |
| 完成貼紙 | `grid size-21 place-items-center rounded-full bg-sun text-ink -rotate-8 ring-5 ring-paper outline-2 outline-blush-strong motion-safe:animate-pop` |
| 錯誤／空狀態貼紙 | 見 7.15 |
| 載入圓點 | `size-2 rounded-full bg-brand-vivid`（第二顆 `bg-sun`、第三顆 `bg-brand`），`motion-safe:` 才加跳動動畫 |

### 15.5 現有樣式 → 新 token（改版時逐一替換）

| 現在 | 換成 |
|---|---|
| `bg-neutral-950`、`#0a0a0a` | `bg-paper` |
| `bg-neutral-900`（漫畫佔位） | `bg-mist` |
| `bg-neutral-900`（輸入框底） | `bg-paper`＋`inset-ring-line-strong` |
| `bg-neutral-800`（次要按鈕） | 次要按鈕 |
| `text-neutral-50`／`100`／`200` | `text-ink` |
| `text-neutral-300`／`400` | `text-ink-soft` |
| `text-neutral-500`／`600` | `text-ink-faint` |
| `border-neutral-700`／`800` | 輸入框 `inset-ring-line-strong`；卡片、分隔 `line` |
| `bg-sky-600`／`hover:bg-sky-500`（主要按鈕、開關開） | `bg-brand`／`hover:bg-brand-hover` |
| `ring-sky-400`（泡泡框） | `shadow-ring-hint`／`shadow-ring-selected` |
| `ring-amber-400`（沒翻譯的泡泡框） | `shadow-ring-hint-plain` |
| `focus:border-sky-500` | `focus:inset-ring-3 focus:inset-ring-brand` |
| `text-emerald-400` | 成功訊息框或成功膠囊 |
| `text-amber-400`、`border-amber-900/60` | 提醒訊息框 |
| `text-rose-400`、`border-rose-500` | `text-danger`、`inset-ring-danger` |
| `rounded-md`、`rounded-lg` | 依第 6 節選 `rounded-tile`／`rounded-card`／`rounded-full` |
| `disabled:opacity-40`／`50` | 停用色（第 7 節通用規則） |
| `text-xs`／`sm`／`base`／`lg`／`2xl` | `text-caption`／`meta`／`body`／`label`／`page`（依第 4 節） |
| `max-w-[800px]` | `max-w-reader` |
| `max-w-xl`、`max-w-md` | `max-w-narrow`／`max-w-page` |

### 15.6 page-design-spec 的數值 → token

page-design-spec 用預覽的變數與 px 寫；實作時換成這裡的 token。

| page-design-spec | token |
|---|---|
| `--bg` / `--blush` / `--blush-2` / `--line` | `paper` / `blush` / `blush-strong` / `line` |
| `--text` / `--text-2` / `--text-3` | `ink` / `ink-soft` / `ink-faint` |
| `--pink` / `--pink-strong` / `--sun` | `brand-vivid` / `brand` / `sun` |
| `--st-*`、`--st-*-bg`、圖形色 | `st-*`、`st-*-tint`、`st-*-graphic`（學習中圖形色 `#C98400` 一律換 `st-learn-graphic` `#B87A00`） |
| `#A9154F`（按下深一階） | `brand-pressed` |
| `#9C8592`（開關關閉軌道） | `line-strong` |
| `#F5EEF1` | `mist` |
| 字級 12 | 13 `text-caption` |
| 字級 13 | 13 `text-caption` |
| 字級 14 | 14 `text-meta` |
| 字級 15 | `ink-soft`／`ink-faint` 的說明 → 14 `text-meta`；`ink` 的主要內容與按鈕 → 16 `text-body` |
| 字級 16 | 16 `text-body` |
| 字級 17 | 欄位標籤、中文提示內容 → 18 `text-label`；內文、輸入框、提示框譯文 → 16 `text-body` |
| 字級 18 | 18 `text-label` |
| 字級 19、20 | 20 `text-heading` |
| 字級 22 | 「正確／不對」→ 20 `text-heading`；答案字 → 24 `text-headline` |
| 字級 24、25、26 | 24 `text-headline` |
| 字級 28 | 28 `text-page` |
| 字級 34 | 34 `text-display` |
| 圓角 10、12、14、16、18 | 16 `rounded-tile`（圖例小方塊 4 例外） |
| 圓角 20、24（白卡、側邊面板、繼續看卡） | 20 `rounded-card` |
| 圓角 22、24（頂端列、分頁列）、24–28（淡粉卡）、32（淡粉頂區） | 28 `rounded-panel` |
| 按鈕高 48（錯誤狀態） | 44 md |
| 按鈕高 52（收卡面板） | 56 lg（兩顆並排時 `flex-1`） |
| 柔和按鈕高 32 | 36（觸控區補到 44） |
| 圓鈕 40 | 44 |
| 時長 80–140ms | `duration-120` |
| 時長 160–240ms | `duration-200` |
| 時長 260ms | `duration-280` |
| 曲線 `cubic-bezier(.2,.8,.2,1)`、ease-out、ease-in | `ease-standard` |
| 曲線 `cubic-bezier(.3,1.4,.6,1)` | `ease-emphasized` |
| 泡泡框「1.5px 實線 `--pink` 60%」「虛線 `#C98400`」「2.5px `--pink-strong`」 | `shadow-ring-hint`／`shadow-ring-hint-plain`／`shadow-ring-selected`（7.17） |
| 提示框 `0 0 0 2px var(--line)` | `border-2 border-ink`＋`shadow-overlay`（7.17） |
| 浮動控制項 `0 0 0 2px var(--line)`＋陰影 | `shadow-float` |
| 輸入框 `inset 0 0 0 2px var(--line)` | `inset-ring-2 inset-ring-line-strong` |
| 停用開關 `opacity: .5` | 7.9 的停用樣式 |
