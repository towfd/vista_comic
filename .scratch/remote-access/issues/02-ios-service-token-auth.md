# 02 — iOS Service Token auth

**What to build:** The iOS app authenticates every backend request with the Cloudflare Access Service Token, so it can reach the public tunnel hostname from off the home network. `APIConfig` gains the two credential values (same gitignored, scheme-level env-var pattern as `VISTA_BASE_URL`); `APIComicRepository`'s `get` and `put` are unified onto one request-building path that attaches the headers when configured and stays a no-op when not (so local/simulator dev against `127.0.0.1` is unaffected). On-device builds point `VISTA_BASE_URL` at the public tunnel hostname — no local/remote branching logic.

**Blocked by:** 01 (needs the live tunnel hostname and real Service Token values to configure the scheme and run the full device-level check)

**Status:** done (2026-07-28)

- [x] `APIConfig` provides `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`, defaulting to unset/empty for local dev. Superseded from the original "environment variable" plan: both this and `VISTA_BASE_URL` now come from `Bundle.main.infoDictionary` (build-time `Config/Shared.xcconfig` + gitignored `Config/Secrets.xcconfig`), not `ProcessInfo.environment` — see the `## Comments` entry below.
- [x] `APIComicRepository`'s `get` and `put` both route through a single shared request-construction point (`APIConfig.authorizedRequest`, also shared with `AuthorizedAsyncImage` — see below).
- [x] When both credential values are present, every outgoing request carries `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers with the configured values. **This was false as originally shipped** — see `## Comments`; now true for JSON requests and image requests alike.
- [x] When the credential values are unset, no Access headers are added and requests are unchanged from current behavior.
- [x] Unit tests using a stubbed `URLProtocol`-backed `URLSession` assert both the "headers present when configured" and "headers absent when unconfigured" cases, for `get`, `put`, and (added after the gap below was found) image fetches.
- [x] On-device build with `VISTA_BASE_URL` set to the public tunnel hostname and both `CF_ACCESS_*` values set successfully loads the library and reader while the phone is off the home Wi-Fi. **Confirmed by the developer on a physical device.**
- [x] Simulator build with `VISTA_BASE_URL` unset/`127.0.0.1` and no `CF_ACCESS_*` values set continues to work exactly as before. Confirmed structurally (full local `xcodebuild build`/`test` pass against the unset-credential path) and confirmed by the developer.

## Comments

**Build-time config (superseding the original plan):** scheme-level environment variables (the original plan for `VISTA_BASE_URL`/`CF_ACCESS_*`) only apply when Xcode itself launches the process — tapping the app icon directly with no debugger attached loses them, which defeats the point of a remotely-reachable backend for daily use. Moved both to build-time `.xcconfig` → `Info.plist` → `Bundle.main`, gitignored `Config/Secrets.xcconfig` holding the real values (same secret discipline as `.env`).

**Found and fixed: images didn't carry Access headers.** As originally shipped, only `APIComicRepository`'s own JSON requests (`/comics`, `/comics/{id}`, `/progress`) attached the Service Token headers. Covers and reader pages are loaded directly by SwiftUI's `AsyncImage(url:)`, which has no API for custom headers — so once Access was live (ticket 01), every image request was silently blocked at the edge while the JSON still loaded fine: the app opened, the library populated, but no images rendered. Confirmed live: the same media URL returned 403 (HTML) without headers and 200 (`image/jpeg`) with them. Fixed with a new `AuthorizedAsyncImage` view (drop-in replacement for `AsyncImage`, same phase-based API) that fetches through the same `APIConfig.authorizedRequest` builder `APIComicRepository` now also shares. 5 new regression tests added, including one that directly reproduces the observed 403 status.

**Test-infra lesson:** first extracted the stub `URLProtocol` used by both test files into one shared file, since it was the second occurrence. That was wrong — its static state is global, and Swift Testing can run different `@Suite`s in parallel with each other even though `.serialized` only serializes tests *within* a suite, so the two suites raced and corrupted each other's stubbed responses (observed as flaky, unrelated-looking test failures on a full-suite run). Reverted to one file-private stub class per suite.
