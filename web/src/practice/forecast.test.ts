import { describe, expect, it } from 'vitest'
import type { CardState, LearningCard } from '../api/types'
import { daysUntil, dueBucketOf, dueForecast, dueLaterToday, hasDueDates, isDueBucketKey } from './forecast'

let nextId = 1
function card(state: CardState, dueAt: Date): LearningCard {
  return {
    id: nextId++,
    sourceText: 'a',
    translation: 'b',
    kind: 'word',
    note: null,
    state,
    ladderStage: 0,
    learningStep: null,
    previousStage: null,
    introducedOn: '2026-08-01',
    dueAt: dueAt.toISOString(),
    createdAt: dueAt.toISOString(),
    hasAudio: false,
  }
}

// Local times, so the tests mean the same thing in any time zone.
const local = (day: number, hour: number, minute = 0) => new Date(2026, 7, day, hour, minute)
const NOW = local(20, 23, 0)
const MINUTE = 60 * 1000

describe('daysUntil', () => {
  it('counts calendar days, not 24-hour spans', () => {
    // Ten hours away, but on tomorrow's date.
    expect(daysUntil(local(21, 9), NOW)).toBe(1)
    expect(daysUntil(local(20, 23, 59), NOW)).toBe(0)
    expect(daysUntil(local(20, 0, 1), NOW)).toBe(0)
  })

  it('is negative once the date has passed', () => {
    expect(daysUntil(local(18, 12), NOW)).toBe(-2)
  })

  it('rolls over a month end', () => {
    expect(daysUntil(new Date(2026, 8, 1, 8), local(31, 22))).toBe(1)
  })
})

describe('dueBucketOf', () => {
  it('puts each day on its edge in the right tile', () => {
    const cases: [number, string][] = [
      [20, 'today'],
      [21, 'd1'],
      [22, 'd3'],
      [23, 'd3'],
      [24, 'd7'],
      [27, 'd7'],
      [28, 'd21'],
      [41, 'd21'],
      [42, 'later'],
    ]
    for (const [day, key] of cases) expect(dueBucketOf(card('review', local(day, 12)), NOW), `day ${day}`).toBe(key)
  })

  it('counts an overdue card under today', () => {
    expect(dueBucketOf(card('review', local(3, 9)), NOW)).toBe('today')
  })

  it('counts a learning card due in minutes under today', () => {
    expect(dueBucketOf(card('learning', new Date(NOW.getTime() + 5 * MINUTE)), NOW)).toBe('today')
  })

  it('leaves a new card out', () => {
    expect(dueBucketOf(card('new', local(25, 9)), NOW)).toBeNull()
  })
})

describe('dueForecast', () => {
  it('counts every tile in reading order, zeros included', () => {
    const deck = [
      card('review', local(19, 9)),
      card('relearning', local(20, 23, 30)),
      card('review', local(21, 8)),
      card('review', local(30, 8)),
      card('review', local(30, 8)),
      card('new', local(21, 8)),
    ]
    expect(dueForecast(deck, NOW).map(({ bucket, count }) => [bucket.label, count])).toEqual([
      ['今天', 2],
      ['1 天', 1],
      ['3 天', 0],
      ['7 天', 0],
      ['21 天', 2],
      ['更久', 0],
    ])
  })

  it('is all zeros for an empty deck', () => {
    expect(dueForecast([], NOW).every(({ count }) => count === 0)).toBe(true)
  })
})

describe('hasDueDates', () => {
  it('is false for a deck of only new cards, or none', () => {
    expect(hasDueDates([card('new', NOW), card('new', NOW)])).toBe(false)
    expect(hasDueDates([])).toBe(false)
  })

  it('is true once any card has left new', () => {
    expect(hasDueDates([card('new', NOW), card('learning', NOW)])).toBe(true)
  })
})

describe('dueLaterToday', () => {
  const morning = local(20, 9)

  it('counts review cards due later today but not yet', () => {
    expect(dueLaterToday([card('review', local(20, 21))], morning)).toBe(1)
  })

  it('leaves out review cards already due, which the session asks now', () => {
    expect(dueLaterToday([card('review', local(20, 8)), card('review', local(15, 8))], morning)).toBe(0)
  })

  it('leaves out learning cards inside the learn-ahead window, and counts those past it', () => {
    const soon = card('learning', new Date(morning.getTime() + 15 * MINUTE))
    const later = card('relearning', new Date(morning.getTime() + 45 * MINUTE))
    expect(dueLaterToday([soon, later], morning)).toBe(1)
  })

  it('leaves out tomorrow and new cards', () => {
    expect(dueLaterToday([card('review', local(21, 0, 30)), card('new', local(20, 21))], morning)).toBe(0)
  })
})

describe('isDueBucketKey', () => {
  it('accepts the six keys and nothing else', () => {
    expect(['today', 'd1', 'd3', 'd7', 'd21', 'later'].every(isDueBucketKey)).toBe(true)
    expect(isDueBucketKey('d2')).toBe(false)
    expect(isDueBucketKey(undefined)).toBe(false)
    expect(isDueBucketKey(['d3'])).toBe(false)
  })
})
