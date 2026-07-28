# 01 — Public tunnel + Access gate

**What to build:** A stable, publicly reachable HTTPS endpoint for the `api` service — `cloudflared` added as a third Docker Compose service, bound to a named Cloudflare Tunnel on a subdomain of the developer's existing Cloudflare-managed domain, with Cloudflare Access configured in front of it and a Service Token issued for the app. Only `api` gets a tunnel route; `postgres` stays on the internal Compose network only.

**Blocked by:** None — can start immediately

**Status:** done (verified 2026-07-27)

- [x] `docker-compose.yml` runs a `cloudflared` service alongside `api` and `postgres`; `docker compose up` brings all three up together and `cloudflared` logs show a healthy connection to Cloudflare's edge.
- [x] The named tunnel routes the public hostname (`api.vistabanana.com`) to the `api` service's internal Compose address — not `localhost`, not `postgres`.
- [x] The tunnel credentials file is gitignored and never committed, matching the existing `.env` secret discipline (`MANGA_LIBRARY_PATH`, `DATABASE_URL`).
- [x] Cloudflare Access is configured on the public hostname; a Service Token is issued and added to the Access policy as an allowed service auth method.
- [x] A request to the public hostname's `/healthz` **without** the Service Token headers is rejected by Access (302).
- [x] A request to the public hostname's `/healthz` **with** the Service Token headers (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) succeeds (200).
- [x] `postgres` port `5432` is not reachable via the public hostname/tunnel — only via the existing LAN/localhost path (no ingress rule routes to it; `config.yml` has a single hostname entry + catch-all 404).
- [x] `docs/adr/0005-cloudflare-tunnel-for-public-connectivity.md` and `docs/api-contract.md`'s Connectivity section are updated to record Access as adopted (superseding "no Access policy for now") and the Service Token as the auth mechanism.

## Comments

Verified end-to-end 2026-07-27: tunnel `689fa4a3-7d1f-444b-93a0-84a093b429d2` routes `api.vistabanana.com` → `api:8000`; `docker compose logs cloudflared` showed 4 registered edge connections; `/healthz` returned real data (`{"status":"ok","comics":2,"chapters":6}`) with valid Service Token headers, and a 302 (Access login redirect, `service_token_status: false`) without/with-wrong headers.
