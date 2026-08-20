"""The migrations and the models must not drift apart.

Alembic owns the schema now, which moves the risk: not "did someone forget the
manual SQL" any more, but "did someone change a model and forget the migration".
The first test here is the guard for that, and it is the reason this module
exists — it fails on any model change that has no migration behind it, without
anyone having to remember to look.

These run against their own throwaway database rather than the suite's shared
one, because a downgrade test necessarily drops every table and the shared
database is session-scoped.
"""

from __future__ import annotations

import pytest
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect
from sqlalchemy.engine import make_url

from app import db

# `tests/` is not a package, so pytest's rootdir-relative import puts this
# module's own directory on `sys.path` — `conftest` is importable by name.
from conftest import _ensure_test_database, _test_database_url


def _url_of(engine) -> str:
    """The engine's URL with its password intact (see the fixture below)."""
    return engine.url.render_as_string(hide_password=False)


@pytest.fixture
def migration_engine():
    """A separate ``*_test`` database this module may migrate up and down."""
    # `str(URL)` masks the password as `***`, which would reach Postgres as a
    # wrong one; `render_as_string` is the only way back to a usable string.
    url = (
        make_url(_test_database_url())
        .set(database="vista_migration_test")
        .render_as_string(hide_password=False)
    )
    _ensure_test_database(url)

    engine = create_engine(url, future=True)
    # Same data-loss guard the shared fixture carries: this module drops tables.
    assert (make_url(str(engine.url)).database or "").endswith("_test")

    with engine.begin() as conn:
        conn.exec_driver_sql("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")

    try:
        yield engine
    finally:
        engine.dispose()


def test_the_migrated_schema_matches_the_models(migration_engine):
    """Upgrading an empty database produces exactly what the models describe.

    Asserted by asking Alembic what it *would* autogenerate next: nothing. Any
    model changed without a migration shows up here as a pending operation, so
    this fails for the next person who forgets rather than for the deployment
    that discovers it.
    """
    db.upgrade_schema(_url_of(migration_engine))

    with migration_engine.connect() as connection:
        context = MigrationContext.configure(connection)
        pending = compare_metadata(context, db.Base.metadata)

    assert pending == [], f"models and migrations disagree: {pending}"


def test_migrating_creates_every_table_the_app_uses(migration_engine):
    db.upgrade_schema(_url_of(migration_engine))

    tables = set(inspect(migration_engine).get_table_names())

    assert {
        "progress",
        "comprehension_record",
        "comprehend_usage",
        "learning_card",
        "card_review",
    } <= tables
    # Alembic's own bookkeeping, which is what makes a stamped database
    # distinguishable from an unmanaged one.
    assert "alembic_version" in tables


def test_the_migrations_are_reversible(migration_engine):
    """The migrations are not a one-way door.

    Not because rolling back production is the plan — there is one environment
    and no runbook for that (see the spec's Out of Scope) — but because a
    downgrade that was never run is a downgrade that does not work, and finding
    that out later costs more than asserting it now.
    """
    from alembic import command
    from alembic.config import Config
    from pathlib import Path

    config = Config(str(Path(db.__file__).resolve().parent.parent / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", _url_of(migration_engine))

    command.upgrade(config, "head")
    command.downgrade(config, "base")

    tables = set(inspect(migration_engine).get_table_names())

    assert "progress" not in tables
    assert "comprehension_record" not in tables
    assert "comprehend_usage" not in tables
    assert "learning_card" not in tables
    assert "card_review" not in tables


# --- what the app does when migrating fails ---------------------------------
#
# Two failures, deliberately handled differently (see the spec). These run the
# real `lifespan` through `TestClient`'s context manager, which is the only way
# to exercise startup rather than the routes.


def test_an_unreachable_database_still_serves_the_catalog(sample_library, monkeypatch):
    """An outage must not take browsing down.

    The catalog is scanned from disk and never needed Postgres, so a database
    that cannot be reached is logged and serving continues — progress and
    history degrade, the library does not.
    """
    from fastapi.testclient import TestClient

    from app import config, db, main

    # A port nothing listens on: reaching it fails as an OperationalError, the
    # same shape a real outage produces.
    nowhere = "postgresql+psycopg://vista:vista@localhost:5599/nowhere"

    # Patched in three places, all of them load-bearing:
    #
    # - `db.get_database_url` and `main.get_library_root` because both modules
    #   bound those names at import time, so patching `app.config` alone leaves
    #   the originals in play.
    # - `config.get_database_url` because `alembic/env.py` imports it when
    #   Alembic execs that file, which is *after* this patch takes effect — and
    #   missing it points the migration at the developer's real database, which
    #   `conftest`'s `_test`-suffix guard cannot see and therefore cannot stop.
    monkeypatch.setattr(db, "get_database_url", lambda: nowhere)
    monkeypatch.setattr(config, "get_database_url", lambda: nowhere)
    monkeypatch.setattr(main, "get_library_root", lambda: sample_library)

    with TestClient(main.app) as client:
        resp = client.get("/comics")

    assert resp.status_code == 200
    assert [c["title"] for c in resp.json()] == ["Alpha", "Beta"]


def test_a_broken_migration_stops_the_app_starting(sample_library, monkeypatch):
    """A schema the code cannot vouch for is not something to serve through.

    Anything other than an unreachable database means the migration itself
    would not apply, so it propagates out of `lifespan` and the container fails
    to start — where degrading would only move the error somewhere further from
    its cause.
    """
    from fastapi.testclient import TestClient

    from app import db, main

    class MigrationBroken(RuntimeError):
        pass

    def _explode(*args, **kwargs):
        raise MigrationBroken("revision will not apply")

    monkeypatch.setattr(main, "get_library_root", lambda: sample_library)
    monkeypatch.setattr(db, "upgrade_schema", _explode)
    monkeypatch.setattr(main, "upgrade_schema", _explode)

    with pytest.raises(MigrationBroken):
        with TestClient(main.app):
            pass
