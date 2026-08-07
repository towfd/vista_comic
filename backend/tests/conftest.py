"""Shared fixtures for the backend test suite.

Every test builds its own temporary fixture tree under ``tmp_path``; nothing
here reads ``MANGA_LIBRARY_PATH`` or the developer's real library.

Reading-progress (Slice 4) tests run against a **throwaway** Postgres database,
never the dev progress DB. The URL is injectable via ``TEST_DATABASE_URL`` only
(it deliberately does NOT fall back to ``DATABASE_URL``, which usually points at
the dev DB), and the resolved database name **must end in ``_test``** or the
suite refuses to run — because every test ``TRUNCATE``s the ``progress`` table.
The default targets a separate ``vista_test`` database on ``localhost:5432``
(published by ``docker compose``); it is auto-created if missing and truncated
per test. Pure scanner/id/parsing tests do not depend on the DB fixtures.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

_IMG = b"fake-image-bytes"

# Separate DB name so tests never touch the dev progress DB (default: vista).
_DEFAULT_TEST_DATABASE_URL = (
    "postgresql+psycopg://vista:vista@localhost:5432/vista_test"
)


def _test_database_url() -> str:
    url = os.environ.get("TEST_DATABASE_URL") or _DEFAULT_TEST_DATABASE_URL
    # Data-loss guard: every test TRUNCATEs the `progress` table, so the suite
    # must NEVER run against a non-test database. We deliberately do NOT fall
    # back to DATABASE_URL (which normally points at the dev `vista` DB), and we
    # refuse any URL whose database name does not end in `_test`.
    name = make_url(url).database or ""
    if not name.endswith("_test"):
        raise RuntimeError(
            f"Refusing to run tests against database {name!r}: the test database "
            "name must end in '_test'. Set TEST_DATABASE_URL to a dedicated DB."
        )
    return url


def _ensure_test_database(url: str) -> None:
    """Create the target database if it does not exist (idempotent).

    Connects to the ``postgres`` maintenance database with AUTOCOMMIT because
    ``CREATE DATABASE`` cannot run inside a transaction.
    """
    parsed = make_url(url)
    db_name = parsed.database
    maintenance = create_engine(
        parsed.set(database="postgres"), isolation_level="AUTOCOMMIT", future=True
    )
    try:
        with maintenance.connect() as conn:
            exists = conn.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :n"),
                {"n": db_name},
            ).scalar()
            if not exists:
                conn.execute(text(f'CREATE DATABASE "{db_name}"'))
    finally:
        maintenance.dispose()


@pytest.fixture(scope="session", autouse=True)
def _never_touch_the_dev_database():
    """Point every database-URL lookup at the throwaway database, for the whole
    session, whether a test asked for a DB fixture or not.

    The `_test`-suffix guard above protects the engine the fixtures build. It
    cannot protect `alembic/env.py`, which imports `config.get_database_url`
    itself when Alembic execs it — so a bare `db.upgrade_schema()` in a test
    would run migrations against the developer's real database, outside
    everything this file does to prevent exactly that. It happened once while
    writing these tests; Postgres's transactional DDL rolled it back and no data
    was lost, which was luck rather than design.

    Patching the source closes it: there is no longer a path from the test
    session to a database whose name does not end in `_test`.
    """
    from app import config, db

    url = _test_database_url()
    original_config, original_db = config.get_database_url, db.get_database_url
    config.get_database_url = lambda: url
    db.get_database_url = lambda: url
    try:
        yield
    finally:
        config.get_database_url = original_config
        db.get_database_url = original_db


@pytest.fixture(scope="session")
def _progress_engine():
    """Point the app's engine at the throwaway test DB and migrate it.

    Migrated rather than built from ``Base.metadata``, which is what this used
    to do via ``init_engine``. Alembic owns the schema now, and building the
    test schema a different way than production's would leave the suite
    validating something no deployment ever produces — a hazard
    ``docs/manual-migrations.md`` flagged while it was still true.

    Once per session: migrations are idempotent, and the per-test fixtures below
    truncate rather than rebuild.
    """
    from app import db

    url = _test_database_url()
    _ensure_test_database(url)
    engine = db.init_engine(url)
    db.upgrade_schema(url)
    # Defense-in-depth: the active engine must target a `_test` database, so a
    # future change (e.g. wrapping TestClient in `with`, which runs the app
    # lifespan and re-inits the engine from DATABASE_URL) can never silently
    # repoint the truncating tests at the dev DB.
    assert (make_url(str(engine.url)).database or "").endswith("_test")
    return engine


@pytest.fixture
def progress_db(_progress_engine):
    """Truncate the ``progress`` table before each test that uses the store."""
    with _progress_engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE progress"))
    return _progress_engine


@pytest.fixture
def db_session(progress_db):
    """A standalone session against the truncated test DB (caller-agnostic)."""
    from app import db

    session = db.new_session()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def comprehension_db(_progress_engine):
    """Truncate the comprehension record + usage tables before each test.

    Both, because the daily cap is *reserved* when a record is enqueued: a
    leftover count from a previous test would make cap assertions depend on
    execution order.
    """
    with _progress_engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE comprehension_record"))
        conn.execute(text("TRUNCATE TABLE comprehend_usage"))
    return _progress_engine


@pytest.fixture
def comprehension_session(comprehension_db):
    """A standalone session against the truncated comprehension tables."""
    from app import db

    session = db.new_session()
    try:
        yield session
    finally:
        session.close()



def _write_page(path: Path, data: bytes = _IMG) -> Path:
    """Create a fake page/cover file (metadata-only; contents are irrelevant)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


@pytest.fixture
def write_page():
    """Return a helper that writes a fake image file at an absolute path."""
    return _write_page


@pytest.fixture
def sample_library(tmp_path, write_page):
    """Build a small, well-formed library and return (root, expectations).

    Layout::

        library/
        ├── Alpha/
        │   ├── cover.png
        │   ├── 01 - The Journey/  (2 pages + its own cover.jpg)
        │   └── 02/                (1 page, no chapter cover)
        └── Beta/
            └── 01-intro/          (3 pages, no explicit cover)
    """
    root = tmp_path / "library"

    write_page(root / "Alpha" / "cover.png")
    write_page(root / "Alpha" / "01 - The Journey" / "001.jpg")
    write_page(root / "Alpha" / "01 - The Journey" / "002.jpg")
    # A chapter-level cover: not a page, and the thing that chapter's row shows.
    # Only one of Alpha's two chapters has one, so the fallback is covered too.
    write_page(root / "Alpha" / "01 - The Journey" / "cover.jpg")
    write_page(root / "Alpha" / "02" / "001.jpg")

    write_page(root / "Beta" / "01-intro" / "1.jpg")
    write_page(root / "Beta" / "01-intro" / "2.jpg")
    write_page(root / "Beta" / "01-intro" / "10.jpg")

    return root
