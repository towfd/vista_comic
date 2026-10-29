Status: ready-for-agent

# Web bubble collect: send a tapped bubble to the collecting panel

## Problem Statement

The web reader shows a speech bubble's translation when it is tapped (PR #130): invisible boxes from the chapter's `comic-ocr-data` OCR file, and a card beside the bubble with the translation above and the original below. To keep a line from that card, the reader has to open 收卡 and retype both the Vietnamese and the Chinese by hand — the text they are looking at is already on screen, and copying it out is the whole cost of collecting it.

## Solution

The translation card gains a 加入句子 button. Pressing it closes the card and opens the collecting panel already filled in: the bubble's original text, converted to upper case, in 原文; its translation in 譯文; the page recorded as the page the bubble is on. The reader edits either field as they like and adds it with the panel's existing 加入單字 / 加入句子 buttons. Nothing about how a card is saved changes.

## User Stories

1. As a reader, I want a 加入句子 button on a bubble's translation card, so I can keep a line without retyping it.
2. As a reader, I want pressing it to open the collecting panel with the original and the translation already filled in, so the card is one press away from saved.
3. As a reader, I want the translation card to close when the panel opens, so the two do not stack over the page.
4. As a reader, I want the original filled in upper case — lines with lower-case letters converted too — because that is how I am used to reading these lines.
5. As a reader, I want the translation card itself to keep showing the original exactly as OCR read it, so the conversion only affects what I collect.
6. As a reader, I want the card to record the page the bubble is on, not whichever page the reader counts as current, so a bubble near a page boundary is attributed to its own page.
7. As a reader, I want to be able to edit both fields before adding, so I can fix an OCR misread, a name, or a translation I disagree with.
8. As a reader, I want to choose 加入單字 or 加入句子 in the panel as before, so a one-word bubble can still be collected as a word.
9. As a reader, when a bubble has no translation, I want the button to still be there and fill in only the original, so I can type the meaning myself.
10. As a reader, when the panel already holds something I typed, I want pressing the button on another bubble to replace it, because pressing it means this is the line I want now — the panel keeps no drafts anyway.
11. As a reader, I want everything that happens after the panel is filled — the already-collected notice, a failed save, the 已加入 confirmation — to behave exactly as it does for a typed card.

## Implementation Decisions

### What is and is not touched

- Web client only: the collecting store, the reader page component, and the reader view. No backend, iOS, or `comic-ocr-data` change.
- The card-saving path (API client, deck store, the panel's add/notice behaviour) is unchanged.

### The collecting store

- Gains one action that fills the panel from a bubble: given the original text, the translation (or none), and the page number, it opens the panel and **replaces** both fields with them, fixes the page to the given one, and clears any notice and the last 已加入 confirmation.
- A filled page behaves like a typed one from then on: emptying the source field releases it, and typing again fixes the reader's current page, as today.
- The upper-case conversion is done by a small pure function (locale-aware upper-casing for Vietnamese, so diacritics and `đ → Đ` convert correctly). Only the value filled into the panel is converted.

### The reader page component

- The translation card gains a 加入句子 button under the original text. Pressing it emits the bubble's segment to the parent; the component does not know about the collecting store.
- The card's display of the original is unchanged (OCR casing as read).

### The reader view

- On that event: close the translation card, then call the store's fill action with the bubble's original, translation, and its page number (the page component already knows its own page).
- The click must not reach the window-level listener that closes the card in a way that leaves things half-done; order is: close card, fill panel.

## Testing Decisions

- Good tests here assert the panel's observable state after the action, not how it is wired.
- **Collecting store** (existing `collect.test.ts` seam): filling an empty panel; filling over typed text replaces it; the page is the given one, not the current page; a missing translation leaves 譯文 empty; a notice and the last confirmation are cleared; the filled card adds through the unchanged path.
- **Upper-case function**: mixed-case and already-upper lines; Vietnamese diacritics and `đ`.
- No component or browser tests: UI behaviour is verified by the developer on a device (CLAUDE.md, Verification rule 4). The ticket hands over a checklist instead.

## Out of Scope

- Word-by-word breakdown of a line, collecting single words from it, and any LLM call — the second spec of this request.
- Marking bubbles already collected, or showing collection state on the translation card.
- Changing how the translation card or the boxes look, or how the overlay data is served.
- Upper-casing anything other than the value filled in from a bubble.

## Further Notes

- 1015 of the 1413 OCR lines in `comic-ocr-data` are already all upper case; the longest line is 120 characters, inside the deck's 200-character limit.
- The deck treats a line as the same card whatever its case, so an upper-cased fill of a line already collected in lower case is reported as already collected, as intended.
