# 17 — The settings page

**What to build:** The reader can see and change the learning steps and the number of new cards per day at `/practice/settings`. A value the scheduler could not use is refused before it is sent, and a saved change shows at once in the overview's numbers and beside 練習.

See the spec's *Settings*.

**Blocked by:** 10 — Today's deck on the overview.

**Status:** ready-for-agent

- [ ] The API client can write study settings, sending both fields whole
- [ ] The page shows the current learning steps, in minutes, and the daily allowance
- [ ] Learning steps need at least one entry and every entry above zero; the allowance must be zero or more; a violation is explained and nothing is sent
- [ ] A save that fails is reported and the entered values are kept
- [ ] After a save the held settings are replaced, so the overview and the bar's count follow without a reload
- [ ] The overview's settings control leads here, and there is a way back
- [ ] Unit tests cover the validation and the client call
- [ ] The write is confirmed once through the dev proxy against the real backend
- [ ] Hand-off: a list for the developer covering a changed allowance showing in the count and on the phone, and each refused value
