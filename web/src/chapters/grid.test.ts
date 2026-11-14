import { describe, expect, it } from 'vitest'
import { cellAriaLabel, cellState, chapterLabel, isLongLabel, scrollTargetFor } from './grid'

describe('chapterLabel', () => {
  it('is the number itself, decimals included', () => {
    expect(chapterLabel(54)).toBe('54')
    expect(chapterLabel(1162)).toBe('1162')
    expect(chapterLabel(54.1)).toBe('54.1')
    expect(chapterLabel(1162.5)).toBe('1162.5')
    expect(chapterLabel(0)).toBe('0')
  })
})

describe('isLongLabel', () => {
  it('keeps up to four characters at the regular size', () => {
    expect(isLongLabel('1')).toBe(false)
    expect(isLongLabel('54')).toBe(false)
    expect(isLongLabel('1162')).toBe(false)
    expect(isLongLabel('54.1')).toBe(false)
  })

  it('steps down from five characters', () => {
    expect(isLongLabel('154.5')).toBe(true)
    expect(isLongLabel('1162.5')).toBe(true)
  })
})

describe('cellState', () => {
  it('is current for the continue chapter, whatever its read state', () => {
    expect(cellState({ id: 'a', readState: 'reading' }, 'a')).toBe('current')
    expect(cellState({ id: 'a', readState: 'unread' }, 'a')).toBe('current')
    // Everything read: the continue chapter wraps to the first, still pink.
    expect(cellState({ id: 'a', readState: 'read' }, 'a')).toBe('current')
  })

  it('is read for a finished chapter', () => {
    expect(cellState({ id: 'a', readState: 'read' }, 'b')).toBe('read')
    expect(cellState({ id: 'a', readState: 'read' }, null)).toBe('read')
  })

  it('looks unread when unread, left halfway, or in a state it does not know', () => {
    expect(cellState({ id: 'a', readState: 'unread' }, 'b')).toBe('unread')
    expect(cellState({ id: 'a', readState: 'reading' }, 'b')).toBe('unread')
    expect(cellState({ id: 'a', readState: 'paused' }, 'b')).toBe('unread')
    expect(cellState({ id: 'a', readState: 'reading' }, null)).toBe('unread')
  })
})

describe('cellAriaLabel', () => {
  it('says the state in words', () => {
    expect(cellAriaLabel({ id: 'a', number: 54, readState: 'reading' }, 'a')).toBe('第 54 話，正在看')
    expect(cellAriaLabel({ id: 'a', number: 54, readState: 'read' }, 'b')).toBe('第 54 話，看過')
    expect(cellAriaLabel({ id: 'a', number: 54, readState: 'unread' }, 'b')).toBe('第 54 話')
  })

  it('tells a chapter left halfway from an unread one, though they look alike', () => {
    expect(cellAriaLabel({ id: 'a', number: 54, readState: 'reading' }, 'b')).toBe('第 54 話，看到一半')
  })

  it('keeps decimal numbers', () => {
    expect(cellAriaLabel({ id: 'a', number: 54.1, readState: 'read' }, null)).toBe('第 54.1 話，看過')
  })
})

describe('scrollTargetFor', () => {
  it('puts the cell top 35% down the viewport', () => {
    expect(scrollTargetFor(5000, 800)).toBe(4720)
    expect(scrollTargetFor(1000.4, 1000)).toBe(650)
  })

  it('stays put when the cell is in the first rows', () => {
    expect(scrollTargetFor(200, 800)).toBeNull()
    expect(scrollTargetFor(280, 800)).toBeNull()
  })
})
