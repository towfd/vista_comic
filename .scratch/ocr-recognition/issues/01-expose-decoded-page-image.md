# 01 — Expose the decoded page image alongside the rendered `Image`

**What to build:** `AuthorizedAsyncImage` (and the `ReaderPage` that uses it) makes the decoded source image it already fetches available to callers, not just the SwiftUI `Image` it renders into the Reader today. This is a pure prefactor — no visible or behavioral change to how the Reader loads, scrolls, retries, or resumes. It unblocks pixel-accurate cropping in a later ticket (a crop must come from the original decoded pixels, not a screenshot of the on-screen scaled rendering).

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] Reader pages load, scroll, retry-on-failure, and resume exactly as before (no regression)
- [ ] The decoded image is available at the point a page is rendered, in a form usable for pixel-level cropping later (e.g. alongside or instead of discarding the `UIImage` currently converted straight to `Image` in `AuthorizedAsyncImage.fetchImage`)
- [ ] `AuthorizedAsyncImageTests` (or an equivalent unit test) covers the newly exposed value
