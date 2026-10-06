# 01 — The library on screen, through the proxy

**What to build:** The reader runs `npm run dev` in `web/`, opens `http://localhost:5173`, and sees their real manga library — titles, chapter counts and covers — fetched from `api.vistabanana.com` through the local proxy. Nothing is clickable yet.

**This is the tracer bullet, and most of the MVP's risk lives here rather than in the screens.** One screen is enough to prove every assumption the design rests on: that the Service Token gets through Cloudflare from a Vite proxy, that the token never reaches the browser, that absolute media URLs are rewritten so images also go through the proxy, and that the three kinds of failure can be told apart. Tickets 02 and 03 are then ordinary screens on a road this ticket has already paved.

It creates `web/` (Vue 3 + Vite + Pinia + Tailwind) and the three layers the spec names: an API client that owns `fetch`, URL rewriting and error shaping; a Pinia store for catalog state; and components that read the store and never call `fetch`.

**The proxy.** `vite.config` reads `web/.env` with `loadEnv` and forwards `/comics` and `/media` to `VISTA_API_ORIGIN` with `changeOrigin: true`, adding `CF-Access-Client-Id` and `CF-Access-Client-Secret`. The variables are deliberately **not** `VITE_`-prefixed, because Vite embeds those into the browser bundle. The dev server stays bound to `localhost`. `web/.env` already exists, is gitignored by the root `.gitignore`, and is filled in by the developer — this ticket never writes or prints the token.

**URL rewriting is the one place this design can fail silently.** The backend returns `https://api.vistabanana.com/media/...`; an `<img>` given that URL bypasses the proxy, carries no token, and is refused — so the library would render with every cover broken. The client reduces every media URL to its path before it reaches a component. It is unit-tested and is the first thing to suspect if images break.

**Three failures, three messages.** Cloudflare refuses an untokened request with a redirect to its login page rather than an error status, so the client must recognise "this is not the API's JSON" and report it as an authentication problem. That, the network being unreachable, and a genuinely empty library each get their own message; the first two offer a retry.

**Blocked by:** None — can start immediately. The developer must have filled in `web/.env` to verify it.

**Status:** done 2026-10-06 — unit-verified, checked against the live backend, and reviewed in the browser by the developer on branch `feature/web-reader-mvp`.

- [x] `web/` exists as a self-contained Vue 3 + Vite + Pinia + Tailwind project; `npm run dev` serves it on `localhost` only
- [x] `/comics` and `/media` are proxied to `VISTA_API_ORIGIN` with both Cloudflare Access headers attached
- [x] The token is read only by `vite.config`; no `VITE_`-prefixed variable carries it, and it appears nowhere in the browser bundle
- [x] `web/.env` is untouched by the implementation and remains gitignored
- [x] The library screen lists every comic from the real catalog with its title, chapter count and cover
- [x] Every media URL is rewritten to a path before reaching a component, so covers load through the proxy
- [x] An authentication refusal, an unreachable network and an empty library each show their own Traditional Chinese message; the first two offer a retry
- [x] Components read from the Pinia store and never call `fetch` directly
- [x] Unit tests cover URL rewriting (absolute → path; already-relative unchanged), response decoding, and that a Cloudflare login redirect becomes an authentication error rather than a parse error
- [x] No server, iOS, `docker-compose.yml` or `cloudflared/` file is modified

## Browser checklist for the developer

- [ ] The library shows your real comics with covers
- [ ] Network panel: every request goes to `localhost:5173`, none to `api.vistabanana.com`
- [ ] Sources panel: searching for your Client ID finds nothing
- [ ] Blank `CF_ACCESS_CLIENT_ID` in `web/.env`, restart `npm run dev`: the page says the token is the problem, not that the library is empty
- [ ] Network off: the failure message and its retry appear; network back on, retry recovers

## What was built

- `web/package.json`, `vite.config.ts`, `tsconfig.json`, `index.html`, `.gitignore` — the project. `vite.config.ts` owns the proxy and is the only code that reads the token.
- `web/src/api/client.ts` — `toMediaPath`, `getJson` with error shaping into `auth` / `unavailable` / `notFound` / `unexpected`, and `fetchComics`. Requests use `redirect: 'manual'` so an Access redirect stays visible instead of being followed into a cross-origin login page and surfacing as a network error.
- `web/src/api/client.test.ts` — 12 tests: URL rewriting, decoding, and every error path including an opaque redirect, a 302, a 200 HTML login page and a 403.
- `web/src/stores/library.ts`, `views/LibraryView.vue`, `components/ErrorState.vue`, `router.ts`, `App.vue`, `main.ts`.

## Verification done

- `vue-tsc --noEmit` clean; 12/12 unit tests pass; `vite build` succeeds.
- **Through the real proxy against the live backend:** `GET /comics` → 200 JSON, 14 comics. A rewritten cover path → 200 `image/jpeg`. The same cover at its raw `https://api.vistabanana.com/...` URL without the token → **403** — so the rewrite is load-bearing, not defensive.
- The built bundle contains no token value, no `CF-Access` header name, and no `vistabanana` hostname. `CF_ACCESS` appears twice, both inside the auth-error hint text that names the variables for the developer.
- The dev server listens on `127.0.0.1:5173` only; the machine's LAN address refuses the connection.
- `git status`: only `web/` added. No server, iOS, compose or tunnel file touched.

## Notes for whoever touches this next

- **TypeScript is pinned to 5.x** (`5.9.3`). npm resolves `typescript@latest` to 7.0, the Go-native compiler, which has no JS API (`ts.createProgram` is undefined) — and `vue-tsc` is built on that API. Its peer range says `>=5.0.0`, so npm happily installs 7 and `vue-tsc` breaks with an error that does not name the cause. Do not "upgrade" it.
- **Cloudflare now answers an untokened request with 403, not the 302** recorded in `.scratch/remote-access/issues/01`. The client treats any 3xx, 401, 403 and a non-JSON 200 as `auth`, so both are covered and tested.
- npm's install-script gate blocked `fsevents` (macOS file watching). It ships a prebuilt binary and Vite falls back to `fs.watch` either way, so it was left blocked rather than approved on the developer's behalf.
