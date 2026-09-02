"""Runtime configuration.

The manga library path is machine-specific and lives only in the repo-root
gitignored ``.env`` as ``MANGA_LIBRARY_PATH``. It is never hardcoded or
committed. We load ``.env`` if present, then read the environment variable.
"""

from __future__ import annotations

import os
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv

# The repo root is two levels up from this file: backend/app/config.py -> repo/
_REPO_ROOT = Path(__file__).resolve().parents[2]
_ENV_PATH = _REPO_ROOT / ".env"

# Load the gitignored .env from the repo root (no-op if it is missing).
load_dotenv(dotenv_path=_ENV_PATH)

_ENV_KEY = "MANGA_LIBRARY_PATH"
_DB_ENV_KEY = "DATABASE_URL"
_CLAUDE_API_KEY_ENV_KEY = "ANTHROPIC_API_KEY"
_SCHEDULING_TZ_ENV_KEY = "SCHEDULING_TIMEZONE"


# Non-secret local default used when DATABASE_URL is unset (e.g. a local
# uvicorn dev run after ``docker compose up`` published Postgres on localhost).
# The real URL / password live only in the gitignored repo-root ``.env`` (or,
# for the container, in the compose ``environment:``) and are never committed.
_DEFAULT_DATABASE_URL = "postgresql+psycopg://vista:vista@localhost:5432/vista"

# Whose midnight the day-length intervals roll over on. Not a secret and not
# machine-specific in the way the library path is -- it is a statement about
# the reader, who is one person in one place -- so it has a real default here
# rather than failing loudly, and ``.env`` only has to say anything if that
# person moves.
_DEFAULT_SCHEDULING_TIMEZONE = "Asia/Taipei"


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
    """Return the Claude (Anthropic) API key the comprehension worker calls with.

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


def get_scheduling_timezone() -> ZoneInfo:
    """Return the timezone whose day boundary the review schedule counts in.

    A card on a day-length interval comes back at the start of a **reader's**
    day, not at the instant-plus-24-hours the answer happened to land on (see
    ``ladder.due_after``). Turning "the day after next" into a stored UTC
    moment needs a zone, and the server has no way to know one: it is the
    reader's, and every request that carries a day already says so in the
    reader's terms (``local_date``, and the note on ``StudyRepository`` about a
    UTC boundary landing at eight in the morning on UTC+8).

    Configured rather than sent because this is a single-reader deployment.
    Sending an offset with each answer would be more correct while travelling
    and is a one-field change if that ever matters; a fixed zone is the honest
    description of the system as it stands, and travelling under it means days
    keep rolling over on home time -- which is arguably what a study streak
    should do anyway.

    The offline path is the app's own ``dueAfter``, which uses
    ``TimeZone.current`` because a phone always knows. The two agree at home
    and reconcile on sync, where the server's answer wins.
    """
    return ZoneInfo(
        os.environ.get(_SCHEDULING_TZ_ENV_KEY) or _DEFAULT_SCHEDULING_TIMEZONE
    )
