Status: done (2026-10-06)

# Web reader MVP: manga on a computer screen, from localhost

> **Revised 2026-10-06.** The first version of this spec served the frontend from the `api` container at a new public hostname (`comic.vistabanana.com`) behind a Cloudflare Access email login. Two facts retired that design: the backend runs on a separate Ubuntu machine at home, not on the development Mac, and the developer does not need the web reader to be publicly hosted at all. It now runs on `localhost` and talks to the existing `api.vistabanana.com` exactly as the iOS app does. The public-hosting design is not discarded — it is deferred, see Out of Scope.

## Problem Statement

`vista_comic` runs only on iOS. The library, the reader and the vocabulary it collects are reachable only from a phone. The developer wants to read on a computer, and eventually to do the whole learn-while-reading flow there.

`.scratch/web-client/map.md` settled the architecture and split it into six parts, which is more than can be taken on at once. This spec is the thinnest thing that puts the developer's manga on a computer screen.

## Solution

A Vue 3 application run on the developer's own computer with `npm run dev`, opened at `http://localhost:5173`. It has three screens — **library → chapter list → reader** — and the reader stacks a chapter's pages in one continuously scrolling column.

The Vite dev server forwards `/comics` and `/media` to the production backend at `https://api.vistabanana.com`, attaching the same Cloudflare Access Service Token the iOS app uses:

```text
browser ── localhost:5173 ──► Vite dev server ── + CF-Access-Client-Id/Secret ──► api.vistabanana.com (Ubuntu, unchanged)
```

**Nothing on the server changes**: not the backend code, not the Dockerfile, not the tunnel, not Cloudflare. The web reader is one more client of an API that already exists, which is the whole point.

The three endpoints it needs already return exactly what is needed:

```text
GET /comics                                 → library
GET /comics/{comicId}                       → chapters
GET /comics/{comicId}/chapters/{chapterId}  → pages: [absolute image URLs]
GET /media/...                              → image bytes
```

Reading progress is not written, and no resume position is read. OCR, the learning flow, the card library and review are out.

## User Stories

1. As the reader, I want to open a page in my browser and see my manga library, so that I can read on my computer instead of my phone.
2. As the reader, I want to pick a comic and see its chapters, so that I can choose where to read.
3. As the reader, I want a chapter's pages in one continuous scrolling column, so that reading works the way the material is drawn — as a vertical strip.
4. As the reader, I want pages centred in a column no wider than 800px and never upscaled, so that the Vietnamese lettering stays as sharp as the source.
5. As the reader, I want the rest of a chapter not to download until I scroll to it, so that opening an eighty-page chapter does not stall on a hundred megabytes of images.
6. As the reader, I want this to work wherever my computer has internet, so that I am not tied to the home network — which it does for free, since it goes through the same tunnel the phone does.
7. As the reader, I want to be told when something has not loaded and be able to retry, so that a dropped request looks different from an empty library, and a bad token looks different from both.
8. As the developer, I want the Service Token never to reach the browser or the repository, so that running the reader does not leak the key that guards my library.
9. As the developer, I want no change to the server, the iOS app, the API contract or the database, so that this cannot disturb anything already working.

## Implementation Decisions

### Where it lives

- **`web/` at the repository root**, a self-contained Vue 3 project with its own `package.json`. Vue 3 + Pinia + Tailwind, per `.scratch/web-client/issues/08-frontend-stack-and-browser-access.md`.
- Three layers, following the `state-api-integrator` convention: a thin API client that owns `fetch`, URL handling and error shaping; Pinia stores holding catalog state; components that read stores and never call `fetch` themselves.
- **How it runs is `npm run dev`, and that is the entire deployment.** There is no build-and-host step in this spec.

### The proxy and the token

- `vite.config` reads `web/.env` through `loadEnv` and proxies `/comics` and `/media` to `VISTA_API_ORIGIN` with `changeOrigin: true`, adding `CF-Access-Client-Id` and `CF-Access-Client-Secret` to every forwarded request. `changeOrigin` is required: Cloudflare routes by hostname, and a forwarded `Host: localhost:5173` would match no tunnel route.
- **`web/.env` holds the token and is gitignored** — covered by the repository root `.gitignore`'s `.env` rule, confirmed with `git check-ignore`.
- **The variables must not be prefixed `VITE_`.** Vite embeds every `VITE_*` variable into the browser bundle, which would publish the token to anyone who opens developer tools. Only the Node-side config ever reads them.
- **The dev server stays bound to `localhost`** (Vite's default). Bound to the LAN, any machine on the network could use the proxy — and therefore the token — to read the library.
- Because the browser only ever talks to `localhost:5173`, there is no cross-origin request and no CORS configuration anywhere.

### Absolute URLs must be rewritten — the one trap in this design

The backend builds page and cover URLs from the host it was reached on, so through the proxy they come back as `https://api.vistabanana.com/media/...`. Used as-is, an `<img>` would go straight to Cloudflare **without** the token and be refused: the library would load and **every image would be broken**.

**The API client therefore reduces every media URL to its path** (`/media/...`) before it reaches a component, so images go through the proxy like everything else. One function, applied to `coverUrl` and to every entry of `pages`, and unit-tested — it is the single place where this design can fail silently.

### Telling failures apart

- A request Cloudflare refuses does not return an error status the way the API does: Access answers with a redirect to its login page. The client must recognise "this is not the API's JSON" and report it as **an authentication problem — the token is missing or wrong** — distinct from the network being down and distinct from an empty library.
- Every screen handles **loading, failure-with-retry, and empty**.
- Individual page images that fail render a placeholder in place rather than failing the chapter.

### The reader

- **Continuous vertical scroll, images stacked in document order.**
- **A column at most 800px wide; wider pages scale down, narrower pages stay at natural size, centred. Never upscaled.**

  *Corrected 2026-10-06.* This originally said "a fixed column at the source's natural width", on the premise that every page is 900px wide. That premise came from the OCR project's samples, which were all webtoon strips, and it is false for this library: Frieren's first chapter mixes 1000px and 836px pages, a webtoon runs 800px, and Conan's first chapter runs from 446px to a 1890px double-page spread. Natural width taken literally would make the column change width page by page. The developer chose the cap-without-upscaling rule over stretching every page to one width (blurs narrow pages) and over fitting each page to the window height (shrinks webtoon strips).
- **Native `loading="lazy"` on every page image**, which satisfies story 5 with no observer and no prefetch logic.
- Each image reserves its space before loading where the aspect ratio is known, so scrolling does not jump as pages arrive.

### Language

**Traditional Chinese written directly in the components. No i18n library.** This departs knowingly from the iOS rule against hardcoded Chinese: the MVP has roughly ten strings, and a translation layer for ten strings costs more than extracting them later would.

### Deliberately included, though adjacent to a cut

`GET /comics/{comicId}` already returns each chapter's `readState`, so the chapter list shows read / reading / unread as a badge — chapters read on the phone become visible on the computer. It is free (same response, no extra call) and **displays only, never writes**. Flagged because it sits next to a feature that was explicitly cut; say the word and it goes.

## Testing Decisions

- **Unit tests for the API client layer**: media-URL rewriting (absolute → path, already-relative left alone), response decoding, and error shaping — including that a Cloudflare login redirect is reported as an authentication failure rather than a parse error.
- **No backend tests and no server-side verification**, because nothing on the server changes.
- **Browser verification belongs to the developer**, per `CLAUDE.md`. The deliverable is a checklist, at minimum:
  - The library renders with covers from the real catalog.
  - A chapter opens and scrolls end to end; images beyond the first screen arrive as they are scrolled to, confirmed in the network panel.
  - **In the network panel, every request goes to `localhost:5173`** — none to `api.vistabanana.com`. A request there means a URL escaped the rewrite.
  - Page images are not upscaled (rendered width equals natural width).
  - With the token blanked in `web/.env` and the dev server restarted, the app reports an authentication problem rather than an empty library or a blank page.
  - With the network off, the failure state and its retry appear.
  - The iOS app still works, unchanged.
  - The bundle contains no token: search the browser's loaded sources for the client ID and find nothing.

## Out of Scope

- **Public hosting of the web reader.** Serving it from the `api` container at `comic.vistabanana.com` behind a Cloudflare Access email login was this spec's first design and is the plan of record if it is ever wanted — `.scratch/web-client/issues/03-same-origin-static-serving.md` and `08-frontend-stack-and-browser-access.md` hold the reasoning. Because the server is a separate machine, that version would build the frontend inside the `api` image rather than bind-mounting a `dist/` built elsewhere.
- **Any change to the server**: backend code, Dockerfile, `docker-compose.yml`, `cloudflared/config.yml`, Cloudflare Access.
- **Reading progress, in both directions.** Writing it needs a rule for what counts as read while scrolling, and this repo already has a defect report about that judgement on iOS (`.scratch/reader-auto-advance-false-trigger/`).
- **OCR, translation, explanation, the card library, review** — parts ①, ④, ⑤ and ⑥ of the map.
- **Page prefetch, offline reading, a service worker.**
- **Next-chapter navigation from the end of a chapter.** Browser back already reaches the chapter list.
- **Any change to the iOS app, the API contract, or the schema.**
