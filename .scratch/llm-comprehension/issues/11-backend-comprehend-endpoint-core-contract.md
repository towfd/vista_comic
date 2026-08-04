# 11 — Backend `/comprehend` endpoint: core contract

**What to build:** a new `POST /comprehend` backend endpoint that accepts a selection crop image, a downscaled full-page image, the (possibly user-corrected) source text, and a target language, calls the Claude Messages API with a `strict: true` tool-use schema, and returns a structured comprehension result. Defaults to Claude Haiku 4.5; accepts an optional request field to use Claude Sonnet 5 instead (the manual-upgrade path, wired up end-to-end in ticket 17). Distinguishes a genuine success from a model-declined outcome via a `status` field on the same HTTP 200 response, per spec's Implementation Decisions. This ticket is demoable purely via direct HTTP calls (curl/Postman) against the running backend — no iOS changes yet.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `POST /comprehend` accepts `{cropImageBase64, pageImageBase64, sourceText, targetLanguageCode}` and an optional model-tier override field
- [ ] On success, calls Claude with a `strict: true` tool-use schema enforcing exactly `translation`, `grammarNotes`, `contextNotes`, `toneRegister`, and returns `{status: "ok", translation, grammarNotes, contextNotes, toneRegister}` with HTTP 200
- [ ] When Claude declines to process the request (no valid tool-use result in the response — do not depend on a specific `stop_reason`/`stop_details` value being present, per the spec's Further Notes), returns `{status: "declined"}` with HTTP 200
- [ ] Any other failure (network error to Claude, Claude API error, malformed request) surfaces as a normal HTTP 4xx/5xx, not a 200
- [ ] The API key used to call Claude lives only in the backend's gitignored `.env`, never in any committed file or response body
- [ ] Backend tests cover the request/response contract (success, declined, malformed-request shapes) by stubbing/mocking the Claude API call — the test suite never makes a real call to Anthropic's API
