Type: prototype
Status: resolved

# History tab list and detail UI

## Question

Design the 歷史紀錄 tab that replaces 單字本. Unlike 單字本 — a short list of things the reader deliberately kept — this fills up automatically with every translate, so volume, scanning, and triage matter in a way they didn't before.

Prototype and decide:

- What a row shows in each state the data model (ticket 08) defines: explanation pending, arrived-unread, arrived-read, failed-retryable, declined.
- How unread is expressed on a row, and how the tab-bar badge is presented.
- What the detail view shows, and how opening it marks the entry read (ticket 05).
- Where the retry affordance lives and what it looks like mid-retry — it may be triggered from a list of many rows, so it should be hard to spam by accident.
- Whether M8's "peek back to the source page" jump-back survives here, since the same `comic_id`/`chapter_id`/`page_number` that powers retry also powers it.
- Grouping/ordering: newest-first flat list, or grouped by comic/chapter?

Use `/prototype` to make something concrete to react to.

## Unblocked by ticket 08

[History record data model and API shape](08-history-record-data-model.md) is resolved, so the states and endpoints this ticket renders are now fixed:

- **Row states come from one `status` column:** `pending`, `running`, `ok`, `declined`, `failed`. Whether a row distinguishes "queued" from "being explained" is this ticket's choice — the data supports both.
- **Text shown per row:** `cloudTranslation` when present, else `translatedText`.
- **Endpoints:** `GET /comprehensions` (newest first), `PATCH /comprehensions/{id} { "isRead": true }` on open, `POST /comprehensions/{id}/retry` (failed only), `DELETE /comprehensions/{id}`. The unread badge count is computed client-side from the list — there is no count endpoint.
- **No upgrade action here.** [Ticket 09](09-reader-result-screen-states.md) removed M9's "request a stronger explanation" entirely and replaced it with a model-tier picker chosen *before* translating, so the detail view has no re-request affordance to design. A `declined` record likewise offers no retry — only `failed` does.
- **No pagination exists yet**, and this list grows with every translate forever. If the prototype makes it obvious that volume needs handling, say so — that is currently sitting in the map's Not-yet-specified.

**Absorbed from the map's fog (now answered below):** decide this tab's **empty state and its unreachable-backend state**. This matters more than it did for 單字本 — that list held things the reader deliberately kept, so "you haven't saved anything" was a fair message. This one fills automatically, so an empty list means something different, and a backend outage means the reader loses the whole tab rather than a few saves. Note that `translation_store`'s existing convention is deliberately *not* to degrade a read failure into an empty list (see its module docstring) — the tab must be able to say "unreachable" distinctly from "nothing here".

## Answer

Three whole-tab variants were drawn and compared in
[History tab variants](../assets/10-history-tab-variants.md) — the text artifact
standing in for the `/prototype` UI branch's usual runnable route.

**Variant B wins: compact two-line rows in a `List`, flat and newest-first, each
pushing a detail screen.**

### The list

A `List` — a change from the shipped tab, which is a `ScrollView` of `VStack`
cards (`VocabularyView.swift:65-78`) and therefore has no swipe actions. Rows
are two lines:

```
●  お前、なかなかやるじゃないか        ›
   ☁️ 鬼滅之刃 第 4 話 · 3 分鐘前
```

- Line 1: unread dot, then the source text, truncated.
- Line 2: a status glyph and label, then comic/chapter, then relative time.

| `status` | Line 2 reads |
| --- | --- |
| `ok` | `☁️` + comic/chapter + relative time |
| `pending` / `running` | `◌ 解釋產生中` |
| `declined` | `⊘ 無解釋` |
| `failed` | `⚠ 解釋失敗` |

No grouping. Variant C (sectioned by comic/chapter) was rejected because a
reader working through one long manga collapses into a single enormous section,
so the grouping earns nothing until several comics are in play — and because a
just-arrived explanation stops being reliably at the top, which is where the
thing the badge is pointing at wants to be.

Variant A (keep today's expanding cards) was rejected on volume: a card is
about five lines before expanding, so ten records already exceed a screen. It
also exposed retry inline in a long scroll — the exact "easy to spam by
accident" shape this ticket warned about — and made expanding both the way to
read an entry and the way to mark it read, so there was no way to peek.

### The detail screen reuses ticket 09's vocabulary

Original/Translation with the `📱`/`☁️` provenance chip, then the `深度解釋`
section in whichever of its states applies (notes, the failure box with retry,
or the declined message), then the source line, then jump-to-source and delete.
Deliberately the same shapes as
[the result screen](09-reader-result-screen-states.md) so the two screens teach
each other rather than each inventing a vocabulary.

- **Opening the detail is what marks the record read** — `PATCH
  /comprehensions/{id} { "isRead": true }`, satisfying ticket 05's per-entry
  clearing.
- **Retry lives only here.** Reaching it requires a deliberate tap into one
  record, which is the answer to the ticket's "hard to spam" requirement. A
  `declined` record has no retry at all (ticket 09).
- **M8's jump-back survives**, unchanged in behaviour: a `ReaderRoute` with
  `isPeek: true` and `targetPage`, so it opens read-only at the exact page
  without overwriting reading progress (`SavedTranslationRow.swift:160-167`).
  It is **disabled when the comic is no longer in the library** — see below.

### Titles must come from the catalog, not the ids

The mockups all read `鬼滅之刃 · 第 4 話`, but the record stores only
`comic_id`/`chapter_id`, which are 16-hex-char SHA-1 prefixes (`ids.py:20`). As
ticket 08 specified it, the row would actually render
`a3f9c2b1d4e5f6a7 · 8b2c1d3e4f5a6b7c · p.12`.
`SavedTranslationRow.swift:7-10` already admits this and calls resolving titles
out of scope — a fair call for three deliberately-saved items, and not a fair
call for a tab that fills automatically and exists to be browsed.

**The backend joins titles at read time from the catalog it already holds in
memory** (`main.py:118` `_require_catalog`, `main.py:173` `_to_summary`), so
`GET /comprehensions` and the single-record GET return `comicTitle` and
`chapterTitle`. Zero storage, always current if a comic is renamed. Snapshotting
titles onto the row at enqueue was rejected as duplicated data that goes stale;
client-side resolution was rejected as a round trip and a cache to buy something
free in-process.

**When the comic is gone from the library** the join misses: the row reads
`已不在書庫` and the jump-to-source button is disabled, since that navigation
would fail anyway.

### Delete becomes routine curation, but keeps its confirmation

Swipe-to-delete on the list row, plus a delete on the detail screen — both
behind the existing confirmation alert (`SavedTranslationRow.swift:98-109`).
The entry point moves from a button to a swipe because every translate now
writes a row, so pruning is something the reader does often rather than rarely;
the confirmation stays because deletion is still irreversible and there is no
undo.

### Empty and unreachable are different screens

```
        ⌛ 還沒有任何紀錄                    ⚠ 連不上伺服器
  翻譯過的句子會自動出現在這裡，          紀錄還在，只是現在讀不到。
  雲端解釋完成後也會回到這一頁。                [ 重試 ]
```

Keeping these distinct is not a polish decision — `translation_store.py:6-13`
already establishes the rule that a read failure must never degrade into an
empty list, because that misrepresents "the store is unreachable" as "nothing
has been saved". The copy also changes in kind from 單字本's "Nothing saved
yet": the reader never chose to save anything, so an empty history is a
statement about the feature, not about their diligence.

### The tab-bar badge

The count of unread records, computed client-side from the fetched list
(ticket 08 — there is no count endpoint), refreshed on app foreground and on
tab appear (ticket 07).

## Comments

Resolved via a `/prototype` + `/grilling` session on 2026-08-05. Variants asset:
[`assets/10-history-tab-variants.md`](../assets/10-history-tab-variants.md).

**Volume was deliberately left unresolved.** The map's fog expected this ticket
to sharpen it, and the honest outcome is that it did not: compact rows took a
screen from ~2 records to ~10 and swipe-delete gave the reader a pruning tool,
so both push the threshold further out — but neither reveals where it is. A
default `?limit=200` was considered and rejected: without a "load more" it makes
old records **silently unreachable**, which is worse than slow. The fog stays,
rewritten more precisely.

Consequences pushed onto other tickets:

- **[08](08-history-record-data-model.md)** — the list and single-record
  responses gain `comicTitle`/`chapterTitle`, joined from the catalog and
  nullable when the comic is gone.
- **[12](12-client-removal-boundary.md)** — `VocabularyView`/`SavedTranslationRow`
  are replaced rather than repurposed, but the `ReaderRoute` +
  `navigationDestination` jump-back pattern and the delete-confirmation alert
  both survive and should be reused.
