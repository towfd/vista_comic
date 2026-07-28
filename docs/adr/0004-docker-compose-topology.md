# Docker Compose: two services, Redis deferred

Status: accepted (2026-07-23)

The backend runs as a two-service Docker Compose stack — `api` and `postgres` — with the Library folder read-only bind-mounted into `api`. Postgres pulls in a container regardless once Progress persistence exists (ADR-0002), so containerizing `api` alongside it buys a reproducible one-command local stack for free. Redis was considered and explicitly deferred: the Catalog already lives in-memory inside the single `api` process, so a Redis cache is a slower network hop with no job to do today. It is only worth adding when there is a concrete trigger — multiple uvicorn workers/processes needing to share one cached Catalog (so re-scans aren't repeated per worker), or measured slowness on large libraries / many clients. Should that trigger occur, Redis slots in behind the API's Catalog seam as a third Compose service.
