// The reading-progress rules, kept free of the DOM and of Vue so they can be
// unit-tested directly. Each mirrors its iOS counterpart in
// vista_comic/Features/ComicPage/ComicView.swift; see
// .scratch/web-reading-progress/spec.md for why each rule is what it is.

/**
 * The 1-based page the reader positions at when a chapter opens, or `null` to
 * start at the top of the screen (no saved position, or an override).
 *
 * The web twin of iOS `readerStartIndex`: a "start at the top" override wins
 * (the next-chapter button), otherwise the saved page is resumed, clamped to
 * `[1, pageCount]` in case the chapter shrank since it was recorded. A finished
 * chapter (`lastReadPage == pageCount`) therefore opens on its last page.
 */
export function resumeStartPage(options: {
  pageCount: number
  lastReadPage?: number | null
  startAtTop?: boolean
}): number | null {
  const { pageCount, lastReadPage, startAtTop = false } = options
  if (pageCount <= 0) return null
  if (startAtTop) return null
  if (lastReadPage == null || !Number.isFinite(lastReadPage)) return null
  return Math.min(Math.max(Math.trunc(lastReadPage), 1), pageCount)
}

/**
 * The 1-based page to report as the reader's position, or `null` before
 * anything has been seen.
 *
 * The web twin of iOS `reportedProgressPage`: the top-most page with any part
 * visible, except that once the 「本話完」 block is visible the chapter counts
 * as finished and the position is `pageCount`. The visible set comes from
 * IntersectionObserver -- never from scroll offsets, which is what produced
 * the iOS false-trigger defect.
 */
export function currentPage(visiblePages: Iterable<number>, endVisible: boolean, pageCount: number): number | null {
  if (pageCount <= 0) return null
  if (endVisible) return pageCount
  let topMost: number | null = null
  for (const page of visiblePages) {
    if (topMost === null || page < topMost) topMost = page
  }
  return topMost
}

/**
 * Whether the position should be sent now.
 *
 * - The gate stays closed until a real user input after positioning, so
 *   merely opening a chapter (page 1 briefly visible before the resume scroll,
 *   images loading above the viewport) can never overwrite the phone's
 *   position in the one shared store.
 * - The same page as the last one sent is not sent again.
 */
export function shouldWrite(options: { gateOpen: boolean; page: number | null; lastSent: number | null }): boolean {
  const { gateOpen, page, lastSent } = options
  if (!gateOpen) return false
  if (page === null) return false
  return page !== lastSent
}

/** The keys that count as the reader scrolling: ↓, PageDown and Space. */
export function isScrollKey(key: string): boolean {
  return key === 'ArrowDown' || key === 'PageDown' || key === ' ' || key === 'Spacebar'
}
