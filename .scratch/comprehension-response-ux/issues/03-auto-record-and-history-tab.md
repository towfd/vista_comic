Type: grilling
Status: resolved

# Auto-record replaces manual save; 歷史紀錄 replaces 單字本

## Question

Once the explanation arrives after the reader may already have dismissed the result screen, it needs somewhere to land. What is that place, where does it live in the app, and what happens to the existing manual Save action and 單字本 tab?

## Answer

**Every Translate automatically creates a record — no manual Save — and the 單字本 tab becomes a 歷史紀錄 (History) tab in the same tab-bar slot.**

The premise, stated by the developer: saved vocabulary is rarely revisited in practice. Their actual reading behaviour is to select anything unfamiliar, read the explanation once, and move on. That makes a curated "saved items" list dead weight and makes an automatic, complete history the thing that's genuinely useful — especially now that an explanation can arrive *after* the reader has moved on.

Locked details:

- **Recording is automatic and immediate.** The record is created when Translate is tapped, carrying the fast on-device translation, and appears in History right away — not when the cloud explanation returns.
- **The manual "Save" button is removed entirely**, along with `saveState`. Leaving it would be semantically incoherent: the record already exists, so a Save button would imply a second, separate copy.
- **The entry point is the tab bar, not the reader.** The developer's first instinct was to put History next to the reader's scan toggle (`ComicView.swift:272`), but an unread badge there would vanish the moment the reader is dismissed — which is exactly the situation the badge exists to survive. `RootTabView`'s existing second tab slot keeps it globally visible. The reader's control bar is unchanged.
- **Existing `saved_translation` rows are disposable.** The developer confirmed that data is not worth keeping, so any storage decision downstream (reuse the table, or replace it) is free of migration constraints.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map.

This supersedes M9's [structured output & persistence](../../llm-comprehension/issues/04-structured-output-and-persistence.md) decision insofar as *when* a record is created (was: on explicit save; now: on every translate) — though its core call, that explanation content is persisted rather than view-only, is reaffirmed and in fact strengthened here.

Whether the new record reuses the `saved_translation` table or replaces it, and what status/read fields it needs, is deliberately left to [History record data model and API shape](08-history-record-data-model.md).
