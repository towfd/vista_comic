Status: ready-for-agent

# Comprehension response UX: an immediate translation, an explanation that arrives later

## Problem Statement

M9 shipped LLM-assisted comprehension, and using it surfaced two problems that make it painful in practice.

First, **the reader waits too long for anything at all**. Tapping "Translate" fires a single cloud call that must produce the translation *and* the whole explanation before the screen shows a word. A Claude call takes tens of seconds, so the reader sits looking at a spinner in the middle of reading a comic — for a result whose most useful part, the literal translation, their phone could have produced almost instantly. Worse, the work belongs to a view: dismissing the sheet or leaving the app throws away everything that was in flight.

Second, **the explanation comes back in an unpredictable language**. The reader picks a target language for the translation, but the grammar, context and tone notes arrive in whatever language the model felt like — most often English. For a reader whose whole purpose is to understand a foreign comic in their own language, an English explanation of Vietnamese is a second thing to decode.

Underneath both sits a design that no longer fits: M9 assumed one call, one wait, one verdict, and a manual "Save" into 單字本 — a vocabulary book the reader confirmed they rarely revisit.

## Solution

Split the single wait in two, and let the slow half outlive the screen.

Tapping "Translate" now runs the **on-device translator first**, so a literal translation appears essentially immediately. The deeper explanation is **enqueued on the backend**, which owns the Claude call from that moment on: it survives the reader dismissing the sheet, leaving the app, or the server restarting. Every translate automatically creates a **history record** — there is no Save button any more — and the 單字本 tab becomes a **歷史紀錄 (History)** tab in the same tab-bar slot, carrying an unread badge so the reader knows an explanation they were waiting on has landed.

If the reader stays on the result screen, the explanation fills in beneath the translation while they watch. If they don't, it is waiting for them in 歷史紀錄. Either way they never wait for it.

The language problem is fixed at its root: the tool schema's explanation fields now state which language to write in, bound to the target-language picker the reader already uses, so the explanation always comes back in the language they read in.

## User Stories

1. As a reader, I want a literal translation the moment I tap Translate, so that I can keep reading without waiting on a slow cloud call.
2. As a reader, I want the deeper explanation to arrive afterwards on its own, so that the wait for it never blocks me.
3. As a reader, I want to see that an explanation is still coming, so that I know the screen isn't broken or finished.
4. As a reader, I want to close the result screen without losing the explanation, so that I can carry on reading immediately.
5. As a reader, I want the explanation to still be produced when I background the app or my phone locks, so that stepping away doesn't waste the request.
6. As a reader, I want the explanation to still be produced if the server restarts mid-request, so that an infrastructure hiccup doesn't silently lose my work.
7. As a reader who stays on the result screen, I want the explanation to appear in place when it lands, so that waiting is rewarded rather than punished.
8. As a reader, I want the explanation written in the same language I chose to translate into, so that I don't have to decode a second foreign language.
9. As a reader, I want the explanation to quote the original wording it is discussing, so that I can connect the explanation to the actual sentence.
10. As a reader, I want every translation recorded automatically, so that I never lose something by forgetting to save it.
11. As a reader, I want a 歷史紀錄 tab in place of 單字本, so that what I actually produce while reading has a home.
12. As a reader, I want a badge on that tab counting explanations that have arrived and not yet been read, so that I know when there is something new to go and read.
13. As a reader, I want the badge to count only explanations that actually arrived, so that it never points me at a failure or at something I already saw.
14. As a reader, I want the badge to clear one entry at a time as I open them, so that getting through two of five doesn't lose the reminder for the other three.
15. As a reader, I want an explanation that lands while I'm looking at it to count as already read, so that I'm not told to go read something I just read.
16. As a reader, I want the history list to show enough of each record to recognise it at a glance, so that I can find what I'm looking for without opening entries one by one.
17. As a reader, I want records labelled with the comic and chapter they came from, so that I can tell them apart by where I was reading.
18. As a reader, I want to open a record and see the full translation and explanation, so that the list can stay scannable.
19. As a reader, I want to jump from a record back to the exact page it came from, so that I can re-read the scene in context.
20. As a reader, I want that jump to open the page read-only, so that revisiting an old record doesn't move my actual reading position.
21. As a reader, I want to retry a record whose explanation failed, so that a transient network problem isn't permanent.
22. As a reader, I want retry to require opening the record, so that I can't spam expensive calls by mis-tapping in a long list.
23. As a reader, I want a record the model declined to explain to say so plainly and offer no retry, so that I don't spend a request to receive the same refusal.
24. As a reader, I want to tell a content refusal apart from a connection failure, so that I don't go looking for a network problem that doesn't exist.
25. As a reader, I want to swipe a record away, so that clearing out entries I don't care about is quick.
26. As a reader, I want deletion to ask for confirmation, so that a stray swipe doesn't destroy something I wanted.
27. As a reader, I want to choose how deep an explanation I want before translating, so that I'm not asked to wait a second time for a better answer.
28. As a reader, I want that choice remembered, so that I don't reset it on every selection.
29. As a reader, I want to be told immediately when the daily request limit is used up, so that I understand why nothing is being recorded.
30. As a reader, I want my on-device translation even when nothing can be recorded, so that a backend problem still leaves me able to read.
31. As a reader, I want to know when the history list can't be loaded, as distinct from being empty, so that I don't think my records are gone.
32. As a reader with no records yet, I want the empty tab to explain what will appear there, so that it reads as a feature I haven't used rather than a failure.
33. As a reader whose comic has been removed from the library, I want its old records to still be readable, so that deleting a folder doesn't corrupt my history.
34. As a reader, I want the jump-to-page button disabled for a record whose comic is gone, so that I'm not offered navigation that must fail.
35. As a reader whose on-device language pack isn't downloaded, I want the existing clear error and retry, so that I can fix the actual problem.
36. As a developer, I want the backend to own the queue, so that no client-side lifecycle rules decide whether paid work completes.
37. As a developer, I want concurrent Claude calls capped, so that a bug can't burn the daily quota in minutes.
38. As a developer, I want the daily quota reserved when work is enqueued, so that the queue can never be longer than the remaining budget.
39. As a developer, I want a reservation refunded only when the request never reached Claude, so that the guard doesn't under-count real spend.
40. As a developer, I want a per-attempt timeout well below the SDK default, so that one hung call can't hold a worker slot for ten minutes.
41. As a developer, I want the backend to downscale page images itself, so that moving the call server-side doesn't multiply per-request cost.
42. As a developer, I want no images stored anywhere, so that the record stays small and the library remains the only copy.
43. As a developer, I want one client seam for the whole comprehension resource, so that the app has fewer network protocols than it does today.
44. As a developer, I want the drainable unit of worker behaviour callable synchronously, so that its tests don't depend on threads or sleeps.

## Implementation Decisions

### The backend owns the work

The comprehension call moves out of the app entirely. The app's responsibility ends when it enqueues; the backend runs the Claude call and writes the result back. This reverses M9's client-owned call and is what makes the work survive sheet dismissal, app backgrounding, and container restarts.

The deciding fact is that the backend already holds every page image on local disk and serves it from the media endpoint — so a deferred call can reconstruct everything it needs from the record alone.

### The record row is the queue row

`saved_translation` is **dropped and recreated** as a new `comprehension_record` table. There is no Alembic in this project: the schema is created with `CREATE TABLE IF NOT EXISTS`, which will happily add a table but never a column. Since a manual drop is unavoidable either way, the rename costs nothing extra and stops the name lying about what the rows are — they are no longer a reader's deliberate saves.

Columns: the source text; the **on-device** translation (written at enqueue, never modified); the cloud translation (nullable, written on success); the three explanation note fields (nullable); the target language; the comic id, chapter id and page number; a status; a read flag; the model tier to use; the UTC date the quota reservation drew from; and a creation timestamp.

`status` is a single column with five values — `pending`, `running`, `ok`, `declined`, `failed` — and is the **only** discriminator. M9's convention of "all three note columns are NULL means translation-only" is dead: it cannot distinguish pending from failed, which is the entire point.

One column serves both readers of the row. The worker claims atomically with an `UPDATE ... WHERE status = 'pending' ... RETURNING`; the UI renders `status` directly. Splitting outcome and queue state into two columns was rejected because it admits illegal combinations that then need an invariant nobody enforces.

The model tier is stored on the row rather than passed per call, because the worker runs minutes after enqueue and must know which model to use.

### The worker

A polling loop started in the existing lifespan handler, running as a **plain daemon thread, not an asyncio task**. This backend is entirely synchronous, so an asyncio worker would have to wrap every database read and write in a thread hop — introducing the codebase's first sync/async seam purely as an artifact of how the loop was started. A thread leaves the question absent rather than displaced.

**Recovery on restart is a blanket update of `running` back to `pending` at startup.** This is exactly correct rather than merely convenient: the container runs a single uvicorn worker, so if the process has just started, nothing can still be executing and every `running` row is by definition orphaned. No heartbeat, no lease expiry, no claim timestamp.

Because of that, **`pending` genuinely means "still running"**, which is what lets the UI avoid inventing a "this has probably died" state. FastAPI `BackgroundTasks` was considered first and rejected precisely because a restart would strand rows in a state indistinguishable from work in progress.

**Concurrency is capped at 3, FIFO by creation time.** The cap exists to bound Claude spend, not to protect threads — with one user and a default thread pool of 40, thread contention does not bite at this scale. **3 is a tunable constant, not a load-bearing premise.** Strictly serial was rejected as needlessly slow when three selections are made on one page.

**The per-attempt Claude timeout is 120 seconds.** The SDK is currently constructed with no timeout, taking its 600-second default, so one hung call could hold a slot for over ten minutes. A real call is ten to thirty seconds, so 120 already means something has gone wrong. Note this is per attempt: with the SDK's own retries left in place, a worst-case job occupies its slot for roughly six minutes.

### Images

Every call is now deferred and no image is ever stored, so the worker's only source is the library on disk — at full scan resolution. Downscaling to a 1024px long edge currently happens on iOS, and the backend has no image library at all, so **Pillow becomes a backend dependency** and the worker downscales before encoding. Sending raw scans would cost several times more per call and risk the model's size limits.

Uploading a pre-downscaled image at enqueue was rejected: it contradicts the no-stored-images rule and puts an upload on the one request whose entire purpose is to return instantly. **The selection crop leaves the flow altogether** — it was never stored, and a deferred call cannot reproduce it — so every comprehension request is page-image-only.

### Endpoints

The synchronous comprehend endpoint is **removed**, along with its request-payload size guard (no client uploads images any more). The comprehension client module stays as the Claude seam the worker calls directly. Six endpoints replace it and the translations endpoints:

- enqueue a record, returning a pending record immediately
- list records, newest first
- fetch one record
- mark one record read
- retry one record (failed only), which re-enqueues and re-reserves quota
- delete one record, refunding its reservation if it was still pending

The enqueue body carries the source text, the on-device translation, target language, comic id, chapter id, page number, and the model tier — no images. Responses stay camelCase to match the existing iOS contract.

**List and single-record responses also carry the comic and chapter titles**, joined at read time from the catalog the backend already holds in memory, and nullable when the comic has left the library. The record itself stores only ids, which are truncated SHA-1 hashes — fine as opaque keys, unusable as the label on a browsable list. Joining rather than snapshotting keeps renames correct and duplicates nothing.

Retry gets its own path rather than a status-setting patch: re-enqueueing is a domain action with its own precondition and its own quota reservation, and handing the client arbitrary status transitions would leak the state machine into the API.

### Quota

The daily cap guard moves from the comprehend endpoint to the enqueue endpoint, so an exhausted cap still returns 429 **immediately, with no record created**, and the queue can never be longer than the remaining quota.

**The reservation is taken at enqueue and settled only when the request never reached Claude** — the row was deleted while pending, or the worker failed before issuing the call. Anything that reached Claude keeps its count, including a declined result, which produced billable tokens. The reservation's UTC date is stored on the row and refunds go back to *that* date: the counter is keyed by UTC day, so a job reserved at 23:59 and run at 00:00 would otherwise hand the new day a free request.

Full settlement (refunding Claude-side errors too) was rejected: the SDK's own retries mean a "failure" may already have partially billed, and refunding failures is exactly what would let a retry-loop bug run free — which is the guard's only purpose.

Nothing cancels an enqueued job. M9's per-call cancellation is gone, and this reservation model is what replaces the cost protection it provided.

### Explanation language

Validated against real calls rather than assumed. Unmodified, the notes come back in **English** — not a random language, but the language of the prompt itself — while the translation is unaffected because its schema description is the only one naming the target language.

**The fix is one sentence appended to each of the three explanation fields' `description` in the tool schema, naming the target language by its BCP-47 code.** The prompt text needs no change. The bare code proved as reliable as spelling the language out by name, and choosing it means the backend never has to maintain a code-to-name table synced with the app's picker.

From the live spike, the decision-carrying part:

```python
"grammarNotes": {
    "type": "string",
    "description": (
        "Notes on the sentence's grammar/structure. "
        f"Write this field in {target_language_code}."
    ),
},
# the same one-sentence suffix on contextNotes and toneRegister
```

The schema is currently a module-level constant and must become a function of the target language code — the only non-trivial part of the change. Compliance was 18 of 18 note fields across 6 calls on the default model tier, with the original wording correctly quoted inside the translated prose.

### The reader's result screen

M9's verdict banner is **deleted**, and its two jobs split. "Is more coming?" becomes a `深度解釋` section standing where the explanation will render, so the waiting indicator is exactly where the answer will appear. "Which translation am I reading?" becomes a small provenance chip on the translation column itself, flipping from on-device to cloud when the cloud version replaces it — which is what makes the text changing under the reader legible.

The cloud translation takes display precedence, falling back to the on-device one, so pending, failed and declined records naturally show the device translation with no extra flag. Both are stored, which also leaves this presentation choice cheap to revisit.

The `深度解釋` section's states:

- `pending` and `running` share one message. With a concurrency cap of 3 a single reader only queues by selecting a fourth passage in quick succession, and a queue position is not something they can act on. The distinction stays in the data for other consumers.
- `ok` replaces the section with the three note fields.
- `failed` shows a message and a **retry**.
- `declined` shows a different message and **no retry** — retrying would spend quota to receive the same verdict. M9 kept these two visually distinct on purpose; that intent survives, carried by copy and by what the reader can do rather than by colour.
- Quota exhausted at enqueue renders inline in the same slot: the reader keeps their translation, but nothing was recorded and there is nothing to retry.
- A **transient enqueue failure** renders in that slot too, with different copy and a retry, since retrying can actually help.

The screen polls the single-record endpoint while its record is pending or running, and marks the record read when the explanation lands while the reader is still watching.

### The model tier becomes a preference, not an action

M9's "request a stronger explanation" action is **removed entirely**. Under a queue it would mean a second multi-minute wait on the very screen this work exists to stop blocking. It is replaced by a **model-tier picker sitting beside the existing target-language picker**, chosen before translating and persisted per device — copying the pattern the language picker already establishes, since this app has no settings screen and its only existing preference works exactly this way.

The trade accepted: the tier is now global, so choosing the stronger model applies to every call. **The spec's implementer must check the actual price ratio between the two model tiers and record it next to the daily cap**, because the cost profile of the whole feature now moves with one picker.

### 歷史紀錄

A flat, newest-first list of compact two-line rows: an unread dot and the source text, then a status glyph, comic and chapter, and relative time. Tapping pushes a detail screen that reuses the result screen's vocabulary — translation with provenance chip, the `深度解釋` section in whichever state applies, source line, jump-to-page, delete.

Opening the detail is what marks a record read. **Retry lives only there**, which is how it stays hard to trigger by accident from a list of many rows.

Grouping by comic and chapter was rejected: a reader working through one long series collapses into a single enormous section, and a just-arrived explanation stops being reliably at the top — which is where the thing the badge points at wants to be.

The list is a real list view with **swipe-to-delete**, a change from today's card scroll, because every translate now writes a row and pruning becomes routine. The deletion confirmation stays: it is still irreversible and there is no undo.

M9's peek-mode jump back to the source page survives unchanged, and is disabled for a record whose comic has left the library.

Empty and unreachable are distinct screens. This is not polish — the existing store convention already forbids degrading a read failure into an empty list, because that misrepresents "the store is unreachable" as "you have nothing". The empty copy also changes in kind: the reader never chose to save anything, so an empty history is a statement about the feature, not about their diligence.

The unread badge counts unread records, computed client-side from the fetched list. There is no count endpoint: the backend stays the single source of truth.

~~Refreshed when the app returns to the foreground and when the tab appears. There is no shared client store: each screen fetches for itself, so marking read is a write whose effect simply shows up on the next refresh.~~ **Reversed by ticket 22, after shipping.** This gave the badge a refresh policy that could only learn something had arrived at the exact moments the reader no longer needed telling — translate, dismiss the sheet, keep reading, and nothing fetched the list until the reader opened the tab the badge was supposed to send them to. It contradicted user story 12 outright.

The per-screen-fetch rule was the right call for the *list*, which only matters while it is on screen, and the wrong call for the *badge*, whose whole job is to speak while the reader is somewhere else. So badge ownership sits in the tab shell, not in 歷史紀錄, and it is kept current two ways: a refresh on launch and on return to the foreground, catching anything that finished while the app was dead or backgrounded; and a watch on a record known to be in flight, handed over when the reader translates, polling until the backend reaches a terminal status. Nothing in flight means no polling — the mechanism is silent on a day the reader never translates. Each half covers the other's hole: watching alone loses anything enqueued before a relaunch, and refreshing alone either misses the arrival by minutes or polls all day to avoid it.

The shared store this rejected is therefore unavoidable, and is kept to the size of the job: a count, a recount from a list a screen already holds, and a watch on one record. 歷史紀錄 hands over the list it just fetched rather than causing a second one.

The counting rule never changed and is not implicated: a reader who dismisses the sheet cancels the poll, so nothing marks the record read and it is correctly unread — it was simply never counted again.

### The client seam

One protocol covering all six endpoints, environment-injected with a concrete production default, replacing **both** M9's comprehender protocol and the translation repository — so the app ends with one fewer network seam than it has today. Its HTTP plumbing copies the existing repository's exactly, including the Cloudflare Access header attachment every request already routes through.

Splitting into reader-facing and history-facing protocols was rejected: marking read is needed by both, so it would mean two protocols pointing at one implementation, a pattern this codebase has nowhere.

### What replaces the combined translate-and-comprehend call

The flow inverts — translate on device, *then* enqueue — so there are two independently failing steps where M9 had one. From the domain modelling, the shape that decision produced:

```swift
enum SelectionEnqueueOutcome {
    case recorded(translation: String, record: ComprehensionRecord)
    case notRecorded(translation: String, reason: NotRecordedReason)
}

enum NotRecordedReason {
    case quotaExhausted   // permanent for today, no retry offered
    case transient        // network/server, retry offered
}
```

wrapped in the existing load-state type, where **failure means only that the on-device translation failed**. An enqueue failure is deliberately not a failure: the reader does have their translation, so it is a variant of success — "translated, but not recorded" — and modelling it otherwise would make the screen discard something it actually has.

**If the on-device translation itself fails, no record is created, the backend is never called, and no quota is spent.** The existing translation-failure message and retry stand. The fast translation *is* the product here; if it never arrives there is nothing immediate to record. Making the stored translation nullable and letting the cloud supply the only translation was rejected — it puts the reader back in front of an empty screen for minutes, which is the exact experience this work removes.

### Removals

The comprehender protocol and its API client, the translation repository and its API client, the saved-translation model, and the whole 單字本 feature directory are deleted. The reader screen loses the combined comprehend-or-translate function, the stronger-model upgrade function, the save function, the outcome enum, the three-banner code, the save control, and the upgrade button with its alert.

The on-device translator, the OCR family, the reader-route jump-back pattern, and the persisted target-language preference are **untouched**. The last of those looks like 單字本-era code but is the pattern the new model-tier picker copies — it survives and gains a sibling.

The tab bar's label changes and gains a badge, and the string catalog gains and loses entries accordingly.

### Deployment

**`DROP TABLE saved_translation` is a required manual step**, and must be run before the new build starts. If it is forgotten, table creation silently does nothing and the app fails at runtime with a missing-column error that reads like a code bug rather than a missed deploy step.

**This is intended to be the last manual drop.** Adopting a migration tool is triggered by this schema landing — see Out of Scope.

## Testing Decisions

A good test here exercises externally visible behaviour through the highest existing seam and asserts on outcomes, not on how they were produced. Tests should not reach into the queue's internals, assert on call ordering, or depend on sleeps.

**Backend, all existing seams except one:**

- The Claude call is stubbed by monkeypatching the comprehension client's client-construction function — the seam M9's own comprehension tests already use to run without an API key. Prior art: the existing comprehension test module.
- The six endpoints are tested through `TestClient` over the app, the shape every existing endpoint test module uses. Prior art: the translation and progress endpoint tests.
- The record store is plain functions over a session, tested directly against a throwaway database, mirroring the existing progress and translation stores and reusing their engine fixture.
- **The one new seam is the worker's synchronous drain step** — a function that claims up to N pending rows, runs them, and writes terminal state back. Tests call it directly; the daemon thread is a loop around it holding no logic of its own. This keeps worker tests deterministic with no threads and no waiting.

Worth covering: claiming is atomic and respects the cap and ordering; startup recovery returns orphaned rows to pending; a declined result and an errored result land on different statuses; the quota is reserved at enqueue, refunded only for a request that never reached Claude, and refunded against the reservation's own date across a day boundary; retry is rejected for a record that is not failed; titles are joined for a live comic and null for a removed one.

Image downscaling is a pure function and gets a direct unit test — it does not need a seam, because nothing needs to substitute it.

**iOS, one new seam replacing two:**

- The new repository protocol is stubbed by test conformers exactly as the translation repository is today. Prior art: the existing save-flow, delete-flow and repository test modules.
- The translate-then-enqueue behaviour stays a free function returning a load state, unit-testable against stub conformers independently of any SwiftUI rendering — the convention the existing recognise, translate and save functions already establish. Prior art: the existing selection flow test modules.
- Screen polling needs no seam of its own: driving the stub repository is enough.

Worth covering: the on-device translation failing produces a failure and no enqueue at all; a successful translation with a 429 enqueue produces a not-recorded outcome with the quota reason; a transient enqueue failure produces the transient reason; the cloud translation takes display precedence over the device one when present.

**Tests deleted rather than migrated**, because they assert behaviour that ceases to exist: the comprehender API client tests, the comprehend-then-fall-back flow tests, and the manual-save flow tests. The saved-translation model tests, the translation repository tests, and the vocabulary delete tests are rewritten against the new record and repository. The on-device translation flow tests, and every OCR, crop and image test, are untouched.

For UI-facing work, XCUITest code is written and build-verified as part of the increment but not run here — this environment's simulator cannot reliably initialise the accessibility runner.

## Out of Scope

- **Whole-book or whole-chapter precompute with tap-a-bubble instant display.** The stated long-term direction — OCR plus LLM over an entire comic at import time — replaces this interaction model rather than extending it, and carries an unresolved cost question. Deliberately deferred so a usable version of the current model ships first. **(Amended 2026-08-07: abandoned outright — see `ROADMAP.md`. What this spec shipped is the permanent interaction model, not a first version of something else.)**
- **The OCR text-editing lag.** Tapping recognised text to correct it stalls. A defect needing root-cause diagnosis, with nothing to decide; split out into its own effort.
- **單字本 as a study or review feature** — spaced repetition, quizzing, curation. The tab is being removed, not improved.
- **Adopting a migration tool.** The right call, but infrastructure work rather than a step toward this feature, and writing a migration for a table this work destroys anyway would be wasted. **Triggered by this schema landing**: baseline the post-drop schema, and every change after that is a migration. Whoever picks it up should know the progress table already holds data that would hurt to lose, and that the test suite currently builds its schema through the same create-if-missing path as production.
- **Converting the backend to async.** All routes are synchronous handlers running in a thread pool. At this scale the conversion buys almost nothing, and half-converting is worse than not converting, since a synchronous database call inside an async handler blocks the event loop outright. Revisit when real usage shows the backend being held up, with numbers rather than a hunch.
- **Pagination, archiving or pruning of history.** Every translate writes a record forever. Compact rows and swipe-to-delete both push the threshold further out without revealing where it is; a default row limit was considered and rejected because, without a load-more affordance, it makes old records silently unreachable — worse than slow. Revisit with real row counts.
- **Explanation content quality.** The live spike observed the model occasionally mis-analysing a word. That is translation accuracy, not language compliance, and nothing here addresses it.

## Further Notes

**M9 decisions this supersedes.** This work reverses several of the `llm-comprehension` spec's own locked decisions, and the spec should be read as amended:

- One Claude call producing both translation and explanation → split into an immediate on-device translation and a deferred cloud explanation.
- The on-device translator as a failure fallback → the on-device translator as the primary, always-first path.
- The client owning the comprehension call → the backend owning it as a queue.
- Manual Save into 單字本 → automatic recording into 歷史紀錄.
- A single verdict banner stamped once → a status section plus a provenance chip.
- A per-result stronger-model upgrade action → a per-device model-tier preference chosen before translating.
- Three explanation columns all NULL meaning "translation only" → an explicit status column.

**Two constants are placeholders for judgement, not measurements.** The concurrency cap of 3 and the 120-second per-attempt timeout are both reasoned rather than measured, and should be presented in code as tunable constants with the reasoning attached, not as design premises.

**The model tier's cost ratio is the one unverified number in this spec.** It was deliberately left to implementation to check against current pricing rather than asserted from memory, and it matters more than usual because the tier is now a single global picker rather than a per-result action.

**Sonnet-tier language compliance was not spike-tested.** The default tier complied on every call, and a stronger model failing where the weaker succeeded is not a realistic risk — but it is an assumption, not a measurement, and the tier picker means both will be used.

**The spike artefacts no longer exist.** The language verification was run under a one-off exception to this project's rule against touching code before implementation, and the scripts were deleted immediately afterwards at the developer's request. The wayfinder ticket for that verification is the only surviving record of the evidence, and was written in full for that reason.
