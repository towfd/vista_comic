# vista_comic backend

The domain for vista_comic's local "scan-and-serve" manga catalog and reading-progress store — the smallest service that makes a folder of manga on disk appear in the iOS app. See `docs/api-contract.md` for the API/folder-format specification and `docs/adr/` for the architectural decisions behind it.

## Language

**Library**:
The folder on disk that is the source of truth for a user's manga collection. Always read live from disk, never copied or duplicated.
_Avoid_: manga folder (as a proper noun), archive

**Comic**:
A single manga title — one directory directly under the Library root.
_Avoid_: manga, title, series

**Chapter**:
A numbered sub-unit of a Comic — one directory directly under a Comic directory, containing its Pages.
_Avoid_: volume, episode

**Page**:
A single image file within a Chapter, ordered by natural sort of its filename.
_Avoid_: image

**Catalog**:
The in-memory result of scanning the Library into Comics → Chapters → Pages. Rebuilt on startup or manual re-scan; never persisted, since the Library itself remains the source of truth.
_Avoid_: index, database (the Catalog is not a database)

**Scanner**:
The component that walks the Library into the Catalog.

**Progress**:
Folder-external reading state — the last page read in a Chapter — held in the `progress` store because it cannot be reconstructed from the Library. The only state that survives a Library re-scan, by being keyed on a Stable ID rather than a folder path.
_Avoid_: bookmark

**Stable ID**:
A hash derived from an item's path relative to the Library root, used as its Comic or Chapter identifier. Load-bearing: Progress rows are keyed on Stable IDs, so an ID that changed between scans would silently orphan saved Progress.
_Avoid_: UUID, database ID (it is neither randomly generated nor DB-assigned)

**readState**:
A derived per-Chapter value — `unread`, `reading`, or `read` — computed live from Progress rows.

**continueChapterId**:
A derived per-Comic value identifying which Chapter the "Continue" action opens.
