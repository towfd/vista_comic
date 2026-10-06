Type: grilling
Status: resolved

# The MVP: one thin path to manga on screen

## Question

The six-part split is right as an architecture, and too much to take on at once. What is the thinnest thing worth building first, and what does it deliberately leave out?

## Answer

**Library list -> chapter list -> read the pages. Nothing else.**

It is thinner than parts ② and ③ rather than equal to them: it is a slice *across* both, taking only what putting a page on screen requires.

**In:**

- The `web/` project, the application shell, routing, and the API client layer (from ②)
- FastAPI serving the build output (from ②)
- The Cloudflare Access browser-login policy (from ②) — **the developer chose to do this now rather than defer it**; LAN-only was recommended and declined, so the MVP is reachable away from home on the day it works
- Browsing and continuous reading (from ③)

**Out:**

- **Reading progress, in both directions.** Writing it needs a rule for what counts as "read" while scrolling, and this repo already has a defect report about exactly that judgement on iOS (`.scratch/reader-auto-advance-false-trigger/`). Reading `lastReadPage` to resume was offered as a middle ground and also declined. The web does not touch progress at all.
- Page prefetch, offline anything, OCR, the learning flow, the card library, review.

**Backend changes: three lines.** Mounting the build output is the whole of it. The three endpoints this needs already exist and already return exactly the right thing — `GET /comics`, `GET /comics/{id}`, `GET /comics/{id}/chapters/{chapterId}` — and the last returns absolute page URLs built from `_base_url(request)`, so under [same-origin serving](03-same-origin-static-serving.md) they point at the right host with no configuration at all.

**Why this before part ①.** [Part ①](09-the-six-part-split.md) was the recommended starting point, on the grounds that it is independently verifiable and blocks nothing. Building the thin path first is better for a reason that outranks it: **it tests the assumptions nothing has tested yet.** Same-origin static serving, images loading in a browser against the real catalog, the Access cookie actually covering `/media/...` — all of it is reasoned-about and none of it is observed. Finding a hole there costs far less now than after a multi-gigabyte OCR image exists to rebuild around it.

**The six-part split is not superseded.** ②–⑥ keep their boundaries; the MVP takes a slice of two of them and the remainder of those two returns as ordinary work once the path is walkable.

**Amended 2026-10-06 — the MVP runs on localhost.** The backend lives on a separate Ubuntu machine, not the development Mac, and the developer does not need the reader publicly hosted. So the MVP is a Vite dev server on the developer's computer that proxies to the existing `api.vistabanana.com` with the iOS app's Service Token. That drops the Access browser policy, the `comic.` hostname, same-origin static serving and every server change from the MVP. Those remain the plan for public hosting if it is ever wanted. See `.scratch/web-reader-mvp/spec.md`.

## Comments

Resolved on the developer's own initiative, mid-effort: "先做一條路 讓我們可以在網頁上把漫畫顯示出來就好了 ... 現在這邊太大了".
