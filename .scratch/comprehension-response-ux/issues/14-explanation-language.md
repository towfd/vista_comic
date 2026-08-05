# 14 — Explanation notes come back in the reader's own language

**What to build:** A reader who translates a Vietnamese speech bubble into Traditional Chinese gets grammar, context and tone notes written **in Traditional Chinese**, quoting the Vietnamese they discuss — instead of today's English prose. This is one of the two complaints that started this effort, and it is verifiable against the app as it exists today, before any of the queue work lands.

The cause is that the tool schema names the target language for the translation field only; the three explanation fields say nothing about output language, so the model defaults to the language of the prompt. The fix is one sentence appended to each of those three field descriptions.

From the live spike that settled this, the decision-carrying part:

```python
"grammarNotes": {
    "type": "string",
    "description": (
        "Notes on the sentence's grammar/structure. "
        f"Write this field in {target_language_code}."
    ),
},
# the same one-sentence suffix on contextNotes and toneRegister
```

The **bare BCP-47 code is deliberate** — it proved as reliable as spelling the language out by name, and it means no code-to-name table has to be maintained in sync with the app's picker. The prompt text needs no change.

**Blocked by:** None — can start immediately.

**Status:** done — merged in PR #38

- [x] The tool schema is built per request from the target language code rather than being a module-level constant.
- [x] All three explanation field descriptions instruct the model to write in that language; the translation field's description is unchanged.
- [x] The prompt text is unchanged.
- [x] A test asserts the schema handed to the model carries the requested language code in all three explanation field descriptions, using the existing client-construction stub seam — no live API call in the test suite.
- [x] Manually verified against a real call: with a Vietnamese source and Traditional Chinese target, the three notes are Chinese prose that quotes the Vietnamese, and the translation is unaffected.
