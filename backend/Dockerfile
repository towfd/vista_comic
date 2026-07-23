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

EXPOSE 8000

# One uvicorn worker for now (single developer / single client). The manga
# library path is injected by compose as MANGA_LIBRARY_PATH=/library.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
