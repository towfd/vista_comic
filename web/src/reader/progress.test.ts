import { describe, expect, it } from 'vitest'
import { currentPage, isScrollKey, resumeStartPage, shouldWrite } from './progress'

describe('resumeStartPage', () => {
  it('starts at the top when there is no saved position', () => {
    expect(resumeStartPage({ pageCount: 30 })).toBeNull()
    expect(resumeStartPage({ pageCount: 30, lastReadPage: null })).toBeNull()
  })

  it('resumes at a saved page within range', () => {
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 12 })).toBe(12)
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 1 })).toBe(1)
  })

  it('clamps a saved page above pageCount to the last page (the chapter shrank)', () => {
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 45 })).toBe(30)
  })

  it('clamps a saved page below 1 to the first page', () => {
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 0 })).toBe(1)
    expect(resumeStartPage({ pageCount: 30, lastReadPage: -3 })).toBe(1)
  })

  it('opens a finished chapter on its last page, as iOS does', () => {
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 30 })).toBe(30)
  })

  it('starts at the top when told to, ignoring the saved page', () => {
    expect(resumeStartPage({ pageCount: 30, lastReadPage: 12, startAtTop: true })).toBeNull()
  })

  it('has nothing to position in an empty chapter', () => {
    expect(resumeStartPage({ pageCount: 0, lastReadPage: 3 })).toBeNull()
  })
})

describe('currentPage', () => {
  it('is the top-most visible page', () => {
    expect(currentPage(new Set([7, 5, 6]), false, 30)).toBe(5)
  })

  it('is pageCount once the end block is visible', () => {
    expect(currentPage(new Set([29, 30]), true, 30)).toBe(30)
    expect(currentPage(new Set(), true, 30)).toBe(30)
  })

  it('is none when nothing is visible', () => {
    expect(currentPage(new Set(), false, 30)).toBeNull()
  })

  it('is none in an empty chapter, even with the end block visible', () => {
    expect(currentPage(new Set(), true, 0)).toBeNull()
  })
})

describe('shouldWrite', () => {
  it('writes nothing while the gate is closed', () => {
    expect(shouldWrite({ gateOpen: false, page: 12, lastSent: null })).toBe(false)
  })

  it('writes nothing for the page last sent', () => {
    expect(shouldWrite({ gateOpen: true, page: 12, lastSent: 12 })).toBe(false)
  })

  it('writes a changed page once the gate is open', () => {
    expect(shouldWrite({ gateOpen: true, page: 13, lastSent: 12 })).toBe(true)
    expect(shouldWrite({ gateOpen: true, page: 1, lastSent: null })).toBe(true)
  })

  it('writes nothing when there is no page', () => {
    expect(shouldWrite({ gateOpen: true, page: null, lastSent: null })).toBe(false)
  })
})

describe('isScrollKey', () => {
  it('accepts ↓, PageDown and Space', () => {
    expect(['ArrowDown', 'PageDown', ' '].every(isScrollKey)).toBe(true)
  })

  it('rejects other keys', () => {
    expect(['ArrowUp', 'Tab', 'a', 'Enter'].some(isScrollKey)).toBe(false)
  })
})
