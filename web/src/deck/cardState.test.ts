import { describe, expect, it } from 'vitest'
import type { CardState, LearningCard } from '../api/types'
import { scheduleDue } from '../practice/library'
import { isOverdue, stateChipClass } from './cardState'

const NOW = new Date('2026-08-31T12:00:00Z')
const inMinutes = (n: number) => new Date(NOW.getTime() + n * 60_000).toISOString()

function card(state: CardState, dueAt: string): LearningCard {
  return {
    id: 1,
    sourceText: 'a',
    translation: 'b',
    kind: 'word',
    note: null,
    state,
    ladderStage: 0,
    learningStep: state === 'learning' || state === 'relearning' ? 0 : null,
    previousStage: null,
    introducedOn: '2026-08-01',
    dueAt,
    createdAt: inMinutes(-1),
  }
}

describe('stateChipClass', () => {
  it.each([
    ['new', 'bg-st-new-tint text-st-new'],
    ['learning', 'bg-st-learn-tint text-st-learn'],
    ['relearning', 'bg-st-relearn-tint text-st-relearn'],
    ['review', 'bg-st-review-tint text-st-review'],
  ] as const)('colours a %s card with its own tint and text', (state, colours) => {
    const classes = stateChipClass(state)
    expect(classes).toContain(colours)
    expect(classes).toContain('rounded-full')
  })

  it('gives every state the same shape', () => {
    const shape = (state: CardState) => stateChipClass(state).split(' ').filter((c) => !c.includes('st-'))
    expect(shape('learning')).toEqual(shape('new'))
    expect(shape('relearning')).toEqual(shape('new'))
    expect(shape('review')).toEqual(shape('new'))
  })
})

describe('isOverdue', () => {
  it('is never true of a new card, whatever its stored due date', () => {
    expect(isOverdue(card('new', inMinutes(-600)), NOW)).toBe(false)
  })

  it('is true once the due date has come, and at the very moment', () => {
    expect(isOverdue(card('review', inMinutes(-1)), NOW)).toBe(true)
    expect(isOverdue(card('learning', inMinutes(0)), NOW)).toBe(true)
  })

  it('is false while the card still waits', () => {
    expect(isOverdue(card('relearning', inMinutes(1)), NOW)).toBe(false)
  })

  it('agrees with the words the deck shows', () => {
    for (const minutes of [-60, -1, 0, 1, 60]) {
      for (const state of ['learning', 'relearning', 'review'] as const) {
        const held = card(state, inMinutes(minutes))
        expect(isOverdue(held, NOW)).toBe(scheduleDue(held, NOW) === '已到期')
      }
    }
  })
})
