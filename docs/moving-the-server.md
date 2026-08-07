# Moving the backend to another machine

Everything this stack needs is either in the repository, re-downloadable, or one
file you copy — **except the Postgres volume**. Reading progress and 歷史紀錄 live
there, they are not in git, and they do not travel with the Docker image. That is
the part to be careful with; the rest is logistics.

The tunnel hostname does not change, so **the iOS app needs no rebuild and no
config edit**. `cloudflared` dials out to Cloudflare's edge, so the new machine
needs no port forwarding, no static IP, and no inbound firewall rule.

## What has to move

| Thing | Where it is now | How it moves |
| --- | --- | --- |
| Code | git | `git clone` |
| `.env` | gitignored, repo root | Copy by hand. **`MANGA_LIBRARY_PATH` must be rewritten** for the new machine. |
| The manga library | a folder on disk | Copy. The largest transfer, and the one you could redo from scratch. |
| **Postgres data** | the `pg_data` named volume | **`pg_dump` → restore.** The only thing here that cannot be rebuilt. |
| Tunnel credentials | `cloudflared/<uuid>.json` (gitignored) + `cloudflared/config.yml` | Copy both files. |
| iOS build config | `vista_comic/Config/Secrets.xcconfig` | Nothing to do — the hostname is unchanged. |

## The one ordering rule

**Stop `cloudflared` on the old machine before starting it on the new one.**

One tunnel ID running in two places is not an error Cloudflare rejects — it
treats them as replicas and balances between them. Requests would land on
whichever machine answered, and those two machines have different databases.
The symptom is an app that intermittently shows stale progress or a missing
record, which is far harder to diagnose than an outage.

## Steps

### On the old machine

```bash
# 1. Dump the database. Plain SQL: readable, and restores with psql.
docker compose exec -T postgres pg_dump -U vista -d vista > vista-backup.sql

# 2. Sanity-check the dump before trusting it. Four tables should appear —
#    progress, comprehension_record, comprehend_usage, and alembic_version.
#    That last one is what makes step 7 a no-op instead of a failed migration.
grep "^COPY public" vista-backup.sql
```

This round trip was exercised against a throwaway database while writing this
file: 9 progress rows and 9 comprehension records restored clean, with
`alembic_version` intact. The commands are transcribed from a run, not from
memory.

Take `vista-backup.sql`, the repo-root `.env`, and both files in `cloudflared/`.

### On the new machine

```bash
# 3. Docker, once.
sudo apt install docker.io docker-compose-v2      # or the distro equivalent
sudo usermod -aG docker "$USER"                   # log out and back in

# 4. Code and secrets.
git clone <this repo> && cd vista_comic
cp /path/from/old/.env .env                       # then edit MANGA_LIBRARY_PATH
cp /path/from/old/cloudflared/* cloudflared/

# 5. The library, wherever MANGA_LIBRARY_PATH now points.

# 6. Database first, alone.
docker compose up -d postgres
docker compose exec -T postgres psql -U vista -d vista < vista-backup.sql

# 7. Then the API. Migrations are a no-op: the dump carried `alembic_version`,
#    so `upgrade head` finds it already at head.
docker compose up -d api
curl -s localhost:8000/healthz
curl -s localhost:8000/comics | head -c 200
```

Confirm the data actually arrived — an empty library reads the same as a working
one until you look:

```bash
docker compose exec -T postgres psql -U vista -d vista \
  -c "SELECT count(*) FROM progress;" \
  -c "SELECT count(*) FROM comprehension_record;" \
  -c "SELECT * FROM alembic_version;"
```

### The switchover

```bash
# 8. On the OLD machine — this is the ordering rule above.
docker compose stop cloudflared

# 9. On the NEW machine.
docker compose up -d cloudflared

# 10. Through the public hostname, from anywhere.
curl -s -H "CF-Access-Client-Id: ..." -H "CF-Access-Client-Secret: ..." \
  https://api.vistabanana.com/healthz
```

Then open the app. If the library and your reading positions look right, the move
is done and the old machine can be shut down.

## Worth fixing while you are here

Two things that were fine on a laptop and are worth a second look on a machine
that is now a server, reachable by everything else on its network:

- **Postgres has no password set.** `.env` does not define `POSTGRES_PASSWORD`,
  so compose falls back to its `vista` default, and port 5432 is published to the
  host. On a LAN that is one `psql` away for anyone on it. Setting
  `POSTGRES_PASSWORD` in `.env` before the first `up` is the cheap moment — after
  data exists, changing it means altering the role as well.
- **Port 8000 bypasses Cloudflare Access.** Access control is enforced at
  Cloudflare's edge, in front of the tunnel (ADR-0005), so anything that can
  reach the machine directly on `:8000` is not gated by it at all. Either drop
  the `ports:` mapping for `api` — `cloudflared` reaches it over the compose
  network and does not need it — or bind it to loopback with
  `"127.0.0.1:8000:8000"`.

Neither is a change this document makes on your behalf; both are decisions about
your own network.

## Not covered here

- **Setting up a different tunnel.** These steps move the existing one. Creating
  a new named tunnel and hostname is the original setup, documented in
  `.scratch/remote-access/issues/01-public-tunnel-and-access-gate.md`, and it
  would mean rebuilding the iOS app against the new hostname.
- **Running both machines at once.** See the ordering rule: this stack has one
  database, and nothing reconciles two.
