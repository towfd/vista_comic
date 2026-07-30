Status: ready-for-agent

# Remote access

## Problem Statement

`vista_comic`'s backend (the `api` + `postgres` Docker Compose stack, see `docs/api-contract.md` and `docs/adr/0004-docker-compose-topology.md`) only runs on a Mac at home. The iOS app's base URL (`VISTA_BASE_URL`) points at a LAN IP or `127.0.0.1`. When the developer's phone leaves the home network — a café, cellular, another Wi-Fi — the app can no longer reach the backend at all: there's no library, no reader, no progress sync.

The developer already anticipated this in ADR-0005 (`docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md`) — Cloudflare Tunnel named as the recommended stable-URL option, with Access explicitly deferred. This spec resolves it: give the backend a stable public HTTPS endpoint, gated so only the developer's own app can use it.

## Solution

Expose the `api` service (never `postgres`) through a **named Cloudflare Tunnel** bound to a subdomain on a domain the developer already manages on Cloudflare DNS. Put **Cloudflare Access** in front of the tunnel so the endpoint isn't open to the public internet. The iOS app authenticates to Access non-interactively using a **Cloudflare Access Service Token** (a client-id/secret pair issued to the app, not a person), sent as two request headers on every API call. The app always uses the public tunnel URL on-device — no separate "home" vs. "away" URL or runtime network detection.

This closes the loop the Connectivity section left open ("no Access policy for now... auth stays deferred") now that there's a concrete reason to add it: the tunnel is about to be reachable from anywhere, not just the developer's own machine.

## User Stories

1. As the developer, I want the app to reach the backend when I'm off my home network, so that I can read manga anywhere without needing to be on the same Wi-Fi as my Mac.
2. As the developer, I want the backend's public URL to reject any request that doesn't carry my app's credentials, so that a leaked or guessed tunnel hostname doesn't expose my manga library or reading-progress database to strangers.
3. As the developer, I want the database (`postgres`) to stay unreachable from the public internet even though `api` is exposed, so that the highest-value target (my data) never gets a direct public route.
4. As the developer, I want the app's credentials to follow the existing `VISTA_BASE_URL` pattern (gitignored, scheme-level env var), so that I don't commit secrets and the setup stays consistent with how the base URL already works.
5. As the developer, I want the tunnel, Access policy, and `api`/`postgres` containers to start and stop together via `docker compose up`/`down`, so that there's one command to bring the whole remote-reachable stack up or down, matching the existing two-service Compose workflow.
6. As the developer, I want a clear manual verification step (hit the public URL from a device off my home network) so that I know the setup actually works end-to-end, not just that each piece is configured.
7. As the developer, I want the simulator/local-dev workflow (hitting `127.0.0.1` directly, no tunnel, no Access headers) to keep working unchanged, so that day-to-day development isn't slowed down by remote-access plumbing.

## Implementation Decisions

**Infrastructure (no FastAPI application code changes):**

- Add a third service, `cloudflared`, to the existing `docker-compose.yml` (alongside `api` and `postgres`). It runs the Cloudflare tunnel daemon, authenticated with a tunnel credentials file, and is configured to route the tunnel's public hostname to the `api` service's internal Compose network address (not `localhost`, not `postgres`).
- The tunnel is a **named tunnel** bound to a subdomain of the developer's existing Cloudflare-managed domain (e.g. `api.<domain>`), configured via a Cloudflare Tunnel config file. The tunnel credentials file is a secret and must be gitignored, following the same discipline as the existing `.env` (`MANGA_LIBRARY_PATH`, `DATABASE_URL`).
- **Cloudflare Access** is configured (via the Cloudflare dashboard/Zero Trust) as an application in front of the tunnel's public hostname, replacing the "no Access policy for now" state recorded in ADR-0005. A **Service Token** is issued for the app (not an end-user identity) and added to the Access policy as an allowed service auth method.
- `postgres` is **not** given a tunnel route or public hostname; it remains reachable only on the internal Compose network (and, as today, on `localhost:5432` for local dev tooling). No change to its existing Compose config.
- `docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md` and `docs/api-contract.md`'s Connectivity section are updated to record: Cloudflare Access now adopted (supersedes "no Access policy for now"), Service Token as the auth mechanism, and the reason (public reachability, not just a stable hostname).

**iOS (`vista_comic/vista_comic/Networking/`):**

- `APIConfig` (`ComicRepository.swift`) gains two additional scheme-level env-var-backed values, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`, read the same way `VISTA_BASE_URL` already is (`ProcessInfo.processInfo.environment[...]`, falling back to empty/unset for local dev where no Access sits in front of `127.0.0.1`).
- `APIComicRepository`'s two request paths (`get`, `put`) are unified to build every outgoing call through a single shared request-construction point (today only `put` builds a `URLRequest`; `get` uses `session.data(from:)` directly). That shared point attaches `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers when both values are present, and leaves requests unchanged (no headers) when they're absent — this keeps local dev against `127.0.0.1` working with zero configuration.
- The app's base URL for on-device (non-simulator) builds becomes the public tunnel hostname (`https://api.<domain>`), set via the existing per-scheme `VISTA_BASE_URL` mechanism — no new URL-selection logic, no runtime reachability checks, no "prefer LAN" branching.
- No change to simulator/local workflow: with `VISTA_BASE_URL` unset or pointed at `127.0.0.1` and the two `CF_ACCESS_*` vars unset, behavior is identical to today.
- The now-unnecessary-on-device ATS local-HTTP exception is left in place (still needed for simulator → `127.0.0.1`); no action required, noted as a non-decision consequence.

**Out of scope for FastAPI code:** the `api` service performs no Access-token validation itself — Cloudflare Access enforces the Service Token check at the edge, before traffic ever reaches `cloudflared` or `api`. The backend stays unaware that Access exists.

## Testing Decisions

- **iOS unit test (new):** a test against `APIComicRepository`'s request construction, using a stubbed `URLProtocol`-backed `URLSession` to capture the outgoing `URLRequest` without a real network call. Assert: (a) when `CF_ACCESS_CLIENT_ID`/`SECRET` are configured, every request (`get` and `put`) carries both headers with the expected values; (b) when they're unset, neither header is present. This is the first Networking-layer unit test in the project — use the existing `ComicRepository` protocol and `APIComicRepository`'s current `get`/`put` structure as the shape to extend, not replace.
- **Backend:** no new automated tests — the auth boundary lives entirely in Cloudflare Access/tunnel config, outside the FastAPI app, so there is nothing new for `backend/tests/` to exercise. The existing `test_endpoints.py` suite is unaffected.
- **Manual/infra verification (required, not automatable in this repo):**
  - `docker compose up` brings up all three services; `cloudflared` logs show a healthy connection to Cloudflare's edge.
  - From a network that is *not* the host's LAN (e.g. cellular), a request to the public hostname without Access headers is rejected (Access blocks it); a request carrying the Service Token headers succeeds and reaches `/healthz`.
  - The iOS app, built with the tunnel hostname as `VISTA_BASE_URL` and the two `CF_ACCESS_*` vars set, successfully loads the library and reader while the phone is off the home Wi-Fi.
  - `postgres` port `5432` is not reachable via the tunnel hostname (only via the existing LAN/localhost path).
  - Simulator build with no `CF_ACCESS_*` vars set still works against `127.0.0.1` exactly as before.

## Out of Scope

- Any change to the FastAPI application code, the `progress` table/schema, or the API JSON contract — this ticket is purely a reachability/access-control layer in front of the unchanged API.
- Interactive (browser/OTP) Cloudflare Access login flow — Service Token only.
- "Prefer local LAN, fall back to tunnel" base-URL logic — always-tunnel only, per the resolved decision.
- Hosting the backend anywhere other than the developer's own docker-capable machine (no cloud VM, no managed Postgres, no migration off Compose).
- Exposing `postgres` for remote administration.
- Multi-user auth, per-user accounts, or any identity model beyond "this one app, this one developer."
- Redis (still deferred per ADR-0004, unrelated to this ticket).
- Updating `ROADMAP.md` milestone tracking — per the CLAUDE.md source-of-truth rules, this work is tracked here in `.scratch/remote-access/` going forward rather than as a new ROADMAP.md slice.

## Further Notes

- This is the first ticket created under the `.scratch/`-driven workflow described in `CLAUDE.md` / `docs/agents/issue-tracker.md`; no prior `.scratch/` tickets exist to cross-reference.
- ADR-0005 already named Cloudflare Tunnel as the target mechanism (2026-07-23 decision) but explicitly deferred Access ("no Access policy for now... an Access login would block the app unless a service token is added — auth stays deferred"). This ticket is that deferred follow-through, not a new direction.
- Secret inventory this ticket introduces, all gitignored: the Cloudflare Tunnel credentials file (infra), and two new scheme-level env vars `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` (iOS), alongside the existing `.env` (`MANGA_LIBRARY_PATH`, `DATABASE_URL`, Postgres credentials) and `VISTA_BASE_URL`.
- Next step after this spec: `/to-tickets` (or `/wayfinder` if the work turns out to have real unknowns worth mapping) to break this into implementation-sized tickets — likely one infra/Compose+Cloudflare ticket and one iOS `APIComicRepository`/`APIConfig` ticket, sequential rather than concurrent since the iOS piece needs a live tunnel hostname to test against.
