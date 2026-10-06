import { describe, expect, it } from 'vitest'
import { nextChapter, START_AT_TOP_KEY, takeStartAtTopFlag } from './nextChapter'

const chapters = [
  { id: 'a', number: 1 },
  { id: 'b', number: 2 },
  { id: 'c', number: 3 },
]

describe('nextChapter', () => {
  it('returns the following chapter for one in the middle', () => {
    expect(nextChapter(chapters, 'b')).toEqual({ id: 'c', number: 3 })
    expect(nextChapter(chapters, 'a')).toEqual({ id: 'b', number: 2 })
  })

  it('returns none on the last chapter', () => {
    expect(nextChapter(chapters, 'c')).toBeNull()
  })

  it('returns none for an id not in the list', () => {
    expect(nextChapter(chapters, 'zzz')).toBeNull()
  })

  it('returns none before the list has arrived, or for an empty list', () => {
    expect(nextChapter(undefined, 'a')).toBeNull()
    expect(nextChapter(null, 'a')).toBeNull()
    expect(nextChapter([], 'a')).toBeNull()
  })
})

describe('takeStartAtTopFlag', () => {
  it('reads the flag and returns the rest of the state intact', () => {
    const state = { back: '/comic/x', current: '/comic/x/chapter/b', position: 3, [START_AT_TOP_KEY]: true }
    expect(takeStartAtTopFlag(state)).toEqual({
      startAtTop: true,
      rest: { back: '/comic/x', current: '/comic/x/chapter/b', position: 3 },
    })
  })

  it('reports no flag and nothing to clear when the key is absent (a reload after clearing)', () => {
    expect(takeStartAtTopFlag({ back: null, position: 1 })).toEqual({ startAtTop: false, rest: null })
  })

  it('treats a missing or non-object state as no flag', () => {
    expect(takeStartAtTopFlag(null)).toEqual({ startAtTop: false, rest: null })
    expect(takeStartAtTopFlag(undefined)).toEqual({ startAtTop: false, rest: null })
    expect(takeStartAtTopFlag('x')).toEqual({ startAtTop: false, rest: null })
  })

  it('clears a non-true value without honouring it', () => {
    expect(takeStartAtTopFlag({ [START_AT_TOP_KEY]: 'yes', position: 2 })).toEqual({
      startAtTop: false,
      rest: { position: 2 },
    })
  })
})
