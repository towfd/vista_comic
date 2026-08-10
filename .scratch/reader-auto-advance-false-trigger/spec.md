# Reader jumps to the last chapter when correcting recognized text

## The report

On iPad: draw a selection mid-chapter, wait for recognition, then tap the text field to correct the result. The reader underneath jumps straight to the **last chapter** of the comic.

Reported and narrowed on device by the repo owner, 2026-08-10:

- In the **last** chapter the same tap still moves the reading position, but cannot change chapter.
- Selecting near the **top** of a chapter is fine.
- Selecting in the **middle** of a chapter jumps to the last chapter.

Those three observations together identify the mechanism precisely; see below.

## Mechanism

`ReaderView`'s pull-past-end auto-advance (`ComicView.swift`) decides purely from numbers:

```swift
let maxScroll = geometry.contentSize.height - geometry.containerSize.height
return geometry.contentOffset.y >= maxScroll + pullThreshold
```

Nothing in that expression distinguishes "the reader dragged past the bottom" from "the content got shorter underneath a stationary reader". Both produce the same Bool.

The content does get shorter, sharply:

- The prefetch window holds only the current Page, five ahead and two behind (`PagePrefetchWindow`). Every other row draws `ProgressView().frame(minHeight: 220)` — 220pt standing in for a real Page of ~1300–1500pt on an iPad.
- Tapping the text field raises the keyboard, which shrinks the reader's container, which makes the `LazyVStack` re-lay out and recycle rows. A recycled row's `AuthorizedAsyncImage` resets `phase` to `nil`; rows outside the window fall back to the 220pt placeholder.

`contentSize` therefore collapses while `contentOffset.y` stays put — and the deeper into the chapter the reader is, the larger that stale offset is. Near the top the offset is too small to clear the collapsed `maxScroll + pullThreshold`; in the middle it clears it easily. That is exactly the top-vs-middle split observed.

The cascade to the *last* chapter rather than merely the next one comes from `goTo`. It sets `currentChapter`, but `pagesState` only becomes `.loading` once the async `loadPages()` runs. In between there is one render pass holding **the new chapter's `.id`, the old chapter's URLs, and a stale `topPage`** — a freshly built scroll view positioned deep into content that is almost entirely 220pt placeholders, which satisfies the same condition again. It repeats until `nextChapter == nil`.

The last chapter still shows the position jump because the collapse is real there too; only the chapter change is blocked.

## Scope

In: making auto-advance require a real scroll gesture, and removing the mixed-state render pass in `goTo`.

Out: reserving correct heights for Pages not in memory, which is what actually stops the content collapsing. That is `.scratch/reader-page-prefetch/issues/03`, closed as "not doing" on 2026-08-09 because the residual shift was judged not very noticeable. This bug is new evidence against that judgement — the collapse is not only cosmetic, it corrupts scroll-geometry inference — so 03 is reopened and carries the remaining position jump. It stays a separate ticket because it is a cache/model change, not a reader change, and this fix must not wait on it.

## Prior art worth not breaking

`ROADMAP.md:190` records auto-advance as device-verified on iPhone. iPhone escapes this because its sheet covers the reader completely and the keyboard never resizes the presenter; iPad's form sheet leaves the reader laid out and reacting.
