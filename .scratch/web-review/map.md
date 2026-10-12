# Web review — wayfinder map

## Destination

**A spec, ready to write, for the thinnest path that lets the reader finish a real review session in the browser.** Not the whole of part ⑥ of [the web client's six-part split](../web-client/issues/09-the-six-part-split.md): a first slice of it, cut the way `.scratch/web-reader-mvp/` was cut from parts ② and ③. The reason for the effort is that reading already happens on the web and review should close the loop in the same place. **The web asks two question types and only two: cloze typed, and translate.** Both are answered at the keyboard, which is what a desk is for; four choices and rearranging stay on the phone.

The map is done when the slice's contents are named, every decision that slice depends on is made, and what is left over is listed in an order. At that point the slice goes to `/to-spec`.

**That point has been reached** (2026-10-12): no ticket is open. The slice is defined in [The thin slice](issues/02-the-thin-slice.md) and goes to `/to-spec` next, grilled one question at a time before it is written. What remains under *Not yet specified* is small enough to be asked there, or belongs to the spec after this one.

**The spec is written:** [`spec.md`](spec.md), 2026-10-12. This map stays the record of why; the spec is what gets built.

## Notes

- **The architecture is already locked and is not reopened here.** [`.scratch/web-client/map.md`](../web-client/map.md) is the architecture of record. Three of its decisions are load-bearing for this map: the web writes its own question generation in TypeScript; scheduling always comes from `POST /cards/{id}/reviews`, with no second copy of the state machine; and the iOS app is not modified — the backend may gain endpoints, never change one.
- Everything the slice needs from the backend already exists: `GET /cards`, `POST /cards/{id}/reviews`, `GET`/`PUT /study/settings`, `PATCH`/`DELETE /cards/{id}`. A decision that seems to need a new endpoint should say so explicitly.
- The web today is three routes (library, comic, reader) in Vue 3 + Pinia + Tailwind, with vitest. It has no card code and no navigation shell.
- The iOS source being ported is `vista_comic/vista_comic/Features/Study/` — the pure-logic files import no SwiftUI — and its tests in `vista_comicTests/`.
- Consult `/grilling` and `/domain-modeling` for open questions; `/prototype` where the question is how something should feel under a keyboard and mouse.
- The spec is grilled before it is written, one question at a time — the developer's standing preference.
- UI verification is the developer's. A ticket that needs something tried in a browser hands over a list of what to look for.
- Conversation is in Traditional Chinese; this repo's documents stay in English.

## Decisions so far

- [What the engine must reproduce](issues/01-what-the-engine-must-reproduce.md) — normalisation ports exactly for Vietnamese given the right JavaScript forms (the obvious ones are wrong); translate costs ~13 lines and is the only mode that can ask every card, the two clozes ~100 together with their matching, rearrange ~65, the queue ~55; and the phone never waits for a review response, which the web cannot copy. Full inventory in [`assets/engine-inventory.md`](assets/engine-inventory.md).
- [The thin slice](issues/02-the-thin-slice.md) — the first spec holds the two question types, the ported queue, **real reviews** (a slice that wrote nothing could never end a session), the settings page with writing, and fixing a card mid-practice. Only entering from the reader waits until after. Two of three extras were taken against the recommendation of none, so this slice is thicker than the reader MVP was.
- [Keeping two engines in step](issues/05-keeping-two-engines-in-step.md) — no parity standard: agreement with the phone is judged by the developer in use. The Swift tests are a reference for whoever writes the engine, never an acceptance criterion; the engine is still unit-tested on its own terms. The one thing use cannot show is a count the two devices compute differently.
- [Where practice lives](issues/06-where-practice-lives.md) — the web's first shell: a top bar, 書庫 · 練習, on every page but the reader, with the count of cards waiting beside 練習 (no number if that fetch fails). `/practice` is an overview — due, new, in learning, a start button — chosen over opening straight onto a question; the session is `/practice/session` and settings `/practice/settings`.
- [Fixing a card mid-practice](issues/09-fixing-a-card-mid-practice.md) — on the feedback screen only, once the review is saved: change the translation, change the kind, reset, or delete. The source text cannot be edited — the endpoint refuses it by design — so a misread card can only be deleted. The answer already given stands; there is no undo and none is added.
- [The queue under two clients](issues/03-the-queue-under-two-clients.md) — each review response updates its own card; the whole deck is fetched on entering, when the tab returns to the foreground, and before the day is called done. A question on screen is never swapped out. The server already refuses a doubled review answer and tolerates a doubled learning one, so the one accepted gap is the new-card allowance, which only the clients count. The clock is read per question, and `today` is the local calendar day, as on the phone.
- [An answer that cannot be posted](issues/07-an-answer-that-cannot-be-posted.md) — the verdict shows at once, the next question waits for the review response, and a failed post holds the session there, retrying with the same token and the same `answeredAt`, until it is saved. No skipping and no browser storage: closing the tab loses that one answer. A deleted card (404) leaves the session; a lapsed Access session needs a sign-in.
- [Old and new tone placement](issues/08-old-and-new-tone-placement.md) — `hoà` and `hòa` are one answer: the web compares which tone each syllable carries, not which vowel wears the mark, so strictness still catches a wrong or missing tone. Judging only; card identity and deck-word matching stay exact. A tone on the wrong vowel passes too, accepted.
- [Typing Vietnamese at a desk](issues/04-typing-vietnamese-at-a-desk.md) — a plain field works: the input method composes per syllable and delivers NFC, so Enter is ignored while composing and nothing is judged before submission. **The web is strict about tones — one tone wrong is wrong — where the phone forgives and names it**; the two devices can now give one answer two verdicts, which was stated and accepted. Typed questions are workable in the first slice.

## Not yet specified

- **Entering practice from the reader.** In scope, and the one thing placed after the first spec: something at the end of a chapter that says cards are due. It does not need deciding before the first spec is written, only before the second. The count in [the navigation bar](issues/06-where-practice-lives.md) already tells the reader cards are due from the library and the comic page; this is about the one place the bar is hidden.

## Out of scope

- **Cloze with four choices, and rearranging.** Ruled out by the developer on 2026-10-12, not deferred: the web asks cloze typed and translate, and nothing else. This narrowed the destination, which had first been charted as all four types in some order. Consequences: no distractor selection and no piece tray are ported, and a sentence card is asked more often by production on the web than on the phone, where recognition is one of four draws.
- **Endless training** (永無止盡的訓練). Ruled out by the developer while charting: the web gets one entrance, the one that schedules.
- **Any change to the iOS app, a scheduler on the web, or question generation in the backend.** All three were settled on the web client's map and are not reopened.
- **Collecting cards on the web** — part ④, which waits on the OCR service. The deck practised here is whatever the phone collected.
- **The card library screens** — part ⑤, beyond the one corner named above.
- **Answering with no network.** The web has no offline requirement; that is the whole reason it needs no scheduler of its own.
- **The game layer** — parked on its own map, `.scratch/vocabulary-review/07-game-layer/`.
