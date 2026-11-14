// The chapter page's number grid (page-design-spec 2.2, DESIGN 7.7): what each
// cell says, how it looks, and where the page jumps to on arrival. Pure, so
// the rules are tested without a browser.

import type { ChapterSummary } from '../api/types'

/** The three looks a cell can have. The legend names the same three. */
export type CellState = 'current' | 'read' | 'unread'

/** A cell's label: the chapter number itself (`54`, `1162`, `54.1`), no 第／話. */
export function chapterLabel(number: number): string {
  return String(number)
}

/**
 * Whether a label needs the smaller size. Four characters (`1162`, `54.1`)
 * fit at the regular size in a phone cell (about 60px at 375 wide); from five
 * (`1162.5`) the text steps down so the number never spills out of its cell.
 */
export function isLongLabel(label: string): boolean {
  return label.length >= 5
}

/**
 * How a chapter's cell looks. The continue chapter wins over read: when every
 * chapter is read, `continueChapterId` is the first one and it is still pink.
 * A chapter left halfway that is not the continue one looks unread -- there
 * is no fourth look; its aria-label says so instead.
 */
export function cellState(chapter: Pick<ChapterSummary, 'id' | 'readState'>, continueId: string | null): CellState {
  if (chapter.id === continueId) return 'current'
  if (chapter.readState === 'read') return 'read'
  return 'unread'
}

/** 「第 54 話，正在看」「第 54 話，看過」「第 54 話，看到一半」, or plain 「第 54 話」. */
export function cellAriaLabel(
  chapter: Pick<ChapterSummary, 'id' | 'number' | 'readState'>,
  continueId: string | null,
): string {
  const name = `第 ${chapterLabel(chapter.number)} 話`
  const state = cellState(chapter, continueId)
  if (state === 'current') return `${name}，正在看`
  if (state === 'read') return `${name}，看過`
  if (chapter.readState === 'reading') return `${name}，看到一半`
  return name
}

/** Where the current cell's top edge comes to rest: 35% down the screen. */
export const CURRENT_CELL_VIEWPORT_RATIO = 0.35

/**
 * The window scroll offset that puts the current cell's top 35% down the
 * viewport, or `null` when that would be at or above the page top -- the cell
 * is in the first rows, so the page stays put with its header fully shown.
 *
 * @param cellTop the cell's top edge in document coordinates (rect.top + scrollY)
 */
export function scrollTargetFor(cellTop: number, viewportHeight: number): number | null {
  const top = Math.round(cellTop - viewportHeight * CURRENT_CELL_VIEWPORT_RATIO)
  return top > 0 ? top : null
}
