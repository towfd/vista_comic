Status: deferred — owner is web-only for now; pick up before the iOS app is used again (2026-11-03)
Blocked by: —

# 01 — iOS accepts decimal chapter numbers

**What to build:** The iOS app decodes, stores, sorts and displays a chapter `number` that may be a decimal (`1.5`), while behaving exactly as today for whole numbers. This must land first: the moment the backend (ticket 02) sends `1.5`, today's app fails to decode the whole comic detail for 13 of 15 comics.

**Files (boundary):**
- `vista_comic/vista_comic/Shared/Models.swift` — `Chapter.number: Int` → `Double`, decoder too; a single display helper for the number (`1.5` → "1.5", `8` → "8")
- `vista_comic/vista_comic/Shared/SampleData.swift` — pass `Double(number)`
- `vista_comic/vista_comic/Networking/OfflineChapterStore.swift` — `DownloadedChapter.chapterNumber: Int` → `Double`
- `vista_comic/vista_comic/Features/ChapterPage/components/ChapterListView.swift` — `#\(…)` uses the display helper
- `vista_comic/vista_comic/Features/Downloads/components/DownloadedChapterRow.swift` — same
- Tests under `vista_comic/vista_comicTests/` as needed

**Acceptance criteria:**
- [ ] A chapter JSON with `"number": 1.5` decodes; `"number": 8` still decodes
- [ ] A `DownloadedChapter` persisted by the current build (integer `chapterNumber`) still decodes
- [ ] Display: `8` → "8", `1.5` → "1.5", `37.8` → "37.8"
- [ ] Downloaded chapters sort 1 < 1.5 < 2
- [ ] Unit tests cover the above; full unit run passes within the CLAUDE.md budget

**Device checklist (owner):** chapter list and 已下載 still show `#1`, `#2`… for an ordinary comic; previously downloaded chapters still open offline.

## Comments

2026-11-03, owner: iOS is not in use; ship the backend alone and do this ticket when iOS is picked up again. Until then, comic detail for comics with decimal chapters will fail to decode on the current iOS build.
