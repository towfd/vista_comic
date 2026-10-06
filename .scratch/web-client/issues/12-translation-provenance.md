Type: grilling
Status: open

# Does the translation's provenance need storing?

## Question

`.scratch/comprehension-response-ux/` ticket 09 put a provenance chip beside the translation — 📱 for the device, ☁️ for the cloud — and `.scratch/translation-editing/` added a third state for wording the reader typed. On the web, [there is no translation engine](07-no-translation-engine-on-the-web.md), so a hand-filled translation is the reader's own by construction, and an explanation's is the cloud's.

Two questions, in order:

1. **Is provenance stored at all today, or is it purely a screen state on iOS?** A fact, to be looked up in the `learning_card` schema and `LearningCardResponse` before anything is decided.
2. If it is not stored: does the card library need to show where a translation came from, given that one client can now only ever produce two of the three states? If it is stored: does the web need to send it, and does adding a value risk anything for iOS clients reading the same rows?

Small, but it touches both ④ (which writes the card) and ⑤ (which displays it), which is why it sits on the map rather than inside either.

## Answer

_Unresolved._
