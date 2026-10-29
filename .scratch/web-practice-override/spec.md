Status: ready-for-agent

# Web practice override: count a wrong answer as right

## Problem Statement

The web practice session judges a typed answer in the browser and saves it the moment it is submitted. The judge is strict, so an answer the reader knows is right — a variant spelling, an acceptable different wording — is sometimes marked 不對, and the card is rescheduled as a miss. There is no way to say "that was right".

## Solution

When an answer is judged wrong, the feedback screen offers 算我對 beside 下一題, and the answer is **not saved yet**. Pressing 算我對 saves it as correct and the screen changes to 正確（已改判）, still showing what was typed and what was expected; 下一題 then moves on. Pressing 下一題 without it saves the answer as wrong and moves on, as today. A correct answer is saved at once, as today.

## User Stories

1. As a reader, when my answer is judged wrong, I want an 算我對 button, so a right answer the judge did not accept counts as right.
2. As a reader, I want pressing it to change the screen to 正確（已改判）, so I can see it took.
3. As a reader, I want the override saved the moment I press it, with no way back, so there is nothing left to remember.
4. As a reader, I want 下一題 (and Enter) on a wrong answer to save it as wrong and move on, exactly as before.
5. As a reader, I want an overridden answer counted as correct in the session's tally and schedule.
6. As a reader, I want a correct answer to behave exactly as now.

## Implementation Decisions

- Web only; no backend or iOS change. The review is sent with `isCorrect: true` — the backend's existing path. Nothing records that it was overridden.
- In the session store, a wrong verdict prepares the review but does not send it. Two actions finish it: **count as correct** (verdict becomes correct and marked overridden, the review is sent with `isCorrect: true`) and **advance** (sends the review as wrong if unsent, then moves on once saved — the existing wait-for-save behaviour).
- The review keeps the moment the reader answered (`answeredAt`, `localDate`), not the moment they chose.
- Saving, retries, failures and the 存好之前不會出下一題 rule are unchanged once a review is sent.
- 算我對 is offered only while the wrong answer is unsent; it disappears once pressed.
- Enter on the feedback screen stays 下一題, so Enter on a wrong answer accepts it as wrong.

## Testing Decisions

- Session store (vitest, existing seam): a wrong answer is not sent until a choice is made; count-as-correct sends `isCorrect: true` with the original `answeredAt`, marks the verdict correct and overridden, and counts as correct; advance on an unsent wrong answer sends it as wrong and moves on once saved; count-as-correct is ignored on a correct answer or once sent; a correct answer is still sent at once.
- No component tests; the developer checks the screen (device checklist on the ticket).

## Out of Scope

- iOS.
- Recording that an answer was overridden, or reverting an override.
- Changing how answers are judged.
- Keeping an unsaved wrong answer across closing the tab: closing the tab before choosing loses that answer.
