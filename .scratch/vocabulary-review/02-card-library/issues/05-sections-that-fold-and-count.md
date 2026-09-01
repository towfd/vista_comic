Status: done — device-verified by the repo owner, 2026-09-01

# 05 — Sections that fold, and say how many

**What to build:** The two headings in 單字庫 become collapsible, each one carrying its own count, and each one looking like something rather than like a plain grouped list.

A follow-up to ticket 03, raised by the repo owner after living with the tab. The deck is now long enough that scrolling past every word to reach the sentences is the normal way to use the screen, and the screen never says how much is in it — a workshop should be able to tell you what is on the bench.

## Folding

- **Both sections start collapsed.** Opening the tab shows the headings and their counts: two or three rows, the whole deck summarised, nothing to scroll.
- **The state is not remembered.** Leaving the tab and coming back starts collapsed again. This is the repo owner's call and it is the cheaper one — no stored state, no migration, nothing to go stale — and it fits a screen whose whole premise is that it is rarely opened.
- **A search expands everything, and clearing it collapses again.** Not asked for, decided here, and it is the one place the two rules above would otherwise fight: search is one of the two ways a reader arrives at this screen (`StudyView.swift`'s header comment names both), and typing a word only to be shown a collapsed heading would answer the question with a number instead of the card. Say so on the ticket if this should be a manual expand instead.
- The offline notice stays where it is — outside the sections, above them. It is a fact about the whole list, and burying it inside a fold would let the reader read stale data with no warning.

## Counting

- Each heading carries the number of cards in **that section**: `Words 24`, `Sentences 8`.
- **While a search is active the number is the matching count**, not the total. The list under the heading is the matches, so a total there would describe something not on screen — and the reader searching "khi" wants to know how many they found.
- Empty sections stay dropped, as `groupedByKind` already does. A `Sentences 0` heading is an invitation to fix a section that has nothing wrong with it.
- The unclassified section counts the same way. It is the one whose number is a to-do rather than an inventory, which is a reason to show it, not to hide it.

## Colour

The repo owner asked for this screen to look like more than a list. **Give each section its own identity, and stop there** — the accent, not a redesign of the row.

- Reuse the existing asset colours (`practiceTeal` / `practiceTealDeep`, `primaryRed` / `primaryRedDeep`, `grayFont`). No new colorsets, no third palette invented for this screen. The app has two colour families and they already mean something.
- Words and sentences get different accents; unclassified stays the quiet one — grey, unaccented. It is work waiting, not a category to be proud of.
- The count is part of the heading's treatment, not a stray grey number: a pill, a coloured numeral, whatever reads as one object with the title.
- Dark mode is not optional. Every colour here comes from an asset catalogue entry that already has both appearances; anything hard-coded fails this ticket.

**What this must not become** is the display case. Two features that existed to be looked at have already been deleted from this app. Colour here is so the eye lands on the right heading in one look, and a heading that is now a fold target needs to look tappable at all. It is not a reason to add card artwork, progress bars, or a summary dashboard at the top.

## Blocked by

Nothing. Ticket 03 shipped; this changes the screen it built.

## Acceptance criteria

- [x] Opening 單字庫 shows the section headings collapsed, with no card rows visible
- [x] Tapping a heading expands it; tapping again collapses it
- [x] Leaving the tab and returning shows the headings collapsed again
- [x] Each heading shows the number of cards in that section
- [x] With a search active, every section is expanded and each count is the matching count
- [x] Clearing the search collapses the sections again
- [x] A deck of only words shows one heading, not an empty `Sentences 0`
- [x] The unclassified section counts and folds like the others, and keeps the quiet treatment
- [x] The offline notice is visible without expanding anything
- [x] The empty-deck state and the no-matches state are both unchanged
- [x] Every colour comes from the asset catalogue and is checked in both light and dark appearance
- [x] Counting and grouping stay free functions in `CardLibrary.swift` and are unit tested; the view holds only the fold state
- [x] No XCUITest is written, built, or run — the device checklist is the deliverable

## File boundary

- `vista_comic/vista_comic/Features/Study/StudyView.swift`
- `vista_comic/vista_comic/Features/Study/CardLibrary.swift`
- `vista_comic/vista_comic/Features/Study/components/` — only if a section header earns its own view
- `vista_comic/vista_comicTests/` — the counting tests
- `Assets.xcassets` only if an existing colour genuinely cannot serve, and then say why in the report

Everything above is ticked: the unit-tested half by the suite, the visual half by the repo
owner's device pass on 2026-09-01, which passed with no changes asked for.

## What was built

- `CardGroup.accent` in `CardLibrary.swift`, beside `title` — the same decision, which heading
  this is, and drawn from the app's two existing colour families. `nil` for unclassified.
- `components/CardSectionHeader.swift` — a band, a count pill, and a chevron that rotates. It is
  a `Button` with `.buttonStyle(.plain)`, because a bordered style's tinted label fights the band
  behind it.
- `StudyView.openSections`, a `Set<String>` of `CardGroup.id`, cleared in both `.onAppear` and on
  returning to `.active`. **Clearing it is the feature**: a tab keeps its state while the reader
  is elsewhere, so "not remembered" had to be done rather than assumed.

**Two decisions worth review:**

1. **A search overrides the fold rather than mutating it.** `isExpanded` is
   `isSearching || openSections.contains(id)`, so clearing the field returns to whatever the
   reader had open instead of to a state the search invented.
2. **The count is `group.cards.count` and nothing else.** `groups` is built from the matches, so
   the heading is structurally incapable of describing rows that are not underneath it — which
   is what the search-count criterion actually needs, rather than a second count computed
   alongside.

## Verification

`xcodebuild test -only-testing:vista_comicTests` on iPhone 16 (18.1): **533 tests, 0 failures**,
2 skipped, about 165 seconds end to end. Four new tests in `CardLibraryTests.swift`
(`What a heading says about its section`).

Not verified here, by rule: everything visual. No XCUITest was written, built, or run.

## Device checklist for the repo owner

1. Open 單字庫. Both headings are **closed**, each with a number, and no card rows are visible.
2. Tap a heading — it opens, the chevron turns. Tap again — it closes.
3. Open a section, switch to another tab, come back: **closed again**. Same after backgrounding
   the app and returning.
4. The numbers match reality. Count the words in one section against its heading.
5. Search for something you have. **Every section opens**, and each number becomes what was
   found, not the total. Clear the field: back to closed.
6. Search for something you do not have — the "no matches" screen, not the empty-deck one.
7. **Both appearances.** Light and dark, for the two coloured bands and the quiet unclassified
   one. The unclassified heading must stay readable without shouting.
8. **Compact and larger phone.** A long heading with a three-digit count must not push the pill
   off the row.
9. Airplane mode with a cached deck: the "saved on this device" line is visible **without**
   opening anything.
10. Tapping a row still opens the card, and coming back from an edit does not reopen or close
    any section unexpectedly.
