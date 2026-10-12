Type: grilling
Status: resolved
Blocked by: 01

# Keeping two engines in step

## Question

Two parallel implementations were chosen with the drift cost accepted. That settles that there are two; it does not settle how the second one is known to be right on the day it is written.

The phone's rules are pinned by `ClozeQuestionTests`, `DeckWordMatchingTests`, `SentenceAnswerTests`, `PracticeQueueTests` and `PracticeRoundTests`. Are those cases re-typed by hand into vitest, lifted into a fixture file both suites read, or is only the judging — where a disagreement means the same answer is right on one device and wrong on the other — held to parity while question selection is free to differ?

A shared fixture would have the iOS tests read a new file, which brushes against "the iOS app is not modified".

## Answer

**There is no parity standard. Whether the web's practice agrees with the phone's is judged by the developer using it.**

Three ways of proving agreement on the day the engine is written were put forward — re-typing the roughly sixty relevant Swift cases into vitest, each naming the test it came from (recommended); holding only judging and deck-word matching to parity, about twenty-eight cases; or the first plus a vector file kept on the web side for the day the iOS tests may be touched. The developer declined all three: *"我自己感覺就好"* — his own sense of it is enough.

What that does and does not mean:

- **The phone's test suite is a reference, not an obligation.** Whoever writes the engine may read `ClozeQuestionTests`, `DeckWordMatchingTests`, `SentenceAnswerTests`, `PracticeQueueTests` and `PracticeRoundTests` to learn the rules; nothing requires a case-for-case port, and no ticket should carry "matches the Swift tests" as an acceptance criterion.
- **The engine is still tested** — on its own terms, like every other module in `web/`. That is how the web is built, not a parity mechanism, and this answer does not waive it.
- **A shared fixture was never available**: it would have the iOS tests read a new file, which is a change to the iOS app.

The scope it would have covered, for whoever reads the Swift tests as reference — of 99 tests, about 60 concern what the web builds: cloze building 7 and typed judging 7, deck-word matching 14, sentence judging 7, the queue 24, askable modes 6. The rest are distractors, rearranging and the training entrance, all out of scope.

**Where "by feel" cannot see.** Stated once, not as an objection: a wrong verdict or an odd question is visible to the person answering; a new-card allowance or a count of cards remaining that the two devices compute differently is not — each device only ever shows its own number. [The queue under two clients](03-the-queue-under-two-clients.md) fixes the inputs (the local-day string, the learn-ahead window) so the spec has the rule written down even with no test tying it to the phone.

## Comments

Per [What the engine must reproduce](01-what-the-engine-must-reproduce.md): 99 tests pin the five files; no randomness is injectable in the Swift code, so cases about which word is blanked or which distractors are drawn cannot be replayed as-is; and the existing shared normalisation vector table has no Vietnamese vector.

Per [Typing Vietnamese at a desk](04-typing-vietnamese-at-a-desk.md): judging is no longer identical by intent. The web marks a missing tone wrong; the phone marks it correct. Whatever parity this ticket settles on has to exclude that case rather than be broken by it.

Per [Old and new tone placement](08-old-and-new-tone-placement.md): a second intended difference. The web treats `hoà` and `hòa` as one answer; the phone grades the pair "correct apart from tones".

Resolved 2026-10-12. The developer answered outside the options offered. The two intended differences noted above — strict tones, and tone placement — need no carve-out after all, since there is no parity for them to be carved out of.
