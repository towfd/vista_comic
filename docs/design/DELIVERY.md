# 交付：vista_comic 網頁改版（粉紅貼紙）

- 日期：2026-11-14
- 模式：redesign
- 狀態：已合併（PR #146–#152）並部署到 agent 那台（`bd364db`），`api`、`web` 重建；15 個 `title.txt` 已放進書庫並重新掃描（15／15 有正式書名）。

## 產出

| 類別 | 檔案 |
|---|---|
| 設計規則 | `DESIGN.md`、`docs/design/design-tokens.json`、`docs/design/contrast-report.md` |
| 畫面規格 | `docs/design/page-design-spec.md` |
| 視覺方向 | `docs/design/visual-directions.md`、`visual-decision.md`、`previews/round2/direction-c.html`（選定） |
| 書名 | `docs/design/titles.md`（主機上的 `title.txt` 照這份） |
| 工作票 | `.scratch/web-redesign/`（spec＋01–07，皆 done） |
| 程式 | `web/`（全部頁面）、`backend/app/scanner.py` 等（`displayTitle`） |

## 各階段決定（摘要，完整紀錄在 STATUS.md）

- 第 1 輪三個深色方向被否決（太暗沉、版面不喜歡）→ 只做亮色，參考 Webtoon／LINE 漫畫。
- 第 2 輪選方向 C「粉紅貼紙」。章節用數字格；書名用 `title.txt`；練習徽章沿用現有算法；不做一整天的作答統計。

## QA 結果

| 輪 | P0 | P1 | P2 | 說明 |
|---|---|---|---|---|
| 1（390／1440，真實資料） | 0 | 2 | 1 | P1：無空格長書名溢出卡片、書庫回來不會重抓（繼續看過期）。P2：缺 favicon。三項都已修（併入 #148）。 |

- 測試：網頁 24 檔 481 個、後端 410 個全部通過。
- 所有頁面 390／1440 無水平捲動。

## 還沒實際測過（請在 iPhone 上看）

1. 主畫面 App 的狀態列是白底黑字；不是的話刪掉主畫面的 vista 重新加入。
2. Home 條上方的留白（分頁列、收卡面板、練習的按鈕）。
3. 閱讀器泡泡框疊在真實翻譯資料上的樣子（本機沒有翻譯資料，只用假框驗過三層框）。
4. 鍵盤彈出時：練習的「送出」、收卡面板、單張字卡的欄位不被遮住、畫面不亂跳。
5. 按下按鈕的手感（觸控的 active 樣式）。

## 建議的下一步

- 實機看完後的修正走 tweak 模式。
- 全站都換成 token 了，之後可以把 `style.css` 裡註解掉的 `--color-*: initial` 打開，防止再用到舊色票（要先確認建置後 CSS 沒有少 class）。
- 錯誤畫面「無法通過 Cloudflare 驗證」的說明仍是給開發者看的字（DESIGN §13），要不要改由使用者決定。
