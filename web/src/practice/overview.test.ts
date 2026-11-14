import { describe, expect, it } from 'vitest'
import type { CardState, LearningCard } from '../api/types'
import { bubbleLayout, bubblesHeight, bubblesLabel, distributionLabel, dueTomorrow, stageDistribution } from './overview'

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
  }
}

// Local times, so the tests mean the same thing in any time zone.
const local = (day: number, hour: number, minute = 0) => new Date(2026, 7, day, hour, minute)
const NOW = local(31, 20, 7)

describe('dueTomorrow', () => {
  it('counts cards due on the next local date, at any hour of it', () => {
    const deck = [card('review', local(32, 0, 0)), card('review', local(32, 23, 59)), card('learning', local(32, 9))]
    expect(dueTomorrow(deck, NOW)).toBe(3)
  })

  it('leaves out cards due today, overdue, or the day after', () => {
    const deck = [card('review', local(31, 23, 59)), card('review', local(20, 9)), card('review', local(33, 0, 0))]
    expect(dueTomorrow(deck, NOW)).toBe(0)
  })

  it('leaves out new cards, whose due date means nothing', () => {
    expect(dueTomorrow([card('new', local(32, 9))], NOW)).toBe(0)
  })

  it('rolls over a month end', () => {
    // 31 August, so tomorrow is 1 September.
    expect(dueTomorrow([card('relearning', new Date(2026, 8, 1, 12))], NOW)).toBe(1)
  })

  it('is zero for an empty deck', () => {
    expect(dueTomorrow([], NOW)).toBe(0)
  })
})

describe('stageDistribution', () => {
  it('counts every stage in legend order, zeros included', () => {
    const deck = [card('new', NOW), card('new', NOW), card('review', NOW), card('relearning', NOW)]
    expect(stageDistribution(deck).map(({ label, count }) => [label, count])).toEqual([
      ['新卡', 2],
      ['學習中', 0],
      ['重新學習', 1],
      ['間隔複習', 1],
    ])
  })

  it('reads out in full for the bar', () => {
    const deck = [card('new', NOW), card('learning', NOW)]
    expect(distributionLabel(stageDistribution(deck))).toBe('新卡 1 張、學習中 1 張、重新學習 0 張、間隔複習 0 張')
  })
})

describe('bubbleLayout', () => {
  it('sizes by area, largest first, in the three-bubble slots', () => {
    const bubbles = bubbleLayout({ due: 12, fresh: 5, learning: 3 })
    expect(bubbles.map((b) => [b.key, b.diameter, b.numberSize, b.left, b.top])).toEqual([
      ['due', 136, 'text-display', -124, 20],
      ['fresh', 88, 'text-headline', 18, 4],
      ['learning', 68, 'text-heading', 48, 102],
    ])
  })

  it('orders by count, not by kind', () => {
    expect(bubbleLayout({ due: 1, fresh: 2, learning: 9 }).map((b) => b.key)).toEqual(['learning', 'fresh', 'due'])
  })

  it('keeps ties in 到期, 新卡, 學習中 order', () => {
    expect(bubbleLayout({ due: 4, fresh: 4, learning: 4 }).map((b) => b.key)).toEqual(['due', 'fresh', 'learning'])
  })

  it('stops a tiny count at the smallest size that holds its number', () => {
    const [, small] = bubbleLayout({ due: 80, fresh: 0, learning: 1 })
    expect(small!.diameter).toBe(64)
  })

  it('leaves out empty bubbles and uses the two-bubble slots', () => {
    const bubbles = bubbleLayout({ due: 0, fresh: 5, learning: 5 })
    expect(bubbles.map((b) => [b.key, b.left, b.top])).toEqual([
      ['fresh', -112, 20],
      ['learning', 20, 40],
    ])
  })

  it('centres a lone bubble', () => {
    expect(bubbleLayout({ due: 0, fresh: 3, learning: 0 })).toEqual([
      { key: 'fresh', label: '新卡', count: 3, diameter: 136, numberSize: 'text-display', left: -68, top: 21 },
    ])
  })

  it('draws nothing when nothing waits', () => {
    expect(bubbleLayout({ due: 0, fresh: 0, learning: 0 })).toEqual([])
  })
})

describe('bubblesHeight', () => {
  it('is the usual height for the usual proportions', () => {
    expect(bubblesHeight(bubbleLayout({ due: 12, fresh: 5, learning: 3 }))).toBe(178)
  })

  it('grows when equal counts push the lowest bubble down past it', () => {
    expect(bubblesHeight(bubbleLayout({ due: 4, fresh: 4, learning: 4 }))).toBe(102 + 136)
  })
})

describe('bubblesLabel', () => {
  it('says all three counts, zeros included', () => {
    expect(bubblesLabel({ due: 12, fresh: 0, learning: 3 })).toBe('到期 12 張、新卡 0 張、學習中 3 張')
  })
})
