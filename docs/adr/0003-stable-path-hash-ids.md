# Stable IDs derived from Library-relative path

Status: accepted (2026-07-22)

Comic and Chapter IDs are a hash of the item's path relative to the Library root, not a randomly generated UUID or a database-assigned sequence. This makes IDs stable across re-scans and restarts, which is load-bearing once Progress exists (ADR-0002): Progress rows are keyed on these IDs, so an ID that changed between scans would silently orphan a user's saved reading position with no error. The alternative — DB-assigned IDs — was rejected because it would require the Catalog to touch the database on every scan, contradicting the scan-and-serve design (ADR-0001).
