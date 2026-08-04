Type: grilling
Blocked by: 06
Status: resolved

# Backend API contract and schema

## Question

What's the request/response contract for the new comprehension backend endpoint (path, request shape — crop image, page image, selected OCR text, target language — response shape), and what exact new columns does `saved_translation` gain to hold the explanation content (ticket 04), once ticket 06 fixes the schema those columns need to hold?

Resolve via `/grilling` and/or `/domain-modeling`.

## Answer

**New endpoint: `POST /comprehend`**, flat (not nested under `/comics/{id}/chapters/{cid}`), mirroring `/translations`'s existing flat shape — separate from `/translations`, which stays the save/list endpoint (M8's existing two-step "翻譯 then 儲存" flow is preserved unchanged; `/comprehend` is the new "翻譯" step, `/translations` still handles "儲存").

**Request**: `{ cropImageBase64, pageImageBase64, sourceText, targetLanguageCode }`.

- `sourceText` is the OCR-recognized (and possibly user-corrected) text, sent explicitly — Claude translates *this* text rather than re-deriving its own OCR reading from the crop image. Deliberate: the user may have corrected an OCR mistake before tapping Translate, and if Claude re-read the image itself, its reading could silently diverge from what's shown as "original" on screen, making the correction pointless and confusing.
- Images are base64 in the JSON body (not multipart) — consistent with this API's existing JSON style; payload is small (ticket 02's crop-at-original-resolution + page-downscaled-to-~1024px) so the ~33% base64 overhead is immaterial.
- Backend validates both images against a lenient size ceiling *before* forwarding to Claude — a second, independent cost-anomaly guard alongside ticket 10's daily-request cap, this one catching an oversized single request (buggy client, bypassed app) rather than an excessive request count. Requests over the ceiling are rejected with a 4xx before any Claude call is made.

**Response — two 200 outcomes, discriminated by a `status` field**, not by HTTP status code:

- `{ status: "ok", translation, grammarNotes, contextNotes, toneRegister }` — success
- `{ status: "declined" }` — Claude refused (ticket 07's content-policy case)
- Anything else (network failure, backend down, ticket 10's daily cap exceeded, this ticket's oversized-image rejection) is a genuine HTTP 4xx/5xx

Chose 200+field over a distinct 4xx for "declined" specifically because ticket 08 already decided "declined" and "generic error" need visually distinct banners (orange vs. gray) on iOS — the client already has to read a discriminator to pick the right banner, so putting that discriminator in the response body (rather than memorizing which status code number means what) is the more direct fit. Mirrors Claude's own API convention (a refusal is HTTP 200, not an error) per ticket 07's research.

**iOS-side fallback**: any non-`"ok"` outcome (declined, or an HTTP error) triggers ticket 03's fallback to the on-device `Translator` — the same underlying fallback path, just rendered with ticket 08's orange banner for `declined` vs. gray for everything else.

**`saved_translation` gains three new nullable columns**: `grammar_notes`, `context_notes`, `tone_register` (`CREATE TABLE IF NOT EXISTS`-style addition, no migration tooling, matching this table's existing precedent). No separate "source" column — a row with these three columns `NULL` already means "this was a fallback save, translation only," so a redundant provenance flag isn't needed.

## Comments

Resolved via `/grilling` on 2026-08-04, in the same conversation that created this map.
