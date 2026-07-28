# PostgreSQL for reading Progress, page-level granularity

Status: accepted (2026-07-23)

Reading Progress (last page read per Chapter) is stored in PostgreSQL rather than SQLite, accessed via SQLAlchemy 2.0 + psycopg (sync) — a single `progress` table, `CREATE TABLE IF NOT EXISTS` at startup, no Alembic. Postgres was chosen over SQLite to match the Docker Compose topology already needed once persistence exists (ADR-0004) and to avoid a later migration if Progress ever needs concurrent writers. Progress is tracked at page-level (not chapter-level), so a resumed Chapter reopens at the exact last-read page rather than the start of the Chapter. The Catalog itself stays scan-derived (ADR-0001) — Postgres holds only the state the Library folder cannot reconstruct.
