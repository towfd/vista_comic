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
