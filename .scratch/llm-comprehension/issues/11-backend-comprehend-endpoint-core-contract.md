# 11 — Backend `/comprehend` endpoint: core contract

**What to build:** a new `POST /comprehend` backend endpoint that accepts a selection crop image, a downscaled full-page image, the (possibly user-corrected) source text, and a target language, calls the Claude Messages API with a `strict: true` tool-use schema, and returns a structured comprehension result. Defaults to Claude Haiku 4.5; accepts an optional request field to use Claude Sonnet 5 instead (the manual-upgrade path, wired up end-to-end in ticket 17). Distinguishes a genuine success from a model-declined outcome via a `status` field on the same HTTP 200 response, per spec's Implementation Decisions. This ticket is demoable purely via direct HTTP calls (curl/Postman) against the running backend — no iOS changes yet.

**Blocked by:** None — can start immediately.

**Status:** resolved

- [x] `POST /comprehend` accepts `{cropImageBase64, pageImageBase64, sourceText, targetLanguageCode}` and an optional model-tier override field (`useStrongerModel`)
- [x] On success, calls Claude with a `strict: true` tool-use schema enforcing exactly `translation`, `grammarNotes`, `contextNotes`, `toneRegister`, and returns `{status: "ok", translation, grammarNotes, contextNotes, toneRegister}` with HTTP 200
- [x] When Claude declines to process the request (no valid tool-use result in the response — does not depend on `stop_reason`/`stop_details`), returns `{status: "declined"}` with HTTP 200
- [x] Any other failure (network error to Claude, Claude API error, malformed request) surfaces as a normal HTTP 4xx/5xx, not a 200
- [x] The API key used to call Claude lives only in the repo-root gitignored `.env` (as `ANTHROPIC_API_KEY` — renamed from an earlier `CLAUDE_CODE_API_KEY` during code review to avoid confusion with the Claude Code CLI tool, and to match the `anthropic` SDK's own default-resolved variable name), never in any committed file or response body
- [x] Backend tests cover the request/response contract (success, declined in three shapes, three error-status paths, 422 malformed-request) by stubbing the `anthropic` client at `comprehension_client._client()` — the test suite never makes a real call to Anthropic's API

## Comments

Implemented by `backend-implementer` on `feat/llm-comprehension-foundation`. New: `backend/app/comprehension_client.py`, `backend/tests/test_comprehension.py` (14 tests). Modified: `backend/app/main.py`, `backend/app/models.py`, `backend/app/config.py`, `backend/requirements.txt` (`anthropic==0.120.2`), `backend/README.md` (documented the new `.env` key).

Verified: `pytest tests/test_comprehension.py` — 14/14 pass; full suite — 61 passed (47 pre-existing + 14 new), 49 errors unchanged from baseline (pre-existing, documented local-Postgres-port-shadowing environment issue, unrelated to this ticket — see ROADMAP.md's "Known issues and constraints").

Code review (`/code-review`, Standards + Spec axes) found the diff spec-faithful with no scope creep. Standards axis flagged: the `.env` key wasn't documented in `backend/README.md` (fixed), the env var name `CLAUDE_CODE_API_KEY` was confusable with the Claude Code CLI tool (renamed to `ANTHROPIC_API_KEY`, with the user's confirmation, including the real local `.env`), and two near-identical `except` clauses in the route handler (merged). The Haiku-dated/Sonnet-undated model ID asymmetry was checked against the model catalog and found to be intentional, not a bug.

**Deployment gap found and fixed on 2026-08-04, while device-testing ticket 14–17:** this ticket's AC #13 covers where the key lives on disk, but `docker-compose.yml`'s `api` service `environment:` list was never updated to forward `ANTHROPIC_API_KEY` into the container — `config.py`'s `load_dotenv` reads the repo-root `.env`, which exists on the host but is never copied into the container, so `POST /comprehend` was silently 500ing on every real-device call (visible via `docker logs vista_comic-api-1`), which iOS then masked entirely by falling back to the on-device `Translator` and showing the gray "離線模式" banner (ticket 14's fallback working exactly as designed, just papering over this gap). Fixed by adding `ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}` to the `api` service's `environment:` block in `docker-compose.yml`, mirroring `DATABASE_URL`'s existing forwarding pattern. Verified live: `POST /comprehend` against the running container now returns a real `status: "ok"` result from Claude.
