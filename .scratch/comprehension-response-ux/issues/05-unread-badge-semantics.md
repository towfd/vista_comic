Type: grilling
Status: resolved

# Unread badge semantics

## Question

The History tab carries an unread count so the reader knows an explanation they were waiting on has arrived. What increments it, and what clears it?

## Answer

**Only a successfully-arrived explanation counts as unread. The count clears per entry, when that entry is opened.**

Increment rules:

- A cloud explanation returning successfully for a record → **+1 unread**. This is the only thing that increments.
- The fast on-device translation → **never unread**. The reader saw it on screen the moment they asked for it; there is nothing new to come back to.
- A failed, declined, or abandoned call → **never unread**. Nothing new arrived; a badge would be pointing at an absence. The record's retry affordance is how the reader learns about it, at the moment they're actually looking.

Clearing rules:

- **Per entry, on open.** Opening the History tab clears nothing. Only opening a specific record marks that record read and decrements the count. Clearing the whole badge on tab entry was considered and rejected: the stated purpose is "how many explanations came back, so I can go read them," and a reader who opens the tab and gets through two of five would lose the reminder for the other three.
- **An explanation that lands while the reader is still on the result screen is already read.** In that case the screen fills in the explanation live, and no unread is ever recorded for it — badging something the reader is at that moment looking at would be plainly wrong.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map.

The live fill-in on the still-open result screen was confirmed separately as desired behaviour: the reader who waits is rewarded with the explanation appearing in place, and the same state the background call already writes to is what the screen observes — no extra mechanism.

Where the read/unread flag physically lives (server column vs on-device) is left to [History record data model and API shape](08-history-record-data-model.md).

**Amendment from ticket 07** — the semantics above are unchanged, but the implementation is now pinned: [Background comprehension task ownership and observation](07-background-task-ownership.md) chose "backend is the single source of truth, each screen fetches for itself", so the flag is a **server column** (08 only names it) and there is no shared client store. Two consequences for how the badge behaves in practice:

- **The badge only moves while the app is open.** It is refreshed by fetches — on app foreground and on History tab appear — not pushed. An explanation completing while the app is closed is discovered at next launch. This was accepted when polling was chosen over SSE and APNs.
- **"Already read on the still-open result screen" is a write, not a suppression.** The screen polls its own record, and on seeing the explanation land it marks that record read on the server; the next badge refresh simply doesn't count it. There is no in-memory coordination between the result screen and the badge.
