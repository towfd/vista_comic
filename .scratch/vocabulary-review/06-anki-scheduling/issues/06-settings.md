Status: implemented on branch `feat/anki-offline`, 2026-08-31

# 06 — Settings

**What to build:** The gear in the 練習 tab: learning steps and new cards per day.

Steps are a list — the reader can change 5/7/10 to 5/10 or to 5/7/10/20 — because "how many
steps" and "how long each step is" are the same question. New cards per day is a single number,
default 15.

Stored on the backend, cached locally, **and not editable with no connection**: the backend
recomputes schedules on flush, so two copies that disagree produce two different `due_at` values
for the same answer. When offline, the screen says so rather than accepting an edit it cannot
keep — the same rule `OfflineFallbackStudyRepository` already applies to editing a card.

Changing the steps does not reschedule cards already in flight; a card mid-way through the old
list finishes on the new one at the same index, clamped.

**Blocked by:** 04.

- [ ] Steps and new-card count round-trip and survive an app restart
- [ ] A card in learning survives a steps change without a crash or a due date in the past
- [ ] Editing with no connection is refused and explained
- [ ] Invalid input is rejected in the app, not only by the backend
- [ ] Both phone layouts

## What was built

`StudySettingsView`, reached by the gear on the practice tab's start screen —
and only there, because changing the step lengths mid-session would reschedule
the card on screen.

**The steps are a text field**, parsed by `parseLearningSteps`. A half-typed
list has to be a state the screen can be in; parsing on every keystroke and
snapping the field back would fight the reader mid-edit. Which makes the parser
where every bad value is caught, so that is where the tests are: an empty list
has no first step for a lapse to return to, and a zero-minute step would
schedule a card to be due before it was answered.

`5.5` is refused rather than rounded. The backend stores whole minutes, and
rounding the reader's number without saying so is the kind of quiet disagreement
this stage exists to remove.

**Offline shows an explanation, not a form.** Rendering the defaults and
accepting a save would write values the reader never chose over the ones they
did.
