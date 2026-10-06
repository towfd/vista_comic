Type: grilling
Status: resolved

# Same-origin: FastAPI serves the built frontend

## Question

Where does the web frontend live relative to the existing FastAPI service — same origin, a separate subdomain, a separate deployment, or LAN-only?

## Answer

**Same origin. FastAPI mounts the frontend's build output and serves it alongside the API**, so the page and every request it makes share one hostname.

The deciding constraint is the manga pages themselves. They load through `<img src="/media/...">`, and an `<img>` tag cannot carry a custom header — so the Service Token pair that authenticates the iOS app against Cloudflare Access (`CF-Access-Client-Id` / `CF-Access-Client-Secret`, see `.scratch/remote-access/spec.md`) is unusable for images in a browser. The browser's route through Access is a login that sets a `CF_Authorization` cookie, and a cookie is what `<img>` sends automatically.

A subdomain split (`web.` + `api.`) was examined and is genuinely workable — subdomains are cross-origin but same-site, so a cookie scoped to the registrable domain does reach the API. It was rejected on its three extra pieces of configuration (a CORS allowlist with credentials enabled, the Access cookie's domain scope, and a second Access application), each of which is the kind of thing that is only discovered to be wrong after it is wrong, bought in exchange for a frontend/backend deployment split that a single-user stack on one machine has no use for.

Adding a second framework (Django, Flask) as a middle layer was raised and rejected: they are the same kind of thing as FastAPI, so it is a second identical server rather than a new layer, and it reintroduces the origin split it was meant to avoid. nginx or Caddy would be the correct choice if a separate static server were wanted at all; it is not.

**Amended 2026-09-22 — two hostnames, and the decision is unchanged.** The web is served at `comic.vistabanana.com` while iOS keeps `api.vistabanana.com`, both routed by the tunnel to the same `api` container. This is **not** the subdomain split rejected above. That split meant a page on one host calling an API on another; this is one service answering on two names, with each client touching exactly one of them end to end. `_base_url(request)` builds media URLs from the host the request arrived on, so both clients get same-origin URLs without configuration. Still no CORS, still no cookie-domain scoping. The one discipline it imposes: the frontend must call the API by relative path, since an absolute `https://api.vistabanana.com/...` would manufacture the very split this rejects.

**Two consequences worth carrying forward**: the frontend stays an independent project with its own build and its own dev server (Vite, with a proxy) — same-origin is about what is deployed, not about how it is developed. And a same-origin `<img>` leaves the canvas untainted, which is what makes [browser-side cropping](05-ocr-service-interface.md) possible at all.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
