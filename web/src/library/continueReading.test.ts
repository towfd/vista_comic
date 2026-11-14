import { describe, expect, it } from 'vitest'
import type { ChapterSummary, ComicDetail, ComicSummary } from '../api/types'
import { continueTarget, mostRecentlyRead, progressPercent } from './continueReading'

function comic(id: string, lastReadAt: string | null | undefined, continueChapterId = `${id}-1`): ComicSummary {
  return { id, title: id, displayTitle: null, coverUrl: '', chapterCount: 3, lastReadAt, continueChapterId }
}

function chapter(id: string, number: number): ChapterSummary {
  return { id, number, title: '', pageCount: 10, coverUrl: '', readState: 'unread' }
}

function detail(continueChapterId: string | undefined, chapters: ChapterSummary[]): ComicDetail {
  return { id: 'a', title: 'a', displayTitle: null, coverUrl: '', continueChapterId, chapters }
}

describe('mostRecentlyRead', () => {
  it('picks the latest lastReadAt, whatever the list order', () => {
    const comics = [
      comic('a', '2026-11-10T08:00:00Z'),
      comic('b', '2026-11-12T08:00:00Z'),
      comic('c', '2026-11-11T08:00:00Z'),
    ]
    expect(mostRecentlyRead(comics)?.id).toBe('b')
  })

  it('compares instants, not strings, across time zones', () => {
    const comics = [comic('a', '2026-11-12T09:00:00+08:00'), comic('b', '2026-11-12T02:00:00Z')]
    expect(mostRecentlyRead(comics)?.id).toBe('b')
  })

  it('is null when nothing has been read', () => {
    expect(mostRecentlyRead([comic('a', null), comic('b', undefined)])).toBeNull()
    expect(mostRecentlyRead([])).toBeNull()
  })

  it('skips unparsable times and comics with nothing to continue', () => {
    const comics = [
      comic('a', 'not a date'),
      comic('b', '2026-11-12T08:00:00Z', ''),
      comic('c', '2026-11-01T08:00:00Z'),
    ]
    expect(mostRecentlyRead(comics)?.id).toBe('c')
  })

  it('keeps the first of equal times', () => {
    const comics = [comic('a', '2026-11-12T08:00:00Z'), comic('b', '2026-11-12T08:00:00Z')]
    expect(mostRecentlyRead(comics)?.id).toBe('a')
  })
})

describe('continueTarget', () => {
  const chapters = [chapter('c1', 1), chapter('c2', 2), chapter('c2.5', 2.5), chapter('c3', 3)]

  it('has no numbers until the detail arrives', () => {
    expect(continueTarget(comic('a', '2026-11-12T08:00:00Z', 'c2'), null)).toEqual({ chapterId: 'c2', progress: null })
  })

  it('derives the number, place and total from the detail', () => {
    const target = continueTarget(comic('a', '2026-11-12T08:00:00Z', 'c2.5'), detail('c2.5', chapters))
    expect(target).toEqual({ chapterId: 'c2.5', progress: { number: 2.5, position: 3, total: 4 } })
  })

  it("prefers the detail's continue chapter, which is fresher than the list's", () => {
    const target = continueTarget(comic('a', '2026-11-12T08:00:00Z', 'c1'), detail('c3', chapters))
    expect(target).toEqual({ chapterId: 'c3', progress: { number: 3, position: 4, total: 4 } })
  })

  it("falls back to the list's chapter when the detail omits the field", () => {
    const target = continueTarget(comic('a', '2026-11-12T08:00:00Z', 'c2'), detail(undefined, chapters))
    expect(target).toEqual({ chapterId: 'c2', progress: { number: 2, position: 2, total: 4 } })
  })

  it('keeps the link but drops the numbers when the chapter is not in the detail', () => {
    const target = continueTarget(comic('a', '2026-11-12T08:00:00Z', 'gone'), detail(undefined, chapters))
    expect(target).toEqual({ chapterId: 'gone', progress: null })
  })
})

describe('progressPercent', () => {
  it('is the place over the total', () => {
    expect(progressPercent({ number: 54, position: 54, total: 149 })).toBeCloseTo(36.24, 2)
    expect(progressPercent({ number: 3, position: 4, total: 4 })).toBe(100)
  })

  it('is 0 for an empty comic', () => {
    expect(progressPercent({ number: 1, position: 1, total: 0 })).toBe(0)
  })
})
