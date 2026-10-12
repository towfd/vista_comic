Status: implemented (2026-10-12) — tickets 10–18 merged in #107–#115; none of it has been checked in a browser yet, which is the developer's

# Web review: finish a real review session in the browser

Charted on [the web review map](map.md); every decision below traces to a resolved ticket there. Implementation tickets are `issues/10` to `issues/18`; `01`–`09` in that directory are the map's decision tickets, all resolved. Architecture comes from [the web client map](../web-client/map.md) and is not reopened.

## Problem Statement

The web client can read manga and keeps reading progress in step with the phone, but it has no part of the other half of the product. Cards collected while reading can only be practised on the phone. A reader who has just finished a chapter at the computer has to pick up another device to review, and nothing on the web even says that cards are waiting.

The phone's practice is also built for a thumb. At a desk there is a keyboard and a Vietnamese input method, and the two question types that ask the reader to *produce* Vietnamese are exactly the ones a keyboard is good at.

## Solution

The web gains practice: an overview of what is waiting today, a session that asks typed questions until the queue is empty, a settings page, and a way to fix a card from the question that exposed it. It works on the same deck and the same schedule as the phone — an answer given in the browser moves the card for both devices.

- A **navigation bar** on every page except the reader, reading 書庫 · 練習, with the number of cards waiting beside 練習.
- An **overview** at `/practice`: due, new and in-learning counts, a way into settings, and a start button.
- A **session** at `/practice/session` that asks two question types and only two — **cloze typed** and **translate** — and runs until nothing is left, then reports what happened.
- **Strict judging**: a wrong or missing tone is wrong. This departs from the phone on purpose.
- A **settings page** at `/practice/settings` for the learning steps and the daily allowance of new cards.
- **Fixing a card** after the verdict: change its translation or kind, reset it, or delete it.

Nothing in the backend or the iOS app changes. Every endpoint this needs already exists.

## User Stories

**Getting there**

1. As the reader, I want a navigation bar on the library and comic pages, so that I can reach practice from wherever I am without going back through the library.
2. As the reader, I want the reader itself to stay free of that bar, so that manga keeps the whole screen.
3. As the reader, I want the number of cards waiting shown beside 練習, so that I know review is due without opening it.
4. As the reader, I want the library to load and work normally when that number cannot be fetched, so that a problem with cards never costs me my manga.
5. As the reader, I want that number to match what the session says is left, so that the two never tell me different things.

**The overview**

6. As the reader, I want to see how many cards are due, new, and in learning before I start, so that I can decide whether I have time now.
7. As the reader, I want to start a session with one press, so that the overview does not get in the way.
8. As the reader, I want to be told plainly when I have collected no cards at all, so that I know to go and collect some rather than wait.
9. As the reader, I want to be told plainly when everything due has been done and the day's new cards are spent, so that I know to come back tomorrow.
10. As the reader, I want a clear error with a retry when the deck cannot be loaded, so that I am not left looking at an empty overview that might be wrong.

**Answering**

11. As the reader, I want to be shown a sentence I collected with one of my own words blanked and its meaning, and to type the missing word, so that I produce the word with the sentence still in front of me.
12. As the reader, I want to be shown a meaning alone and to type the whole Vietnamese line, so that I produce it from memory.
13. As the reader, I want a word card to be asked by translation, so that cards that appear in no sentence are still practised.
14. As the reader, I want the question type drawn at random from what a card supports, so that I cannot predict the easy form.
15. As the reader, I want the blank to be the least familiar of my words in that sentence, so that practice lands where I am weakest.
16. As the reader, I want Enter to submit my answer, so that I never reach for the mouse.
17. As the reader, I want Enter pressed while my input method is still composing a syllable to finish the syllable and not submit, so that a half-typed word is never judged.
18. As the reader, I want nothing judged while I am still typing, so that the page does not flag a missing tone on a syllable I have not finished.
19. As the reader, I want Enter on an empty field to do nothing, so that a stray keypress cannot record a wrong answer.
20. As the reader, I want case, spacing and — for whole sentences — punctuation ignored, so that I am tested on the words and not on typing.
21. As the reader, I want word order to count, so that the test covers where Vietnamese grammar actually lives.
22. As the reader, I want a wrong or missing tone marked wrong, so that tones are something I am held to at a keyboard where typing them costs nothing.
23. As the reader, I want `hoà` and `hòa` treated as the same answer, so that I am not marked wrong for my input method's convention differing from the scanlation's.

**Feedback and moving on**

24. As the reader, I want the verdict the instant I submit, so that judging never waits on the network.
25. As the reader, I want my answer and the card's text shown one above the other when I am wrong, so that I can see the difference myself.
26. As the reader, I want Enter to take me to the next question, so that a session flows from the keyboard.
27. As the reader, I want the next question to appear only once my answer is saved, so that I am never asked a card whose schedule is still in the air.
28. As the reader, I want to see that the page is waiting when I press on before the save has finished, so that it does not look frozen.
29. As the reader, I want a running count of what is left, so that I know how far I am from done.
30. As the reader, I want never to be asked the same card twice in a row when another is available, so that I am not answering from short-term memory.
31. As the reader, I want to be able to stop a session and return to the overview, so that I can leave part-way without losing what I answered.

**When saving fails**

32. As the reader, I want a failed save retried on its own a few times, so that a blip costs me nothing.
33. As the reader, I want to be told when my answer is still not saved, with a retry button, so that nothing is lost silently.
34. As the reader, I want the session to stay on that question until the answer is saved, so that what I see next is always based on the true schedule.
35. As the reader, I want a retried answer never to count twice, so that a response lost on the way back does not double-step a card.
36. As the reader, I want a retried answer scheduled from when I answered, not from when the network came back, so that a learning step is not stretched by an outage.
37. As the reader, I want a card I deleted on the phone mid-session to drop out quietly, so that the session carries on.
38. As the reader, I want to be told to sign in again when my Access session has lapsed, so that I am not left retrying something that cannot succeed.

**Finishing**

39. As the reader, I want the session to end when the queue is empty and not after a fixed number, so that "finished" means finished.
40. As the reader, I want a closing screen that says how many I got right and wrong and how many cards graduated, so that I see what the session achieved.
41. As the reader, I want the deck checked once more before I am told I am done, so that cards answered or collected on the phone meanwhile are accounted for.

**Two devices**

42. As the reader, I want an answer given on the web to move the card on the phone too, so that the two feel like one deck.
43. As the reader, I want the web to notice what I did on the phone when I come back to the tab, so that I am not asked what I just answered.
44. As the reader, I want a question already on my screen to stay there even if its card changed elsewhere, so that what I am typing is never taken away.
45. As the reader, I want a tab left open overnight to behave correctly at the next question, so that I need not reload it in the morning.
46. As the reader, I want the day's allowance of new cards shared with the phone, so that using two devices does not double my new cards.

**Fixing a card**

47. As the reader, I want to correct a card's translation from the feedback screen, so that a wrong meaning is fixed where I noticed it.
48. As the reader, I want to change a card's kind between word and sentence, so that a mis-tapped save is put right.
49. As the reader, I want to reset a card to new, so that a card whose history was earned against a wrong translation can start again.
50. As the reader, I want to delete a card, with a confirmation, so that a misread bubble stops coming back.
51. As the reader, I want those actions available only after my answer is saved, so that a reset cannot race the answer it is meant to wipe.
52. As the reader, I want the rest of the session to reflect a fix at once, so that a deleted card is not asked again and a reset card returns as a new one.

**Settings**

53. As the reader, I want to see and change the learning steps on the web, so that I need not pick up the phone to tune them.
54. As the reader, I want to see and change the number of new cards per day, so that I can throttle or open up new material from the desk.
55. As the reader, I want an invalid setting refused with a reason before it is sent, so that I do not save something the scheduler cannot use.
56. As the reader, I want the waiting count to follow a changed allowance straight away, so that the bar and the overview are not stale after a save.

## Implementation Decisions

### What is built

- **A card and study layer in the API client** — the web's first calls about cards: list the deck, record a review, read and write study settings, update a card, reset a card, delete a card. They go through the client's existing request path so Access refusals, 404s and outages are classified exactly as they are for comics.
- **A practice engine**, pure TypeScript with no Vue in it: text keys and judging; finding deck words in a sentence and building a cloze; the queue. Clock and randomness are passed in, never read inside.
- **A deck store** holding the deck and the settings, shared by the navigation bar, the overview and the session.
- **A session store** that drives one session: current question, verdict, save state, outcome.
- **Views**: the overview, the session, the settings page, and a navigation bar in the application shell. The library's own heading yields to the bar.

### Question types

- Exactly two: **cloze typed** (recorded as `cloze_typed`) and **translate** (recorded as `sentence_typed`). Cloze with four choices and rearranging are not built.
- A card supports cloze typed when it is a sentence card and contains at least one *other* card's text as a whole word, where removing that word does not leave the sentence empty. Every card supports translate.
- The type is drawn uniformly from what the card supports. A word card, a card with no kind, and a sentence containing no deck word are therefore always translate.
- **The cloze blank** is the matched deck card with the lowest ladder stage; a tie goes to the match that appears earliest in the sentence. The prompt is the sentence with that word removed, plus the sentence's translation.
- **The translate prompt** is the card's translation alone.

### Judging

Strict about tones, and differing from the phone in two intended ways.

- Case and all whitespace are ignored. For translate, punctuation and symbols are ignored as well; for cloze they are not — as on the phone.
- Word order matters.
- A cloze answer is right when it equals either the word as it was written in the sentence or the matched card's own text.
- **A wrong or missing tone is wrong.** The phone's "correct apart from tones" verdict does not exist here; a verdict is right or wrong.
- **Tone placement is folded.** Per whitespace-separated syllable, the five tone marks (grave, acute, tilde, hook above, dot below) are compared as a set, apart from the letters with their circumflex, breve and horn. `hoà` equals `hòa`; `hoà` does not equal `hoá`, `hoa`, or `toi` against `tôi`. A tone on a vowel neither convention would pick also passes; that is accepted.
- The folding is judging only. Finding deck words in a sentence stays exact, so two words differing by tone remain two words.
- An empty or whitespace-only field cannot be submitted.

**The text keys must be written in specific forms** to agree with the phone and the backend for Vietnamese; the obvious JavaScript spellings do not. Established by running all three implementations (see Further Notes):

- compatibility-compose, strip Unicode `White_Space`, lower-case — not `\s`, which differs on U+0085 and U+FEFF;
- strip marks by the fixed combining range U+0300–U+036F after decomposing, with `đ` mapped by hand since it does not decompose — not the general mark category;
- punctuation as Unicode punctuation and symbol categories.

Two further traps in finding deck words: JavaScript's word boundary is ASCII-only, so it would find `ÀO` inside `CHÀO`; and matching must work on whole characters with canonical equivalence, not code units.

### The queue

Ported from the phone, minus the training entrance.

- Order: learning and relearning cards due now; then other cards due now; then, if the day's allowance has room, new cards in the order they were collected; then learning cards coming due within twenty minutes. Within a group, longest-waiting first.
- The card just asked is skipped when another candidate exists.
- The day's allowance is `newCardsPerDay` minus the cards whose `introducedOn` is today.
- An empty queue distinguishes an empty deck from a finished day.
- **Remaining** is the due-now count, plus new cards capped by the allowance left, plus learning cards inside the twenty-minute window. It is zero exactly when the queue has nothing to offer. The overview's three numbers are this figure taken apart, and the navigation bar shows its total.
- **The clock is read each time the queue is asked.** No timers; a tab on the closing screen learns that a step came due when the reader returns to it.
- **`today` is the browser's local calendar day** as `yyyy-MM-dd` — not the UTC day, and not the 04:00 scheduling day. The phone resets the new-card allowance at local midnight, and the two devices share the allowance only by producing the same string.

### Answering and saving

- On submit the answer is judged in the browser and the verdict shown at once. The review is posted in the same moment.
- **The next question is not offered until the response has arrived.** Enter on the feedback screen advances; pressed early, the control shows it is waiting.
- The response's scheduling fields are written onto that card in the held deck. No scheduler exists on the web.
- A review carries the question type, whether it was correct, a token generated once per question, the local date, the moment of answering, and the review context. Elapsed time is not sent.
- **Failure** — the backend unreachable, a server error, a timeout: retried automatically a few times with the same token, the same moment of answering and the same local date. Still unsaved, the feedback screen says so and offers a retry; there is no way past it and nothing is written to browser storage. Closing the tab loses that one answer.
- **Not retried:** a 404 means the card was deleted elsewhere — it leaves the session and the next question is offered. An Access refusal means the reader must sign in again. Any other refusal is shown as unsaved with the manual retry.
- Starting values, to be tuned in use: three automatic attempts, backing off over a few seconds; a request counted as timed out after ten seconds. The API client has no timeout today and gains one.

### When the deck is fetched

- On any page that shows the navigation bar, in the background, for the count. A failure there shows 練習 with no number and nothing else.
- On opening the overview and on starting a session — deck and settings together. Here a failure is an error state with a retry, not a silent fallback to default settings: the web has no offline case to excuse guessing the allowance.
- When the tab becomes visible again.
- When the queue comes up empty, once more before the closing screen; only if it is still empty is the session over.
- **A question on screen is never replaced** by a fetch. The new deck applies from the next question.
- Accepted gap: with the tab visible throughout and the phone introducing new cards, the web can exceed the day's allowance until the next fetch. The server refuses a doubled answer to a review card and tolerates one to a learning card; the allowance is the only thing it does not guard.

### The session's edges

- Reloading the session route starts the queue again from the server. Nothing is lost, since each answer was saved before the next was shown.
- A stop control returns to the overview.
- **The closing screen** reports correct, wrong, and graduated — a card counts as graduated when its state after an answer is review, and stops counting if a later answer in the same session takes it out again. These live only in the session's memory.

### Fixing a card

- Offered on the feedback screen, enabled once the review is saved.
- Change translation and change kind go through the card update; reset and delete through their own endpoints. The held deck is updated from each response — no full fetch.
- After a translation change the card keeps its place in the schedule. After a kind change, later questions are built from the deck as it now stands. After a reset the card is new and returns under the allowance. After a delete it is gone; delete asks for confirmation.
- **The source text cannot be changed.** The update endpoint refuses it by design and is not altered. A misread card is deleted and collected again on the phone.
- **The answer just given is not taken back.** There is no undo and none is added.

### Settings

- Two fields, read and written whole: learning steps as a list of minutes, and new cards per day.
- Validated before sending to the backend's own rules: at least one step, every step above zero, the allowance zero or more.
- After a save the deck store's settings are replaced, so the count and overview follow.

### Feedback

- Right: the verdict and the card's text.
- Wrong: the reader's answer and the card's text, one above the other. No label for a tone-only miss and no per-syllable highlighting.

### Navigation and routes

- The bar is part of the application shell and is hidden on the reader route. It stays visible during a session.
- `/practice` overview, `/practice/session` session, `/practice/settings` settings. A question has no address.

### Environment

- Runs as the reader does today: through the dev proxy to the existing backend. The proxy forwarding `POST`, `PATCH` and `DELETE` is unproven — only `GET` and `PUT` have been through it.
- The web's strings are Traditional Chinese, matching the existing views.

## Testing Decisions

A good test here states what the reader is asked or told for a given deck, settings, clock and answer — never how the module arrives at it. Tests pass the clock and the random source in.

**No test asserts parity with the phone.** That was decided on the map: agreement between the two engines is judged by the developer in use. The phone's test files are worth reading to learn the rules; no ticket carries "matches the Swift tests" as an acceptance criterion.

Three seams, all already used in the web project:

- **The practice engine, as pure functions.** Prior art: the reader's progress and next-chapter tests.
  - Judging: exact; case, spacing and punctuation; word order; wrong tone; missing tone; missing circumflex or horn; both tone placements equal; a different tone on the same syllable unequal; empty input; cloze accepting either spelling of the word; precomposed against combining input.
  - Finding deck words and building a cloze: found and blanked intact; not inside a longer word, including a non-ASCII one; punctuation as a boundary; a tone difference is no match; least-familiar chosen; tie by position; a word that is the whole sentence is not blanked; word cards and kindless cards yield none.
  - The queue: each ordering rule; the allowance and its exhaustion; the learn-ahead window at, inside and outside twenty minutes; no immediate repeat and the one-card deck; empty deck against finished day; remaining is zero exactly when the queue is empty; the local-day string across the UTC boundary.
- **The API client, with an injected fetcher.** Prior art: the client's existing tests. Each new call's method, path and body; the review body's fields; a 404, an Access redirect, a 5xx and a timeout each classified correctly.
- **The session store, with the API client mocked.** Prior art: the comics and chapters store tests. Verdict before the response; no next question until it lands; automatic retries reuse the token and the moment of answering; unsaved state after retries are spent; 404 drops the card and advances; refetch on visibility and before the closing screen; the on-screen question surviving a refetch; the deck after each fixing action; fixing actions disabled until saved; the outcome's graduated count going up and back down.

**Components are not tested**, as nowhere else in the web project.

**Browser verification belongs to the developer**, per `CLAUDE.md`. The checklist, at minimum:

- The bar shows on the library and a comic page and not in the reader; the number beside 練習 matches the overview's three numbers added together.
- Stop the backend and load the library: manga still loads, 練習 shows no number, no error appears.
- With the Vietnamese input method on, an answer ending in a word with no punctuation takes two Enters — one to finish the syllable, one to submit — and is never submitted half-composed.
- Enter on an empty field does nothing.
- Typing `hoa` for a card reading `hoà` is wrong; typing the other tone placement for a card that has such a word is right.
- A translate answer without its closing full stop is right.
- After a wrong answer, both lines are shown; Enter moves on; focus is back in the field without a click.
- In the network panel, each answer is one `POST` and nothing else; the next question never appears before it returns.
- Throttle the network to offline mid-session and answer: the feedback screen reports the answer unsaved, the session will not advance, and restoring the network then retrying saves it exactly once.
- Answer on the web, open the phone: the card has moved. Answer on the phone, return to the tab: the count has changed and that card is not asked.
- Delete a card on the phone while it is on screen in the browser, then answer it: the session carries on to the next card.
- Each fixing action from the feedback screen, and its effect on the rest of the session; delete asks first.
- Change the daily allowance in settings: the bar and overview follow without a reload, and the phone shows the new value.
- Finish a session: the closing screen's numbers are right, and the overview then says the day is done.
- An empty deck shows the collect-some-cards state, not the done-for-the-day one.
- One narrow window and one wide one for the overview, a question, feedback with the fixing actions open, and settings.
- Every request goes to the dev server's own origin.

## Out of Scope

- **Cloze with four choices, and rearranging** — ruled out for the web, not deferred.
- **Endless training.**
- **Entering practice from the reader** — the next slice after this one.
- **The card library screens** beyond the fixing actions here, and **collecting cards on the web**.
- **Any change to the iOS app or to an existing backend endpoint**, including making the source text editable.
- **A scheduler on the web**, and **question generation in the backend**.
- **Answering with no network**, and any store of unsent answers in the browser.
- **Undoing a review.**
- **Labelling a tone-only miss, or highlighting differences**, in feedback.
- **A third verdict** for a differing tone placement.
- **Parity tests against the phone**, and any fixture shared between the two test suites.
- **Timers that wake an idle tab** when a learning step comes due.
- **Safari**, third-party input methods that rewrite text rather than compose, and touch keyboards — none was measured.
- **The game layer.**

## Further Notes

- **Two intended differences from the phone**, both in judging: tones are strict, and tone placement is folded. One toneless answer advances a card on the phone and lapses it on the web, so where a card is answered now shapes its schedule. That was stated and accepted.
- **This slice is thicker than the reader MVP.** Two extras — settings and fixing a card — were taken in against a recommendation of none. Expect more tickets than that spec's three, with the engine and the card layer of the API client as the foundations the rest stands on.
- **Sources.** The rule-by-rule inventory of the phone's logic, the API fields, and the normalisation runs are in [`assets/engine-inventory.md`](assets/engine-inventory.md). It was produced by a research subagent and marks what was run against what was only read; it has not been re-verified line by line. The input-method behaviour was measured once, in Chrome on macOS with a Telex input method, and is recorded in [Typing Vietnamese at a desk](issues/04-typing-vietnamese-at-a-desk.md).
- **A card that looks broken at first sight must still be answered with something** before it can be fixed, since an empty field cannot be submitted and the fixing actions appear only after the verdict. The answer will be recorded as wrong; if the card is then deleted or reset, that record goes with it.
- **What use cannot show.** A wrong verdict is visible to the person answering. A count the two devices compute differently is not — each only ever shows its own. With no parity tests, the rules for the allowance and for what remains are held only by this spec and the engine's own tests.
- **`docs/api-contract.md` does not cover the card routes.** The backend's models are the reference.
