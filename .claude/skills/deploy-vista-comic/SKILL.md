---
name: deploy-vista-comic
description: Merge a vista_comic pull request and deploy it to the home server. Use only when the user explicitly asks, in this request, to merge and/or deploy (合併, 部署, "merge and deploy"). Opens the PR first if none exists (following ship-vista-comic), merges it, deletes the branch, then rebuilds only the containers the change touches on the deploy host and verifies them. A request to just open a PR is ship-vista-comic, not this.
---

# Deploy vista_comic

Take a change from branch to running on the home server: pull request, merge,
deploy, verify. The pull request half is `ship-vista-comic`; this skill adds
the merge and the deploy.

## Authorization gate

Proceed only when the user, **in this request**, asked to merge, deploy, or
both. Approval given for an earlier change does not carry over to this one.

- "Open a PR" alone → use `ship-vista-comic` and stop there.
- "Merge" without "deploy" → do steps 1–2 only, then ask whether to deploy.
- "Deploy" of something already merged → skip to step 3.

## 1. Pull request

If the change has no open PR yet, follow `ship-vista-comic` in full — its
verification, exclusions, commit and PR conventions all apply. For a change
under `web/`, verification is:

```sh
cd web && npm run typecheck && npm run build && npm test
```

If a PR already exists, confirm its checks and diff are what the user reviewed.

## 2. Merge

```sh
gh pr merge <n> --merge --delete-branch   # the repo's history uses merge commits
git checkout main && git pull --ff-only && git fetch --prune
```

Delete any local branch left behind. If the merge is refused (conflict, failing
check, review required), stop and report — do not force it.

## 3. Decide what to rebuild

Look at the paths the merged change touched (`git diff --name-only <base>..<merge>`):

| Touched | Rebuild |
| --- | --- |
| `backend/` (with or without `web/`) | `api web` — api runs its alembic migrations on start |
| `web/` only | `web` |
| `docker-compose.yml`, `web/nginx.conf.template`, `web/Dockerfile` | the services they configure; say which and why |
| only `vista_comic/` (iOS), docs, `.scratch/`, `.claude/` | nothing — say so and stop; the server does not run it |

Never rebuild, restart, or stop `postgres` or `cloudflared`. cloudflared is the
production tunnel; the user switches it themselves.

## 4. Reach the host

The deploy host is one machine with two addresses. Try the LAN first, then the
tailnet:

```sh
ssh -o ConnectTimeout=8 -o BatchMode=yes agent@192.168.0.45 hostname \
  || ssh -o ConnectTimeout=8 -o BatchMode=yes agent@100.84.22.60 hostname
```

Expect hostname `agent-Aspire-TC-1750`. If neither answers, or another machine
answers, stop and report.

## 5. Deploy

On the host, in `~/Documents/vista_comic`:

1. `git status --short`. The only expected change is the user's own
   `web/package-lock.json` — leave it alone. Anything else unexpected: stop and ask.
2. `git pull --ff-only`. If it is not a fast-forward, stop and report.
3. `docker compose up -d --build <services from step 3>`.

Never on this host:

- rsync or copy `comic-ocr-data` from the Mac — the host's copy is the newer one;
- edit `.env` or `web/.env`;
- roll back on a failure without being asked — report instead.

## 6. Verify

On the host:

- `git log --oneline -1` matches the merge commit on `main`;
- `docker compose ps` — rebuilt services are up; `api` reports healthy if rebuilt;
- `curl -s -o /dev/null -w '%{http_code}' localhost:8080/` returns 200 (web's nginx);
- where practical, one probe that shows the new code is live — e.g. a string
  from the change in the served bundle (`localhost:8080/assets/index-*.js`), or
  the changed endpoint through `localhost:8080/<path>`.

A failed check is reported as failed, with its output.

## Report

Return, in the user's language:

- PR link and merge commit;
- which host address was used;
- services rebuilt, and why those;
- verification results;
- what the user should look at on a real device.
