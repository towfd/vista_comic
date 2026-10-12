Type: grilling
Status: resolved

# Does the translation's provenance need storing?

## Question

`.scratch/comprehension-response-ux/` ticket 09 put a provenance chip beside the translation — 📱 for the device, ☁️ for the cloud — and `.scratch/translation-editing/` added a third state for wording the reader typed. On the web, [there is no translation engine](07-no-translation-engine-on-the-web.md), so a hand-filled translation is the reader's own by construction, and an explanation's is the cloud's.

Two questions, in order:

1. **Is provenance stored at all today, or is it purely a screen state on iOS?** A fact, to be looked up in the `learning_card` schema and `LearningCardResponse` before anything is decided.
2. If it is not stored: does the card library need to show where a translation came from, given that one client can now only ever produce two of the three states? If it is stored: does the web need to send it, and does adding a value risk anything for iOS clients reading the same rows?

Small, but it touches both ④ (which writes the card) and ⑤ (which displays it), which is why it sits on the map rather than inside either.

## Answer

**No. Provenance is not stored, and the web sends none.**

1. **It is purely a screen state on iOS.** Neither the card-creation request, the card response, nor the `learning_card` table carries a provenance field; a search of the backend and the web client for one finds nothing. The chip is drawn from what the reader's sheet happens to know at that moment and is gone once the card is saved.
2. **The card library does not need to show it.** [Web card collection](../../web-card-collection/spec.md) made hand-typing the web's only source of a translation, so every card collected there has the same provenance by construction and a label would carry no information. Nothing is added to the request, so iOS clients reading the same rows are unaffected.

**Reopen when explanations reach the web.** At that point a web card's translation can come from two places, and whether the difference is worth a column becomes a real question again.

## Comments

Resolved on 2026-10-12 during the `/grilling` session for [web card collection](../../web-card-collection/spec.md).
