Type: grilling
Status: resolved

# Frontend stack and browser access

## Question

What does the frontend get built with, and does the web page need to work away from the home network?

## Answer

**Vue 3 + Pinia + Tailwind**, and **yes — a browser login policy is added to Cloudflare Access.**

The stack is chosen for tooling that already exists rather than on language merits: this repo's agent roster carries three Vue 3 specialists (`frontend-ui-architect`, `state-api-integrator`, `echarts-specialist`), all of them configured for exactly Vue 3 + Pinia + Tailwind against a FastAPI backend.

On reachability: the LAN route is already free. `api` publishes `8000:8000`, so once the frontend is mounted, `http://<mac-ip>:8000/` works from the house with no Cloudflare configuration and no authentication at all. The decision is only about the tunnel.

Today the Access policy in front of the tunnel admits **only** the Service Token issued to the iOS app, so a browser hitting the public hostname has no way in — there is no human identity configured. A second policy is added alongside it, using Cloudflare's built-in one-time email PIN so no external identity provider has to be introduced. The two policies coexist: the app keeps its token, the browser gets a login and a `CF_Authorization` cookie.

**Settled concretely 2026-09-22 (see `.scratch/web-reader-mvp/spec.md`): two Access applications rather than two policies on one.** Access binds to a hostname, and there are now two — so `api.vistabanana.com` keeps the Service Token policy untouched for iOS, and `comic.vistabanana.com` gets a one-time-email-PIN policy allowlisting a single address. Each door carries exactly one key, so neither auth method can be used to widen the other: the API hostname refuses a browser login, and the web hostname refuses the Service Token.

`postgres` remains unexposed, exactly as `.scratch/remote-access/spec.md` requires.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
