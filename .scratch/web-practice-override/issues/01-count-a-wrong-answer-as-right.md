# 01 — Count a wrong answer as right

**What to build:** On the web practice feedback screen, a wrong answer is held unsent and offers 算我對 beside 下一題. 算我對 saves it as correct and shows 正確（已改判）; 下一題 saves it as wrong and moves on. See [the spec](../spec.md).

**Blocked by:** None — can start immediately.

**Status:** done (2026-10-29) — on `feature/web-practice-override`; shown to the developer locally, device checks pending

**Notes from implementation**

- Pressing 算我對 removes the button, so focus moves to 下一題 and Enter still moves on.
- Checked in the browser against a local API and database: wrong → 算我對 → 正確（已改判）, saved → Enter → next question.

**Acceptance criteria**

- [x] A wrong answer is not sent until 算我對 or 下一題 is pressed; a correct one is sent at once
- [x] 算我對 sends the review as correct with the original answer time, shows 正確（已改判）, and disappears
- [x] 下一題 / Enter on an unsent wrong answer sends it as wrong and moves on once saved
- [x] The session tally counts an overridden answer as correct
- [x] Save failure and retry behave as before once a review is sent
- [x] Vitest covers the store; the web suite and `vue-tsc` pass

**Developer device checklist**

- A wrong answer: 算我對 → 正確（已改判） → 下一題
- A wrong answer: 下一題 (and Enter) → next question, counted wrong
- The end-of-session tally includes the overridden answer as 答對
