Type: grilling
Status: resolved

# Client-side removal and replacement boundary

## Question

Graduated from two fog patches on the map that ticket 08 made specifiable: it removed `POST /comprehend` and `POST /translations` outright, which decides the fate of a large amount of shipped iOS code from both `ocr-translation` and `llm-comprehension`. What survives, what is replaced, and what is deleted?

The affected surface:

- `Networking/Comprehender.swift` — protocol, `ComprehensionResult`, `ComprehensionError`, and its `EnvironmentKey`. The app never calls Claude directly any more.
- `Networking/APIComprehender.swift` — including the `~1024px` downscaling that moves to Python (ticket 08).
- `Networking/TranslationRepository.swift` / `APITranslationRepository.swift` / `SavedTranslation.swift` — `save`/`list`/`delete` against endpoints that no longer exist.
- `Features/Vocabulary/VocabularyView.swift` and `components/SavedTranslationRow.swift` — the tab being replaced by 歷史紀錄 (ticket 03).
- The free functions in `Features/ComicPage/ComicView.swift`: `comprehendOrTranslateSelection` (`:842`), `upgradeComprehension` (`:889`), `saveSelection` (`:921`), and the `SelectionTranslateOutcome` enum they share.
- Their tests: `APIComprehenderTests`, `SelectionComprehensionFlowTests`, `SelectionSaveFlowTests`, `VocabularyDeleteFlowTests`, `SavedTranslationTests`, `APITranslationRepositoryTests`.

Decide:

- Which files are deleted outright versus renamed/rewritten in place. **[Ticket 10](10-history-tab-ui.md) settled the shape**: `VocabularyView`/`SavedTranslationRow` are **replaced**, not repurposed — the tab moves from a `ScrollView` of expanding cards to a `List` of compact rows pushing a detail screen, so almost no layout survives. Two things explicitly do survive and should be reused rather than reinvented: the `ReaderRoute` + `navigationDestination` jump-back pattern (`VocabularyView.swift:29-36`, `SavedTranslationRow.swift:160-167`) and the delete-confirmation alert. What is left to decide is file/directory naming and whether `Features/Vocabulary/` is renamed or a new directory is created alongside it.
- What the new client seam looks like — one repository protocol covering the six `/comprehensions` endpoints, or something narrower — and whether it keeps `TranslationRepository`'s environment-injection convention.
- What replaces `comprehendOrTranslateSelection` now that the flow is "translate on-device, then enqueue" rather than "call cloud, fall back to on-device". Note the on-device `Translator`/`AppleTranslator` seam is untouched by all of this and stays.
- ~~What happens to `upgradeComprehension`~~ — **answered by [ticket 09](09-reader-result-screen-states.md), which unblocked this ticket:** the upgrade action is removed entirely, so `upgradeComprehension`, `isUpgrading`, `upgradeError`, `upgradeButton` and the upgrade alert are all deleted rather than rewritten. What replaces it is a second inline picker next to the language picker, backed by `UserDefaults` exactly like `LastUsedTargetLanguage` (`ComicView.swift:1478-1484`), whose value rides along in the enqueue body as `useStrongerModel`. Note this makes `LastUsedTargetLanguage` a pattern to copy, not delete.
- Which existing tests are rewritten against the new seam versus deleted as testing behaviour that no longer exists.

The project rule "avoid broad refactors while implementing a focused feature" cuts both ways here: this *is* the feature, but the boundary should still be drawn deliberately rather than by drift.

## Answer

Roughly **1,150 lines of production code and 1,550 lines of tests** are in scope.

### A gap this ticket found: what happens when the *on-device* translation fails

Ticket 02 promoted the on-device `Translator` from "fallback on failure" to
"always runs first", but nobody asked what happens when the fast path itself
fails — and it does fail, distinctly enough that
`TranslationError.languagePackUnavailable` already has its own message
(`ComicView.swift:1303-1305`). Ticket 08 then made `translated_text` NOT NULL,
so there is literally nothing to create a record from.

**Decision: no record is created, and the existing translation-failure UI with
its retry stands (`ComicView.swift:1281-1311`).** The backend is never called
and no quota is spent. This is coherent rather than merely convenient: the fast
translation *is* the product of this map, so if it never arrives there is no
"here's something immediately" to record.

Making `translated_text` nullable and letting the cloud supply the only
translation was rejected — it puts the reader back in front of a screen with
nothing on it for several minutes, which is precisely the experience this map
exists to remove.

### The replacement for `comprehendOrTranslateSelection`

The flow inverts: translate on-device, *then* enqueue. That makes two
independently-failing steps where M9 had one, so the return type has to say
more than `LoadState<SelectionTranslateOutcome>` did. Mirroring that type's own
shape (`ComicView.swift:810-833`):

```swift
enum SelectionEnqueueOutcome {
    case recorded(translation: String, record: ComprehensionRecord)
    case notRecorded(translation: String, reason: NotRecordedReason)
}

enum NotRecordedReason {
    case quotaExhausted   // 429 — permanent for today, no retry offered
    case transient        // network/server — retry offered
}
```

wrapped as `LoadState<SelectionEnqueueOutcome>`, where **`.failed` means only
that the on-device translation failed**. An enqueue failure is deliberately not
`.failed`: the reader does have their translation, so it is a variant of
success — "translated, but not recorded" — and modelling it as failure would
make the screen throw away something it actually has.

The `quotaExhausted` / `transient` split follows
[ticket 09](09-reader-result-screen-states.md)'s `declined` / `failed` rule
exactly: distinguish by whether retrying can possibly help, and give a retry
button only to the case where it can.

It stays a free function alongside `translateSelection` and
`recognizeSelection`, unit-testable against stubs independently of SwiftUI —
the convention those two already establish.

### The client seam

**One `ComprehensionRepository` protocol covering all six endpoints** —
`enqueue`, `list`, `get(id:)`, `markRead(id:)`, `retry(id:)`, `delete(id:)` —
with an `EnvironmentKey` defaulting to the concrete `APIComprehensionRepository`,
exactly as `TranslationRepository` does today. One resource, one seam. HTTP
plumbing copies `APITranslationRepository.swift:85-149`: every request built
through `APIConfig.authorizedRequest` for the Cloudflare Access headers, and
`APIConfig.iso8601Decoder` for dates.

Splitting into reader-facing and history-facing protocols was rejected —
`markRead` is needed by both, so the split would need two protocols pointing at
one implementation, a pattern this codebase has nowhere. Dropping the protocol
entirely was rejected because every flow test in this project
(`SelectionSaveFlowTests` and friends) is written against stub conformers.

### File disposition

| | Files |
| --- | --- |
| **Delete** | `Comprehender.swift`, `APIComprehender.swift`, `TranslationRepository.swift`, `APITranslationRepository.swift`, `SavedTranslation.swift`, all of `Features/Vocabulary/` |
| **Add** | `ComprehensionRepository.swift`, `APIComprehensionRepository.swift`, `ComprehensionRecord.swift`, `Features/History/HistoryView.swift`, `Features/History/components/HistoryRow.swift`, `Features/History/HistoryDetailView.swift` |
| **Rewrite in place** | `ComicView.swift`, `RootTabView.swift`, `Localizable.xcstrings` |
| **Untouched** | `Translator.swift` / `AppleTranslator.swift` / `translateSelection`, the whole `OCRRecognizer` family, `ReaderRoute`, `LastUsedTargetLanguage` |

`LastUsedTargetLanguage` deserves calling out: it looks like 單字本-era code but
it is the **pattern ticket 09's model-tier picker copies**, so it survives and
gains a sibling.

In `ComicView.swift`, removed: `comprehendOrTranslateSelection`,
`upgradeComprehension`, `saveSelection`, `SelectionTranslateOutcome`, the
three-banner `comprehensionBanner`/`banner` pair, the save control, and
`upgradeButton` with its alert. Added: the enqueue free function, the model-tier
picker, ticket 09's `深度解釋` box, and the poll on `GET /comprehensions/{id}`.

### Tests

**Deleted (~1,030 lines), because they test behaviour that ceases to exist:**
`APIComprehenderTests` (388 — the deleted client), `SelectionComprehensionFlowTests`
(355 — the cloud-first-then-fall-back logic that inverts), `SelectionSaveFlowTests`
(287 — manual Save, removed by ticket 03).

**Rewritten against the new seam:** `APITranslationRepositoryTests` (393) →
an `APIComprehensionRepository` equivalent, `SavedTranslationTests` (89) →
`ComprehensionRecord` decoding including the new `status` and title fields,
`VocabularyDeleteFlowTests` (48) → the History tab's delete.

**Untouched:** `SelectionTranslationFlowTests` (123 — on-device translation is
unchanged and now *more* load-bearing than before), plus every OCR, crop,
`AuthorizedAsyncImage`, and `Translator` test.

### Judgment calls made without a separate question

- `Features/Vocabulary/` is deleted and `Features/History/` created fresh, rather
  than a `git mv` — the contents are almost entirely replaced, so preserving file
  history buys little.
- The `Localizable.xcstrings` additions and removals are treated as an
  implementation step for the spec rather than enumerated here.

## Comments

Resolved via a `/grilling` session on 2026-08-05.

Consequences pushed onto other tickets:

- **[09](09-reader-result-screen-states.md)** — two result-screen states this
  ticket surfaced: the on-device translation failing (existing failure UI, no
  record, backend never called) and the enqueue failing transiently (translation
  shown, no record, retry offered) as distinct from the already-specified 429.
