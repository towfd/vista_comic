# 02 — iOS Service Token auth

**What to build:** The iOS app authenticates every backend request with the Cloudflare Access Service Token, so it can reach the public tunnel hostname from off the home network. `APIConfig` gains the two credential values (same gitignored, scheme-level env-var pattern as `VISTA_BASE_URL`); `APIComicRepository`'s `get` and `put` are unified onto one request-building path that attaches the headers when configured and stays a no-op when not (so local/simulator dev against `127.0.0.1` is unaffected). On-device builds point `VISTA_BASE_URL` at the public tunnel hostname — no local/remote branching logic.

**Blocked by:** 01 (needs the live tunnel hostname and real Service Token values to configure the scheme and run the full device-level check)

**Status:** ready-for-agent

- [ ] `APIConfig` reads `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` from the environment (same mechanism as `VISTA_BASE_URL`), defaulting to unset/empty for local dev.
- [ ] `APIComicRepository`'s `get` and `put` both route through a single shared request-construction point (today only `put` builds a `URLRequest`).
- [ ] When both credential values are present, every outgoing request carries `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers with the configured values.
- [ ] When the credential values are unset, no Access headers are added and requests are unchanged from current behavior.
- [ ] New unit test (first in the Networking layer) using a stubbed `URLProtocol`-backed `URLSession` asserts both the "headers present when configured" and "headers absent when unconfigured" cases, for both `get` and `put`.
- [ ] On-device build with `VISTA_BASE_URL` set to the public tunnel hostname and both `CF_ACCESS_*` vars set successfully loads the library and reader while the phone is off the home Wi-Fi.
- [ ] Simulator build with `VISTA_BASE_URL` unset/`127.0.0.1` and no `CF_ACCESS_*` vars set continues to work exactly as before.
