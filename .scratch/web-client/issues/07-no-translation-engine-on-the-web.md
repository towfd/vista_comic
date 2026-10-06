Type: grilling
Status: resolved

# No translation engine on the web

## Question

iOS translates on-device through `AppleTranslator`. A browser cannot reach that. What produces the translation on the web — Claude, a local model, a cloud translation API, or something else?

## Answer

**Nothing. The web ships no translation engine.** A card's `translation` has two sources:

1. **The reader types or pastes it into an initially-empty field.** This is the primary path: free, no network round trip, no request spent.
2. **`translation` returned by an explanation request**, when the reader asks for one. It can still be overwritten.

The browser's own right-click translation covers "I just want the gist" and sits entirely outside the application — its result renders for a human and is unreadable to page code, so it could never have fed a card anyway.

**This is not a workaround; it is the rule the iOS app just shipped, with the draft step removed.** `.scratch/translation-editing/spec.md` (branch `feat/translation-editing`, commit d9422d4) establishes: *the machine produces a draft, the reader produces the final version*, and *whatever wording is in that field when the reader acts is what everything downstream uses*. On iOS the field arrives pre-filled and is corrected; on the web it starts empty and is filled. Same rule.

It also meets the existing backend contract without any change. `LearningCardCreate.translation`'s own docstring: *"The server does not judge which: the stored translation is the one the reader read and approved, and that approval is the whole quality gate."* A hand-typed translation is the strongest form of that approval, not the weakest.

**The consequence to carry forward is a cost asymmetry, not a defect.** On the phone there is a free quick translation to look at before deciding whether an explanation is worth spending on. The web has no such tier inside the app, so any card whose translation the reader does not write themselves costs one explanation request. The developer was told this and accepted it.

Two practical notes for the specs that inherit this:

- Chrome's page translation **skips form-field values**, so recognized text sitting in a `<textarea>` for correction will not be translated by it. That is a layout decision for part ④, not an architectural one.
- `/comprehensions` already returns four fields — `translation`, `grammarNotes`, `contextNotes`, `toneRegister` — and the worker fetches the page image from the library itself, so the web needs to send only source text plus the comic/chapter/page identifiers. The explanation path needs **no backend work at all**.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map. Whether the reader-typed provenance needs storing is open — see [Translation provenance](12-translation-provenance.md).
