Type: prototype
Status: resolved

# Verify the explanation-language instruction against the real model

## Question

Ticket 06 locked *what* the explanation language should be (the picker's target language). This ticket settles *how* to instruct the model so it actually complies, verified against real calls rather than assumed — mirroring M9's own precedent of validating the schema against real content ([schema fields and model tier](../../llm-comprehension/issues/06-schema-fields-and-model-tier-prototype.md)).

Open points to test:

- Is a bare BCP-47 code (`zh-Hant`) enough, or does the prompt need the language spelled out by name ("Traditional Chinese")?
- Does the instruction belong in `_prompt_text`, in each field's `description` inside `_TOOL_SCHEMA`, or both? The schema descriptions currently say nothing about output language at all, which is the likely root cause of the drift.
- Does Claude Haiku 4.5 comply as reliably as Sonnet 5 here, given the Sonnet upgrade path exists?
- Spot-check the distinction that matters most: with Vietnamese source text and `zh-Hant` as target, the explanation prose must be Traditional Chinese while still quoting the Vietnamese it's discussing — confirm quoting the source doesn't drag the whole explanation into Vietnamese.

Requires a real `ANTHROPIC_API_KEY` (backend `.env`), so it is a small live spike, not an automated test.

## Answer

**Append one sentence naming the target language to each of the three explanation fields' `description` in `_TOOL_SCHEMA`. The bare BCP-47 code is enough. `_prompt_text` needs no change at all.**

### Method

A throwaway script called Claude directly (bypassing `/comprehend`, so the backend's 300/day counter was untouched), using real material from the library: page 31 of `marrymyhusband` chapter 1, a Vietnamese scanlation. Two speech bubbles were chosen because each stresses a different note field:

| | Source | Stresses |
| --- | --- | --- |
| A | `À, trưởng phòng tìm cô. Cô đi nhanh lên.` | `cô` is genuinely ambiguous (formal "you" vs "she") → `contextNotes` must resolve it from the image |
| B | `Để mình chết đẹp đẽ một chút đi mà!` | the `đi mà` pleading particles → `toneRegister` |

The page was downscaled to a 1024px long edge first, mirroring `APIComprehender.swift:38`, so the input matched production. Four variants, each changing exactly one thing against a V0 that copied the shipped prompt and schema verbatim. Target was `zh-Hant` throughout.

### Findings

**1. The diagnosis in ticket 06 was exactly right, and the failure is sharper than "unpredictable".** In V0, both source texts produced a Traditional Chinese `translation` and all three notes in **English** — not a random language, but *the language of the prompt itself*. `translation` was unaffected because its schema description is the only one that names the target language. The drift is deterministic and entirely explained by the schema.

**2. All three fixes worked; the bare code is enough.**

| Variant | Instruction location | Language written as | Notes language |
| --- | --- | --- | --- |
| V0 | none (shipped) | — | **English** ✗ |
| V1 | schema descriptions | bare code `zh-Hant` | Traditional Chinese ✓ |
| V2 | schema descriptions | name `Traditional Chinese` | Traditional Chinese ✓ |
| V3 | schema + prompt | name | Traditional Chinese ✓ |

**V1 is the choice, and the reason is cost of ownership rather than output quality.** V2 and V3 require the backend to keep a BCP-47 → English-name mapping table in sync with the app's `TargetLanguageOption.options`; V1 interpolates the code that is *already a parameter*, so nothing new has to be maintained and every future picker language works with no backend change. There was no measured compliance benefit to justify that table.

**3. Quoting the source does not drag the explanation into the source language.** This was the sharpest risk and it did not materialise. The model consistently wrote Chinese prose with the Vietnamese quoted inline:

> 「đi mà」是越南文常見的語氣詞組合，強調請求和感情

Fields scoring roughly half CJK / half Latin were all of this shape — Chinese explanation, heavy Vietnamese quotation — never Vietnamese prose.

**4. Haiku 4.5 complies, and this now matters more than when the ticket was written.** Ticket 09 turned the model tier into a user-facing picker, so most calls will be Haiku. Across **6 V1 calls and 18 note fields, compliance was 18/18 with no failures** (one exploratory call per text plus two repeats each — the repeats existed specifically because "unpredictable" was the original complaint and a single success proves nothing).

**Sonnet 5 was deliberately not tested.** Once Haiku complied consistently, a stronger model failing where the weaker one succeeded is not a realistic risk, and the calls were better spent on repeats. Flagged as an accepted, small residual assumption.

### The change this implies

`_TOOL_SCHEMA` is currently a module-level constant (`comprehension_client.py:45`). To interpolate the target language code it has to become a function of that code — a small structural change worth naming, since it is the only non-trivial part:

```python
def _tool_schema(target_language_code: str) -> dict[str, Any]:
    ...
    "grammarNotes": {
        "type": "string",
        "description": (
            "Notes on the sentence's grammar/structure. "
            f"Write this field in {target_language_code}."
        ),
    },
    # same one-sentence suffix on contextNotes and toneRegister
```

`translation`'s description is left alone — it already works. `_prompt_text` is unchanged.

### Out of scope but observed

Note *content* quality carries independent noise: one V2 response called `đẽ` an adverb, mis-splitting the single word `đẹp đẽ`. That is a translation-accuracy matter, not a language-compliance one, and nothing on this map addresses it.

## Comments

Resolved via a live spike on 2026-08-05, run under a one-off exception to this project's "no code before the implement phase" rule. **The spike scripts were deleted immediately afterwards at the developer's instruction**, so — unlike the usual `/prototype` practice of keeping the artifact on a throwaway branch — this ticket is the only record of the evidence. The variant definitions and the numbers above are therefore written out in full rather than summarised.

Ticket 06's decision is confirmed, not amended: binding the explanation to the picker's target language is achievable with a three-line schema change and no new control.
