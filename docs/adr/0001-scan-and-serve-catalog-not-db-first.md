# Scan-and-serve Catalog, not database-first

Status: accepted (2026-07-22)

The Catalog (Comics → Chapters → Pages) is built by scanning the Library into memory on startup / manual re-scan, and served directly — no database backs it. A database was considered and rejected for v1: it doesn't remove the need to scan (something must still walk the folder to populate it), and the folder is already the source of truth, so a second copy would only need to be kept in sync for no benefit. Persistence was introduced later (see ADR-0002), but only for state the folder cannot hold — reading Progress — never for the Catalog itself.
