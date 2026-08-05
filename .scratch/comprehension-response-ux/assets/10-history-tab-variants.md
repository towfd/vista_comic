# History tab variants — asset for ticket 10

> **Verdict: Variant B.** See
> [History tab list and detail UI](../issues/10-history-tab-ui.md) for the
> reasoning and the full resolution. Three things settled after these were
> drawn:
>
> 1. The list becomes a real `List` with **swipe-to-delete plus the existing
>    confirmation alert** — the entry point moves from a button to a swipe
>    because pruning is now routine, but deletion is still irreversible.
> 2. Titles are **joined server-side from the in-memory catalog**, nullable;
>    a comic that has left the library reads `已不在書庫` and its
>    jump-to-source button is disabled.
> 3. Volume stays unresolved on purpose — a default row limit was considered
>    and rejected for making old records silently unreachable.


Text mockups standing in for the `/prototype` UI branch's usual runnable
artifact; this project forbids touching the codebase before the implement
phase.

**Baseline — 單字本 as shipped today** (`VocabularyView.swift:64-79`,
`SavedTranslationRow.swift`): a `ScrollView` of rounded cards (not a `List`,
so no swipe actions). Each card stacks original text, translated text in red,
a source line, and an optional inline "Show explanation" disclosure, with a
trailing column of two circular buttons — jump-to-source `⊙` and delete `🗑`.
There is **no detail screen**; everything happens inline.

The source line today renders raw 16-hex-char SHA-1 ids
(`ids.py:20`), i.e. `a3f9c2b1d4e5f6a7 · 8b2c1d3e4f5a6b7c · page 3 · Jan 15`.
Every variant below draws it with real titles instead — see the open question
at the bottom.

Sample records used throughout:

| # | source | state |
| --- | --- | --- |
| 1 | `お前、なかなかやるじゃないか` | `ok`, unread |
| 2 | `まだまだこれからだ` | `running` |
| 3 | `くっ…！` | `declined` |
| 4 | `絶対に許さない` | `failed` |
| 5 | `ありがとう、本当に` | `ok`, already read |

---

## Variant A — keep the card, grow it

The shipped card evolves in place: an unread dot leads the first line, the
`📱`/`☁️` provenance chip from ticket 09 rides on the translation line, and the
bottom strip becomes the status row. Expanding "顯示解釋" is what marks it read.
No detail screen, no new navigation.

```
┌────────────────────────────────────────────────┐
│  歷史紀錄                                    ⓷ │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │ ●  お前、なかなかやるじゃないか            │  │
│  │    你小子，挺有一套的嘛              ☁️   │  │
│  │    鬼滅之刃 · 第 4 話 · p.12 · 3 分鐘前   │  │
│  │    ⌄ 顯示解釋                     ⊙   🗑  │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │    まだまだこれからだ                     │  │
│  │    還早得很呢                        📱   │  │
│  │    鬼滅之刃 · 第 4 話 · p.12 · 4 分鐘前   │  │
│  │    ◌ 解釋產生中                   ⊙   🗑  │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │    くっ…！                                │  │
│  │    唔…！                             📱   │  │
│  │    鬼滅之刃 · 第 4 話 · p.11 · 6 分鐘前   │  │
│  │    這段內容模型不提供解釋          ⊙   🗑  │  │
│  └──────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────┐  │
│  │    絶対に許さない                         │  │
│  │    我絕對不會原諒                    📱   │  │
│  │    鬼滅之刃 · 第 3 話 · p.20 · 1 小時前   │  │
│  │    沒能取得深度解釋      [重試]   ⊙   🗑  │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

**Bets on:** almost nothing new — the shipped row already does four of these
five states' worth of layout, and the reader never leaves one scroll.

**Costs:** a card is ~5 lines tall before expanding, so ten records already
exceed a screen and a hundred are unscannable. The retry button sits inline in
a scrolling list of many rows, which is exactly the "easy to spam by accident"
shape the ticket warns about. And "expanding marks read" makes reading and
marking the same gesture, so there is no way to peek without clearing the badge.

---

## Variant B — compact rows that push to a detail screen

Each row is two lines: source text, plus a status line carrying the unread dot,
relative time and location. Everything else — translation, notes, source jump,
retry, delete — lives on a detail screen pushed on tap. Opening the detail is
what marks it read.

```
┌────────────────────────────────────────────────┐
│  歷史紀錄                                    ⓷ │
│                                                │
│  ●  お前、なかなかやるじゃないか            ›  │
│     ☁️ 鬼滅之刃 第 4 話 · 3 分鐘前             │
│  ──────────────────────────────────────────    │
│     まだまだこれからだ                      ›  │
│     ◌ 解釋產生中 · 4 分鐘前                    │
│  ──────────────────────────────────────────    │
│     くっ…！                                 ›  │
│     ⊘ 無解釋 · 鬼滅之刃 第 4 話 · 6 分鐘前     │
│  ──────────────────────────────────────────    │
│     絶対に許さない                          ›  │
│     ⚠ 解釋失敗 · 鬼滅之刃 第 3 話 · 1 小時前   │
│  ──────────────────────────────────────────    │
│     ありがとう、本当に                      ›  │
│     ☁️ 鬼滅之刃 第 3 話 · 2 小時前             │
└────────────────────────────────────────────────┘
```

Detail screen — the same vocabulary as ticket 09's result screen, so the two
teach each other:

```
┌────────────────────────────────────────────────┐
│  ‹ 歷史紀錄                                    │
│                                                │
│   Original            │  Translation      ☁️   │
│   お前、なかなか       │  你小子，挺有一套       │
│   やるじゃないか       │  的嘛                  │
│                                                │
│   深度解釋                                      │
│   Grammar notes                                │
│   なかなか + 否定形…                            │
│   Context notes                                │
│   對手在打鬥中認可主角實力的場面…                 │
│   Tone & register                              │
│   粗魯但帶敬意的男性口吻…                        │
│                                                │
│   鬼滅之刃 · 第 4 話 · p.12 · 3 分鐘前          │
│   [ ⊙ 跳到來源頁 ]              [ 🗑 刪除 ]     │
└────────────────────────────────────────────────┘
```

A `failed` record's detail replaces the notes block with the same box ticket 09
uses, retry button included — so retry is reachable only after a deliberate
tap into one record, never from a list of many.

**Bets on:** volume. Two-line rows mean ~10 records per screen, and the row
carries exactly what triage needs — what it was, whether something arrived,
where it came from.

**Costs:** one more tap to read anything, a second screen to build, and the
detail duplicates layout that ticket 09's result screen already has.

---

## Variant C — grouped by comic and chapter

Compact rows like B, but sectioned by where you were reading, newest group
first. Answers "that thing from chapter 4" rather than "that thing from
Tuesday".

```
┌────────────────────────────────────────────────┐
│  歷史紀錄                                    ⓷ │
│                                                │
│  鬼滅之刃 · 第 4 話                        3   │
│  ●  お前、なかなかやるじゃないか            ›  │
│     ☁️ p.12 · 3 分鐘前                         │
│     まだまだこれからだ                      ›  │
│     ◌ 解釋產生中 · p.12                        │
│     くっ…！                                 ›  │
│     ⊘ 無解釋 · p.11                            │
│                                                │
│  鬼滅之刃 · 第 3 話                        2   │
│     絶対に許さない                          ›  │
│     ⚠ 解釋失敗 · p.20                          │
│     ありがとう、本当に                      ›  │
│     ☁️ p.16                                    │
└────────────────────────────────────────────────┘
```

**Bets on:** the reader's own mental index being spatial — you remember the
scene, not the timestamp.

**Costs:** a reader working through one long manga gets one enormous section,
so the grouping earns nothing until several comics are in play. Depends
entirely on having real titles (see below). And the newest record is no longer
reliably at the top, which is where a just-arrived explanation wants to be.

---

## States every variant must answer for

Empty — different in kind from 單字本's "nothing saved yet", because the reader
never chose to save anything:

```
              ⌛ 還沒有任何紀錄
     翻譯過的句子會自動出現在這裡，
     雲端解釋完成後也會回到這一頁。
```

Backend unreachable — must be distinct from empty. `translation_store`'s module
docstring already establishes this rule for the shipped tab: a read failure is
never degraded into an empty list, because that would misrepresent "the store is
unreachable" as "nothing has been saved".

```
              ⚠ 連不上伺服器
        紀錄還在，只是現在讀不到。
                 [ 重試 ]
```

Tab-bar badge — the count of `is_read == false` records, computed client-side
from the list (ticket 08):

```
   ┌──────────┬──────────┐
   │   書庫    │  歷史紀錄 ③│
   └──────────┴──────────┘
```

---

## Open question this asset surfaced

Every mockup above writes `鬼滅之刃 · 第 4 話`. The record only stores
`comic_id`/`chapter_id`, which are 16-hex-char SHA-1 prefixes (`ids.py:20`),
so as specified by ticket 08 the tab would actually render
`a3f9c2b1d4e5f6a7 · 8b2c1d3e4f5a6b7c · p.12`. `SavedTranslationRow.swift:7-10`
already admits this and calls resolving titles out of scope — tolerable when
the reader saved three things deliberately, not tolerable for a tab that fills
automatically and exists to be browsed.

The backend holds the whole catalog in memory (`main.py:118` `_require_catalog`,
`main.py:173` `_to_summary`), so `GET /comprehensions` can join titles at read
time for free. Alternatives are snapshotting the titles onto the row at enqueue,
or having the client resolve them. Decided in the grilling, then pushed back to
ticket 08.
