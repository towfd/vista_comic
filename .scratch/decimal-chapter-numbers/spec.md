Status: ready-for-agent

# Decimal chapter numbers: `01.5` is chapter 1.5, not chapter 1

## Problem Statement

Reported by the repo owner, 2026-11-03: in 殺手彼得 (`sat_thu_peter`) the first chapter is split into two folders, `01` and `01.5`, and on the web reader **both show chapter 1's translations**.

Cause: the scanner parses a chapter folder name with `^(\d+)[-–_.](.*)`, so `01.5` becomes **number 1, title "5"**, and `number` is an `int` end to end. The web reader builds the comic-ocr-data file name from that number (`web/src/reader/overlay.ts`), so `01.5` loads `1.ocr.json` / `1.zh-TW.json`. OCR regions key pages by file name (`001.jpg`…), which both folders share, so chapter 1's boxes land on chapter 1.5's pages at the wrong positions.

Scope of the damage, measured against the library on 2026-11-03: 13 of 15 comics have decimal folders (`sat_thu_peter` alone has 48 of 201). Where no whole-number sibling has OCR data (`07.1`, `07.2` → `7.ocr.json`, which does not exist) the chapter shows no translations at all. The comic-ocr-data itself is correct — `1.5.ocr.json`, `7.1.zh-TW.json` etc. all exist.

Secondary symptom: the parsed title "5" is shown under 第 1 話 on the web chapter list.

## Solution

A chapter's `number` is the folder's numeric prefix **including a decimal part**: `01.5` → `1.5`, `07.2` → `7.2`, `08` → `8`.

- Whole numbers stay **integers on the wire** (`8`, never `8.0`), so every existing response is byte-identical for whole-numbered chapters.
- Default title follows the number: `Chapter 1.5`.
- Ordering is unchanged in rule: by number, then natural folder name.
- Chapter **ids** are untouched (they hash the folder path), so reading progress, learning cards, comprehension records and downloads are unaffected.

The web client needs no code change: `number` is already a JS `number`, `第 1.5 話` renders as is, and the overlay URL becomes `1.5.ocr.json`.

The iOS client decodes `number` as `Int` and **fails the whole comic-detail decode** on `1.5`. So iOS must accept decimals first, and the backend change ships only after that build is on the owner's device.

## Decisions

| Question | Decision |
|---|---|
| Wire type | Integer when whole, decimal otherwise (`int \| float`) |
| `01.5 Title` / `01.5-Title` | Number 1.5, title the remainder |
| `12.Title` (dot then non-digits) | Unchanged: number 12, title "Title" |
| Leading zeros in the decimal part / `37.10` | Parsed as a decimal (37.1); none exist in the library today, ties fall back to natural name ordering. Not handled further. |
| iOS type | `Double`, displayed without a trailing `.0` |
| Persisted iOS downloads | `chapterNumber` becomes `Double`; existing records stored as JSON integers decode unchanged — no migration |
| Rollout order | ~~iOS first~~ — owner waived on 2026-11-03: backend (02) ships alone; iOS (01) deferred until the app is used again, and the current iOS build breaks on decimal comics until then |

## Out of scope

- Renaming library folders or comic-ocr-data files.
- iOS on-device OCR (does not use comic-ocr-data).
- Any change to how chapter ids are derived.
