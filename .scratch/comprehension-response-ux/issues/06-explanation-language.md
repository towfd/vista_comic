Type: grilling
Status: resolved

# Explanation language follows the target-language picker

## Question

The explanation currently comes back in an unpredictable language. What language should `grammarNotes`/`contextNotes`/`toneRegister` be written in, and does the reader need a new control to say so?

## Answer

**The same language the picker translates *to* — the reader's own language. No new control.**

The root cause is in `backend/app/comprehension_client.py`: `_prompt_text` tells Claude the target language code, but the tool schema's descriptions for the three explanation fields say nothing about what language to *write* them in. Their language is therefore left entirely to the model's discretion, which is why it varies.

The developer's phrasing ("回應的語言是對應我們原始的語言…中文 → 越南文…應當是用中文去介紹這段越南語") reads ambiguously — "original language" could mean the manga's own language (Vietnamese) — but the worked example settles it: reading Vietnamese manga with the picker on Traditional Chinese, they want Chinese prose explaining the Vietnamese. That is the *target* language, not the source.

This means the existing single picker already carries all the information needed. It is effectively "the language I read in," so binding the explanation fields to it introduces no second control and no new persisted preference. If the picker changes to English, the explanation should come back in English too.

Scope note: this is a prompt/schema-level fix on the backend. No request or response field changes.

## Comments

Resolved via a `/grilling` session on 2026-08-05, in the same conversation that created this map.

Whether passing a bare language code (e.g. `zh-Hant`) is enough for the model to reliably comply, or whether the prompt needs the language spelled out by name, is an empirical question left to [Verify the explanation-language instruction against the real model](11-verify-explanation-language-prompt.md) — mirroring M9's own precedent of validating schema/prompt behaviour against real calls ([schema fields and model tier](../../llm-comprehension/issues/06-schema-fields-and-model-tier-prototype.md)).
