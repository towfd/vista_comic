"""Runtime configuration.

The manga library path is machine-specific and lives only in the repo-root
gitignored ``.env`` as ``MANGA_LIBRARY_PATH``. It is never hardcoded or
committed. We load ``.env`` if present, then read the environment variable.
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

# The repo root is two levels up from this file: backend/app/config.py -> repo/
_REPO_ROOT = Path(__file__).resolve().parents[2]
_ENV_PATH = _REPO_ROOT / ".env"

# Load the gitignored .env from the repo root (no-op if it is missing).
load_dotenv(dotenv_path=_ENV_PATH)

_ENV_KEY = "MANGA_LIBRARY_PATH"
_DB_ENV_KEY = "DATABASE_URL"
_CLAUDE_API_KEY_ENV_KEY = "ANTHROPIC_API_KEY"

# Non-secret local default used when DATABASE_URL is unset (e.g. a local
# uvicorn dev run after ``docker compose up`` published Postgres on localhost).
# The real URL / password live only in the gitignored repo-root ``.env`` (or,
# for the container, in the compose ``environment:``) and are never committed.
_DEFAULT_DATABASE_URL = "postgresql+psycopg://vista:vista@localhost:5432/vista"


def get_database_url() -> str:
    """Return the SQLAlchemy URL for the reading-progress Postgres store.

    Read from the ``DATABASE_URL`` environment variable (loaded from the
    gitignored repo-root ``.env`` or injected by Docker Compose). Falls back to
    a non-secret localhost default so a local dev run works once the compose
    Postgres is up. Same variable, two scopes: the container uses host
    ``postgres`` (set via compose ``environment:``); local dev/tests use
    ``localhost``.
    """
    return os.environ.get(_DB_ENV_KEY) or _DEFAULT_DATABASE_URL


def get_claude_api_key() -> str:
    """Return the Claude (Anthropic) API key backing ``POST /comprehend``.

    Read from the ``ANTHROPIC_API_KEY`` environment variable (loaded from the
    gitignored repo-root ``.env``, same pattern as ``MANGA_LIBRARY_PATH``) --
    the same name the ``anthropic`` SDK itself resolves by default.
    Mirrors ``get_library_root()``'s fail-loudly stance rather than
    ``get_database_url()``'s fallback-default one: unlike Postgres (which has a
    non-secret local dev default), there is no safe default API key, so a
    caller that needs it should get a clear error immediately rather than
    silently failing inside the Anthropic SDK. Never logged, never returned in
    a response body -- callers use this only to construct the SDK client.
    """
    raw = os.environ.get(_CLAUDE_API_KEY_ENV_KEY)
    if not raw:
        raise RuntimeError(
            f"{_CLAUDE_API_KEY_ENV_KEY} is not set. Define it in {_ENV_PATH} "
            "(gitignored) or export it in the environment."
        )
    return raw


def get_library_root() -> Path:
    """Return the configured manga library root as an absolute Path.

    Raises a clear error if the variable is unset or the path does not exist,
    so startup fails loudly rather than serving an empty catalog silently.
    """
    raw = os.environ.get(_ENV_KEY)
    if not raw:
        raise RuntimeError(
            f"{_ENV_KEY} is not set. Define it in {_ENV_PATH} "
            "(gitignored) or export it in the environment."
        )
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        raise RuntimeError(f"{_ENV_KEY} does not point to a directory: {root}")
    return root
