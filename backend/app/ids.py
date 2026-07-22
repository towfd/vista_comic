"""Stable, server-generated IDs.

Load-bearing requirement: comic and chapter IDs must be identical across
scans and restarts because future reading-progress persistence keys on them.
We derive each ID from a SHA-1 of the item's relative POSIX path under the
library root. This is deterministic, collision-resistant for our scale, and
independent of scan order, absolute path, or machine.

IDs are opaque: ``/media/...`` paths use these IDs rather than raw folder
names, which also avoids path-encoding and traversal concerns.
"""

from __future__ import annotations

import hashlib
from pathlib import PurePosixPath

# 16 hex chars (64 bits) is ample for a single developer's library and keeps
# URLs short. Widen if collisions ever appear (they will not at this scale).
_ID_LENGTH = 16


def stable_id(*relative_parts: str) -> str:
    """Return a stable ID for a library item identified by path segments.

    ``stable_id("marrymyhusband")`` -> comic ID.
    ``stable_id("marrymyhusband", "01-bai1")`` -> chapter ID.

    Segments are joined with ``/`` so the hash reflects the relative path,
    not the absolute location on disk.
    """
    rel = PurePosixPath(*relative_parts).as_posix()
    digest = hashlib.sha1(rel.encode("utf-8")).hexdigest()
    return digest[:_ID_LENGTH]
