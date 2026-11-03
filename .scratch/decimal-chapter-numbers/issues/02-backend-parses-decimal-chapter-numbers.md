Status: done — owner confirmed on the deployed web reader (2026-11-04)
Blocked by: — (was 01; owner waived the iOS-first order on 2026-11-03, web-only for now)

# 02 — Backend parses decimal chapter numbers

**What to build:** The scanner reads `01.5` as chapter `1.5` (title `Chapter 1.5`), whole numbers stay integers on the wire, and the web reader therefore loads `1.5.ocr.json` / `1.5.zh-TW.json` — fixing the reported 殺手彼得 bug with no web change.

**Files (boundary):**
- `backend/app/scanner.py` — `_CHAPTER_RE` and `_parse_chapter_name` keep a decimal part; int when whole
- `backend/app/models.py` — `number` fields on `ChapterEntry`, `ChapterSummary`, chapter detail: `int` → `int | float` (whole stays int)
- `backend/tests/test_scanner.py`, `backend/tests/test_endpoints.py`

**Acceptance criteria:**
- [x] `01.5` → number 1.5, title `Chapter 1.5`; `07.2` → 7.2; `08` → 8 (JSON `8`, not `8.0`)
- [x] `01.5 Title` → 1.5 / "Title"; `12.Title` → 12 / "Title" (unchanged)
- [x] Order: `01`, `01.5`, `02`, `07.1`, `07.2`, `08`
- [x] Chapter ids unchanged for every folder
- [x] Full backend test suite passes

**Owner check after deploy:** 殺手彼得 1.5 and 7.1 show their own translations on the web reader, and the chapter list reads 第 1.5 話 without a stray "5" title.

## Comments

2026-11-03: implemented. 390 backend tests pass (3 new: scanner decimal parsing, decimal + title, wire format incl. `"number":1,` not `1.0` and ids unchanged). Scanning the real library with the new parser: every comic still sorts in number order, sat_thu_peter reads `1, 1.5, 2, 3, 4, 5, 6, 7.1, 7.2, 8, 8.1, 8.2…`; no new skipped chapters (the 3 skipped are pre-existing empty sket_dance folders).
