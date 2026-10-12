# 17 — The settings page

**What to build:** The reader can see and change the learning steps and the number of new cards per day at `/practice/settings`. A value the scheduler could not use is refused before it is sent, and a saved change shows at once in the overview's numbers and beside 練習.

See the spec's *Settings*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** done (2026-10-12) — merged in #114; the browser checklist below is still the developer's to run

- [x] The API client can write study settings, sending both fields whole
- [x] The page shows the current learning steps, in minutes, and the daily allowance
- [x] Learning steps need at least one entry and every entry above zero; the allowance must be zero or more; a violation is explained and nothing is sent
- [x] A save that fails is reported and the entered values are kept
- [x] After a save the held settings are replaced, so the overview and the bar's count follow without a reload
- [x] The overview's settings control leads here, and there is a way back
- [x] Unit tests cover the validation and the client call
- [x] The write is confirmed once through the dev proxy against the real backend
- [x] Hand-off: a list for the developer covering a changed allowance showing in the count and on the phone, and each refused value

## Comments

Implemented 2026-10-12. 252 unit tests pass; the type check and production build are clean. The page was not opened in a browser, and **the real settings were not changed**.

**The `PUT` through the dev proxy** was confirmed with a body the API refuses — an empty step list — which came back as FastAPI's own 422. The settings read back afterwards were still `[5, 7, 10]` / `15`.

The page fetches the settings fresh every time it opens, so it never saves an old value back over one changed on the phone. Learning steps are typed the way the phone takes them: `5, 7, 10`, with commas, spaces or both.

Not addressed, as the spec leaves it: what a changed setting does to a session already running. Settings is its own page, so a session is always left to reach it; the next session starts from the new values.

**For the developer to check in the browser.** Saving here changes the real settings, for the phone too.

- ⚙ 設定 on the overview opens the page with the current values — the same as the phone's settings screen. ← 總覽 goes back.
- Change the daily number, 儲存: 已儲存 appears; back on the overview 新卡 and the count beside 練習 reflect it without a reload; the phone shows the new value.
- Clear the steps field, or enter `5, 0`, `5, x` or `2.5`, and save: a message under the field, no request in the network panel, and what you typed is still there.
- Enter `-1` or nothing for the daily number: the same.
- Stop the backend and save a valid change: a message says it was not saved, and the fields keep what you entered.
- Set the daily number to 0: no new cards are offered and 新卡 is 0.
- Put the values back to what they were.
- A narrow window: the form fits without scrolling sideways.
