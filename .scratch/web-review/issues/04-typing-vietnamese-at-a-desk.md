Type: prototype
Status: resolved

# Typing Vietnamese at a desk

## Question

How does the reader actually type Vietnamese on the computer, and does a plain text field survive it?

The phone forgives a missing tone and names it, because typing tones on a phone is laborious. At a keyboard with a Telex or VNI input method that reason may be gone — or the reader may have no input method installed and need the leniency more. An input method also composes: Enter may commit a syllable rather than submit an answer, and what the field holds mid-composition is not what was typed.

Answered by putting a bare input in front of the developer and watching what it receives. Decides whether typed questions are workable in the first slice, and whether tone leniency carries over unchanged.

## Answer

**A plain text field survives it, on one condition, and the web is strict about tones where the phone is lenient.**

Measured on 2026-10-12 with a standalone test page kept outside the repository: six sentences typed by the developer in Chrome 152 on macOS with a Telex input method.

- **The input method composes, one syllable at a time.** Every syllable is a `compositionstart` … `compositionend` run, committed by the space or punctuation that follows it. Nothing was typed by delete-and-retype.
- **What arrives is NFC**, in all six sentences, including `đ`/`Đ` and doubly-marked vowels (`ường`, `ễ`, `ợ`).
- **Enter commits before it submits.** When an answer ends on a syllable still being composed — any answer with no closing punctuation, three of the six — the first Enter arrives as `keydown` with `isComposing: true` and `keyCode: 229` and only ends the composition; a second Enter submits. This is the input method's own convention, the same one a Chinese input method has, and the page does not fight it.
- **The condition:** Enter must be ignored while `isComposing` is true or `keyCode` is 229. Submitting on that first Enter would leave a composition open over a field the page is about to clear.
- **Nothing is judged before submission.** Mid-composition the field holds real intermediate text — `biêt` on the way to `biết` — which is precisely an answer missing a tone. Judging on `input` would flash a tone warning on every syllable.
- Backspace inside a composition spends one press ending it before the next one deletes. Also the input method's, also left alone.

**The web does not forgive a missing tone: one tone wrong is wrong.** This departs from the phone on purpose. The phone counts a missing tone as correct and names it, because typing tones on a phone is laborious; at this keyboard that reason is gone — five of six sentences came back exact with every tone, and the one miss was a dropped letter — and without it the leniency is only a looser test.

Two costs, both stated and accepted:

- **The same answer gets a different verdict on the two devices.** A toneless answer advances a card on the phone and lapses it on the web, so where a card was answered now shapes its schedule. Keeping one verdict on both devices was the recommendation, was chosen first, and was then reversed by the developer the same day.
- **An answer typed with the input method switched off is wrong in its entirety**, not flagged.

What this does not decide: whether the web still *tells* the reader that tones were the only thing wrong. The verdict is `wrong` either way; saying why is feedback, and belongs to the spec.

**So typed questions are workable in the first slice.** Nothing about the keyboard rules either typed mode out.

## Comments

Not measured: Safari, which orders `compositionend` and the Enter `keydown` differently from Chrome — the `keyCode === 229` half of the guard is there for it and is untested. Also not measured: a third-party input method that rewrites text with synthetic backspaces instead of composing, and a touch keyboard. The test page judged with `normalize('NFC')`, `\s` and `\p{M}`, which [What the engine must reproduce](01-what-the-engine-must-reproduce.md) shows are not the forms to ship; for Vietnamese the verdicts are the same.

The tone decision was first recorded as "the phone's rule, unchanged" and corrected on 2026-10-12 when the developer chose strictness instead. The TypeScript engine therefore does **not** port the tone-insensitive fallback in `judgeSentenceAnswer` or its cloze counterpart as a path to `correct` — a deliberate difference, not drift, and one [Keeping two engines in step](05-keeping-two-engines-in-step.md) has to carve out of any parity it asks for.
