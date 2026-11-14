// The library's 繼續看 rules, free of the DOM and of Vue: which comic the card
// is about, and where in it the reader stands.

import type { ComicDetail, ComicSummary } from '../api/types'

/**
 * The comic read most recently: the latest `lastReadAt`. `null` when nothing
 * has been read (no card then). A missing or unparsable time counts as never
 * read; on a tie the one listed first wins, so the card does not flip between
 * equals.
 */
export function mostRecentlyRead(comics: ComicSummary[]): ComicSummary | null {
  let best: ComicSummary | null = null
  let bestTime = -Infinity
  for (const comic of comics) {
    if (!comic.lastReadAt || !comic.continueChapterId) continue
    const time = Date.parse(comic.lastReadAt)
    if (Number.isNaN(time) || time <= bestTime) continue
    best = comic
    bestTime = time
  }
  return best
}

export interface ContinueProgress {
  /** The chapter's own number, as its folder names it (`54`, `54.1`). */
  number: number
  /** 1-based place of the chapter in the comic's list: the `54` of `54 / 149`. */
  position: number
  /** How many chapters the comic has. */
  total: number
}

export interface ContinueTarget {
  /** The chapter the play button opens. */
  chapterId: string
  /** Where that chapter stands; `null` until the comic's detail arrives (or if it lacks the chapter). */
  progress: ContinueProgress | null
}

/**
 * Where 繼續看 leads. `GET /comics` names the chapter but not its number or
 * place, so those come from the comic's detail once it is fetched. The
 * detail is the fresher of the two (it is revalidated on every visit, the
 * list is not), so its `continueChapterId` wins when it has one.
 */
export function continueTarget(summary: ComicSummary, detail: ComicDetail | null): ContinueTarget {
  const chapterId = detail?.continueChapterId || summary.continueChapterId
  const chapters = detail?.chapters ?? []
  const index = chapters.findIndex((chapter) => chapter.id === chapterId)
  const chapter = chapters[index]
  if (!chapter) return { chapterId, progress: null }
  return {
    chapterId,
    progress: { number: chapter.number, position: index + 1, total: chapters.length },
  }
}

/** The bar's fill, 0-100: how far through the comic the continued chapter is. */
export function progressPercent(progress: ContinueProgress): number {
  if (progress.total <= 0) return 0
  return Math.min(100, Math.max(0, (progress.position / progress.total) * 100))
}
