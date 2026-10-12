Status: implemented (2026-10-12) — tickets 01–02 merged in #119 and #121, 03 in review; not yet marked done, which waits on the developer's browser checks

# Web card collection: type a line into the deck while reading

Decided in a `/grilling` session on 2026-10-12. No map was charted: the route was already clear, so the decisions live here rather than in decision tickets. Architecture comes from [the web client map](../web-client/map.md) and is not reopened; this spec takes that map's part ④ (the learning flow) and ships the half of it that does not need recognition.

## Problem Statement

The web client can read manga and practise cards, but it cannot make one. Every card in the deck was collected on the phone. A reader at the desk who meets a line worth keeping has to pick up another device, find the same page, and select the bubble there — or let the line go.

Collecting on the web was planned, but it was parked behind a backend OCR service that has not been built. That dependency is not real. The reader has a keyboard and an input method in front of them, and the backend already accepts a card as plain text. The only thing missing is somewhere to type.

## Solution

The reader gains a collecting panel. It is collapsed to a single button while reading and opens beside the page when asked for, so the manga stays in view while a line is copied from it. The reader types or pastes the source text and its translation, then presses one of two buttons — add as a word, or add as a sentence. The card joins the same deck the phone uses, records which page it came from, and the panel folds away again.

Nothing is recognized and nothing is translated: both fields are the reader's own typing. Recognition on the web is deferred, not abandoned — when it arrives it fills the same source field.

## User Stories

### Opening and closing

1. As the reader, I want a collect button visible in the reader at all times, so that I can start a card the moment a line stops me.
2. As the reader, I want the panel collapsed by default, so that nothing sits beside the manga while I am only reading.
3. As the reader, I want the panel to open when I press the button, with the cursor already in the source field, so that I can start typing at once.
4. As the reader, I want the open panel to sit to the right of the page column, so that the manga I am copying from is never covered.
5. As the reader, I want to keep scrolling the manga while the panel is open, so that I can check the line above or below what I am typing.
6. As the reader on a window too narrow to fit the panel beside the page, I want it to open along the bottom of the window instead, so that I can still collect at any width.
7. As the reader, I want to collapse the panel myself, so that I can abandon a card I decided against.
8. As the reader, I want collapsing to clear whatever I had typed, so that the next time I open the panel it is empty and belongs to the page I am then on.

### Filling in a card

9. As the reader, I want a field for the source text, so that I can type or paste the line as printed.
10. As the reader, I want a field for the translation, so that I can write the meaning in my own words.
11. As the reader, I want both fields to start empty, so that nothing is presented as a machine's guess.
12. As the reader, I want the source field to hold multi-word lines comfortably, so that a full sentence is as easy to enter as a single word.
13. As the reader, I want the source field to stop at the length the deck accepts, so that I am not allowed to type a card that will be refused.
14. As the reader, I want to see how close I am to that limit as I approach it, so that a long line does not stop without explanation.
15. As the reader, I want typing in either field — spaces included — not to count as scrolling the manga, so that writing a card cannot move or record my reading position.
16. As the reader, I want Enter not to submit the card, so that a stray key press never adds a half-written line.

### Where the card came from

17. As the reader, I want the card to record the comic and chapter I am reading without my entering them, so that it carries its origin like a card collected on the phone.
18. As the reader, I want the page fixed at the moment I start typing the source text, so that scrolling away mid-card does not record the wrong page.
19. As the reader, I want the panel to show which page it has fixed, so that I can see what will be recorded.
20. As the reader, I want that page released when the card is added or the panel is collapsed, so that the next card takes the page I am on then.
21. As the reader, I want a source field emptied back to nothing to release the page too, so that starting over on another page records the new one.

### Adding

22. As the reader, I want an add-as-word button and an add-as-sentence button, so that one press both says what the card is and saves it.
23. As the reader, I want both buttons unavailable until the source text and the translation each hold real content, so that every card I collect here can be asked as a question.
24. As the reader, I want text that is only whitespace to count as empty, so that a blank card cannot be submitted.
25. As the reader, I want both buttons unavailable while a card is being saved, so that a double click cannot send it twice.
26. As the reader, I want to see that the save is in progress, so that I know the press registered.
27. As the reader, I want every card collected here to be translated into Traditional Chinese as far as the deck is concerned, so that it is the same card the phone would have made and not a second copy.

### After a card is added

28. As the reader, I want the fields cleared and the panel collapsed once the card is saved, so that I am back to reading without another action.
29. As the reader, I want a brief confirmation naming the line I just added, shown by the collapsed button, so that I know it went in even though the panel has gone.
30. As the reader, I want that confirmation to disappear by itself, so that it does not stay over the manga.
31. As the reader, I want the new card to appear in 字卡庫 without reloading, so that I can go and check it.
32. As the reader, I want the new card counted in the practice overview without reloading, so that the numbers I see are true.
33. As the reader, I want a card collected here to arrive on the phone like any other, so that the two devices keep one deck.

### A card that already exists

34. As the reader, I want to be told when the line I typed is already in the deck, so that I do not believe a new card was made.
35. As the reader, I want to see the translation the existing card holds, so that I can compare it with what I just wrote.
36. As the reader, I want the panel to stay open with my text intact when this happens, so that the wording I typed is not lost before I have read the message.
37. As the reader, I want a link to that card in 字卡庫, so that I can correct its translation or kind there.
38. As the reader, I want a card I had deleted to come back when I collect the same line again, so that I am never told a line is collected and then unable to find it.
39. As the reader, I want changing the text after such a message to clear it, so that the notice always refers to what is currently in the field.

### When saving fails

40. As the reader, I want a failed save to leave the panel open with both fields as I left them, so that a dropped connection does not cost me the line I typed.
41. As the reader, I want a plain message saying the card was not saved, so that I do not assume it was.
42. As the reader, I want to press an add button again to retry, so that recovering needs no new control.
43. As the reader, I want a retry never to create a second card, so that trying again is always safe.
44. As the reader, I want a sign-in failure reported as such, so that I know to re-authenticate rather than keep retrying.

### Correcting a mistake

45. As the reader who mistyped the source text, I want to delete the card in 字卡庫 and collect it again from the reader, so that a typo is not fixed in my deck for good.
46. As the reader who chose the wrong kind or wrote a poor translation, I want to fix it on the card's page in 字卡庫, so that I do not have to re-collect.

## Implementation Decisions

### What is and is not touched

- **The backend is not changed.** The existing card-creation route already accepts everything this feature sends and already answers "new" and "already there" with different status codes. No route, schema, or migration is added.
- **The iOS app is not changed.**
- Three parts of the web client are touched: the API client gains card creation, the deck store gains a way to take in a collected card, and the reader gains the panel — backed by a new collecting store.

### The collecting store

- A new Pinia store owns everything the panel does: whether it is open, the two fields, the fixed page, and the state of a submission. The panel component only renders it, and the reader only feeds it the DOM fact it cannot know — which page is current. This is the arrangement the reader already uses for progress, where the rules sit outside the component.
- The store is scoped to one chapter. It is told the comic and chapter when the reader opens one; leaving the chapter by any route is a collapse.
- **Collapse is a full reset**: fields, fixed page, and any duplicate or failure notice are all discarded. There is no draft and nothing is persisted to browser storage. Reopening always starts empty.
- **The page is fixed on the transition from an empty source field to a non-empty one**, taking the reader's current page at that instant — the same "top-most visible page" the progress rules already define, including the rule that the end-of-chapter block counts as the last page. It is released when the source field becomes empty again, on a successful add, and on collapse. It is not editable.
- If no page has ever been visible when typing starts — possible only before the chapter has rendered — the card cannot be submitted; the panel is not offered until the chapter's pages are on screen.
- **Submission is allowed only when** both fields have real content, the source text is within the deck's length limit, a page is fixed, and no submission is in flight. "Real content" uses the same normalisation the deck's identity uses, so a string the backend would refuse as empty is never sent.
- A submission has four outcomes, and they are the store's observable states:
  - **created** — the store resets, collapses, hands the card to the deck store, and exposes the added line for the confirmation.
  - **already there** — the panel stays open, the fields are kept, and the existing card is exposed so the panel can show its translation and link to it. The card is still handed to the deck store, because a revived card must reappear in the held deck.
  - **failed** — the panel stays open, the fields are kept, and the error kind is exposed. Nothing is retried automatically; the reader presses again.
  - **in flight** — both add actions are refused.
- Editing either field after an already-there or failed outcome clears that notice.
- A submission that resolves after the panel was collapsed, or after the chapter changed, must not reopen the panel or write into the new chapter's state. The card it created is still handed to the deck store.

### The API client

- One new function creates a card from: source text, translation, kind, comic, chapter, and page number. It reports back the card **and whether it was newly created**, derived from the response status — the backend answers one status for a new card and another for an existing one, and that distinction is the only way the client can tell.
- **The target language is fixed to the identifier the phone sends for Traditional Chinese** and is not a parameter of the function. The deck's identity for a card includes the target language, so a different spelling of the same language would create a second card for the same line.
- **Kind is always sent** and is always word or sentence. The web never creates a card of undecided kind.
- No translation provenance is sent. None is stored anywhere today — see the note on the old ticket below.
- Errors map onto the existing error kinds; a refusal by the backend for an unusable source text falls under the existing unexpected kind, which the submission rules above should make unreachable.

### The deck store

- A new action takes one card into the held deck: inserted if absent, replaced if present. It marks the card as changed from this tab using the store's existing mechanism, so a deck load that set out before the card was collected cannot remove it when its older answer arrives.
- A card collected before the deck was ever loaded needs no special handling: the first load fetches it from the server.
- New cards sit where the deck's existing order puts them — newest first.

### The panel

- A collect button belongs to the reader's header and is always present once a chapter's pages are shown. The confirmation after a successful add appears beside it and removes itself after a few seconds.
- Open, the panel is fixed to the viewport so it stays put while the manga scrolls. At widths where the page column and the panel fit side by side, it docks to the right of the column; below that, it docks to the bottom of the window. The page column itself never moves or resizes — shifting it would move the scroll position and disturb the progress rules' idea of the current page.
- The panel's contents, top to bottom: the fixed page, the source field, the translation field, any notice, the two add buttons, and a collapse control.
- The source field is marked as Vietnamese text, as the practice screens already do, so the browser applies the right font fallback and spell-check behaviour.
- **No keyboard shortcuts.** Opening, collapsing, and both add actions are pointer-driven. Enter inserts a line break or does nothing; it never submits. Standard tab order still reaches every control.
- Key presses that originate in the panel's fields are ignored by the reader's scroll-input listener, so typing a space does not open the progress gate.

### The old ticket

- The web client map's open ticket on translation provenance is resolved as part of this work: provenance is not stored on a card and is not sent by any client; with hand-typed translation as the web's only source, there is nothing to distinguish. It is to be reopened when explanations reach the web.

## Testing Decisions

A good test here states something the reader would notice — a card was or was not sent, the panel is or is not open, the page recorded is this one — and drives it through a module's public surface. It does not assert on internal fields, call order, or how a state is represented.

- **The collecting store is the main seam.** Tested with the API client replaced, exactly as the practice session store is. Covers: opening and collapsing; collapse discarding everything; the page fixing on first input, holding while the current page changes, and releasing on empty, on success and on collapse; submission refused for blank or whitespace-only fields, an over-long source, a missing page, and while in flight; the created outcome resetting and collapsing; the already-there outcome keeping the fields and exposing the existing card; the failed outcome keeping the fields and exposing the error; a retry after failure succeeding; a notice clearing on edit; a late response after collapse or chapter change not reopening the panel; and the card reaching the deck store in both the created and already-there outcomes.
- **The API client's card creation**, tested with a substitute fetcher as the client's other functions are. Covers: the request body, including the fixed target language and the kind; the two success statuses mapping to created and not created; and failures mapping to the existing error kinds.
- **The deck store's new action**, added to its existing test file. Covers: a new card appearing in the held deck; an existing card being replaced rather than duplicated; and a collected card surviving a load that began earlier and finished later.
- **No component tests and no browser automation.** The web client has neither today, and layout verification belongs to the developer. What cannot be unit-tested is handed over as a checklist instead:
  - The panel docks right on a wide window and bottom on a narrow one, and the page column does not shift in either.
  - The manga scrolls freely behind an open panel.
  - Typing a space in a field does not scroll the page.
  - A Vietnamese input method composes normally in the source field.
  - The confirmation appears by the collapsed button and goes away by itself.
  - A card added here shows up in 字卡庫 and in the practice overview without a reload, and on the phone after its next deck fetch.
  - Adding a line that is already in the deck shows the existing translation and a working link.
  - With the backend stopped, an add fails visibly, keeps the text, and succeeds on pressing again once the backend is back.

## Out of Scope

- **Recognition on the web.** Deferred, not cancelled. The web client map's OCR decisions stand untouched; this spec only stops card collection from waiting on them.
- **Explanations on the web**, and with them any use of the explanation route or its daily ceiling.
- **A browser extension**, or collecting from any site other than the web client's own reader.
- **Choosing a target language.**
- **Keyboard shortcuts** for the panel.
- **Keeping a draft** across a collapse, a chapter change, or a reload.
- **Editing the fixed page by hand.**
- **Picking words out of a sentence just collected.** Considered and declined in favour of collapsing after every add.
- **Recording a repeat lookup** when a line turns out to be collected already. That count means the reader looked a word up again; typing it is not a lookup.
- **Showing a card's source page or lookup count in 字卡庫.** Unchanged from the web review spec.
- **Any backend or iOS change.**

## Further Notes

- **A mistyped source text is permanent on that card.** The hand-typed line becomes the answer practice checks against, the web judges tones strictly, and the backend refuses edits to source text by design. The remedy is delete and collect again — which, from this spec on, can be done without the phone. The web review spec's note that a misread card is "collected again on the phone" becomes out of date when this ships.
- **Collapse-discards plus no shortcuts means an accidental collapse loses the line.** This was put to the developer and accepted for the sake of a panel with no draft state.
- **Deck identity ignores spacing and case.** Two lines that differ only in whitespace or capitalisation are the same card to the backend, so the already-there notice can appear for text that does not look identical to the existing card's. Showing the existing card's own text and translation in the notice is what makes that legible.
- **An existing card keeps its kind.** Collecting a known line under the other button does not change it; the notice's link is where that is corrected.
- **The README must change when this ships.** It states that collecting a card still happens on the phone, and lists the browser as lacking it.
- This is the first web feature that writes a new row rather than moving an existing one; the dev server already forwards the path it needs.
