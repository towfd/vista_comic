# 01 — Expose the decoded page image alongside the rendered `Image`

**What to build:** `AuthorizedAsyncImage` (and the `ReaderPage` that uses it) makes the decoded source image it already fetches available to callers, not just the SwiftUI `Image` it renders into the Reader today. This is a pure prefactor — no visible or behavioral change to how the Reader loads, scrolls, retries, or resumes. It unblocks pixel-accurate cropping in a later ticket (a crop must come from the original decoded pixels, not a screenshot of the on-screen scaled rendering).

**Blocked by:** None — can start immediately

**Status:** resolved (commit `906497a` on `feat/ocr-recognition-foundation`)

- [x] Reader pages load, scroll, retry-on-failure, and resume exactly as before (no regression)
- [x] The decoded image is available at the point a page is rendered, in a form usable for pixel-level cropping later (e.g. alongside or instead of discarding the `UIImage` currently converted straight to `Image` in `AuthorizedAsyncImage.fetchImage`)
- [x] `AuthorizedAsyncImageTests` (or an equivalent unit test) covers the newly exposed value

## Comments

`ReaderPage` in `ComicView.swift` was deliberately left untouched — the coordinator's implementation dispatch scoped this ticket to `AuthorizedAsyncImage.swift` only (a new `onDecoded: ((UIImage) -> Void)?` callback + `FetchedImage`), and reserved wiring `ReaderPage` to consume it for Ticket 03, which touches that file anyway to add the selection gesture. The parenthetical "(and the `ReaderPage` that uses it)" in this ticket's "What to build" overstated scope relative to its actual acceptance criteria; flagged by `/code-review`'s Spec axis and judged not a defect for that reason.
