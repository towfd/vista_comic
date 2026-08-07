# FastAPI "scan-and-serve" API, packaged unchanged (M5 Slice 4, sub-step A).
# Build context is ./backend (see docker-compose.yml at the repo root).
FROM python:3.12-slim

# Keep Python output unbuffered and skip .pyc files in the container.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install runtime dependencies first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application code (read-only at runtime; the manga library is bind-mounted).
COPY app ./app

# The schema's history. The app runs `alembic upgrade head` itself on startup
# (see `db.upgrade_schema`), so both the config and the revisions have to be in
# the image — a container that cannot find them cannot migrate, and by design
# will not serve.
COPY alembic.ini ./alembic.ini
COPY alembic ./alembic

EXPOSE 8000

# One uvicorn worker for now (single developer / single client). The manga
# library path is injected by compose as MANGA_LIBRARY_PATH=/library.
#
# --proxy-headers (+ trusting all forwarded-for IPs, since the only caller on
# this container's network is the `cloudflared` sidecar) makes uvicorn honor
# the X-Forwarded-Proto Cloudflare's edge sets on tunneled requests. Without
# it, request.base_url always reports the scheme cloudflared used internally
# (plain http), so every media URL comes back http:// even over the public
# https:// tunnel — which iOS's App Transport Security then blocks.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
