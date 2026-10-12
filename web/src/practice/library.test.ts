import { describe, expect, it } from 'vitest'
import type { CardState, LearningCard } from '../api/types'
import { groupCards, matchesSearch, scheduleDue, scheduleState, scheduleSummary } from './library'

const NOW = new Date('2026-08-31T12:00:00Z')
const inMinutes = (n: number) => new Date(NOW.getTime() + n * 60_000).toISOString()

let nextId = 1
function card(sourceText: string, translation: string, extra: Partial<LearningCard> = {}): LearningCard {
  return {
    id: nextId++,
    sourceText,
    translation,
    kind: 'word',
    state: 'review',
    ladderStage: 0,
    learningStep: null,
    previousStage: null,
    introducedOn: '2026-08-01',
    dueAt: inMinutes(0),
    createdAt: inMinutes(-1),
    ...extra,
  }
}
const standing = (state: CardState, extra: Partial<LearningCard> = {}) => card('a', 'b', { state, ...extra })

describe('matchesSearch', () => {
  const held = card('TÔI KHÔNG BIẾT', '我不知道 路')

  it('keeps every card for an empty search', () => {
    expect(matchesSearch(held, '')).toBe(true)
    expect(matchesSearch(held, '   ')).toBe(true)
  })

  it('finds by source text, ignoring case and spacing', () => {
    expect(matchesSearch(held, 'không biết')).toBe(true)
    expect(matchesSearch(held, 'khôngbiết')).toBe(true)
    expect(matchesSearch(held, ' Tôi ')).toBe(true)
  })

  it('finds by translation', () => {
    expect(matchesSearch(held, '不知道')).toBe(true)
    expect(matchesSearch(held, '知道路')).toBe(true)
  })

  it('still tells tones apart', () => {
    expect(matchesSearch(held, 'khong biet')).toBe(false)
  })

  it('does not find what is in neither', () => {
    expect(matchesSearch(held, 'đường')).toBe(false)
  })
})

describe('groupCards', () => {
  const word1 = card('đường', '路')
  const sentence1 = card('Tôi không biết đường', '我不知道路', { kind: 'sentence' })
  const word2 = card('trường', '學校')
  const loose = card('gì', '什麼', { kind: null })

  it('lists words then sentences, each in the order the deck came in', () => {
    const groups = groupCards([word1, sentence1, word2])
    expect(groups.map((group) => group.key)).toEqual(['word', 'sentence'])
    expect(groups[0]!.cards).toEqual([word1, word2])
    expect(groups[1]!.cards).toEqual([sentence1])
  })

  it('adds a heading for cards with no kind only when there are some', () => {
    expect(groupCards([word1, loose]).map((group) => group.key)).toEqual(['word', 'sentence', 'unsorted'])
    expect(groupCards([word1]).map((group) => group.key)).toEqual(['word', 'sentence'])
  })

  it('keeps both headings for an empty deck, with nothing under them', () => {
    expect(groupCards([]).map((group) => group.cards.length)).toEqual([0, 0])
  })

  it('narrows every group by the search, so the counts follow', () => {
    const groups = groupCards([word1, sentence1, word2, loose], 'đường')
    expect(groups.map((group) => group.cards.length)).toEqual([1, 1])
  })

  it('drops the no-kind heading when the search leaves none there', () => {
    expect(groupCards([word1, loose], 'đường').map((group) => group.key)).toEqual(['word', 'sentence'])
  })
})

describe('scheduleState', () => {
  const steps = [5, 7, 10]

  it('says a card never met is new', () => {
    expect(scheduleState(standing('new'), steps)).toBe('新卡')
  })

  it('says which learning step a card is on, counted from one', () => {
    expect(scheduleState(standing('learning', { learningStep: 0 }), steps)).toBe('學習中 1/3')
    expect(scheduleState(standing('learning', { learningStep: 2 }), steps)).toBe('學習中 3/3')
    expect(scheduleState(standing('relearning', { learningStep: 1 }), steps)).toBe('重新學習 2/3')
  })

  it('reads a missing step as the first, and never runs past the last', () => {
    expect(scheduleState(standing('learning'), steps)).toBe('學習中 1/3')
    expect(scheduleState(standing('learning', { learningStep: 9 }), steps)).toBe('學習中 3/3')
    expect(scheduleState(standing('learning', { learningStep: 0 }), [])).toBe('學習中 1/1')
  })

  it('gives a review card the interval it is being tested against', () => {
    expect(scheduleState(standing('review', { ladderStage: 0 }), steps)).toBe('間隔 1 天')
    expect(scheduleState(standing('review', { ladderStage: 3 }), steps)).toBe('間隔 21 天')
    expect(scheduleState(standing('review', { ladderStage: 6 }), steps)).toBe('間隔 365 天')
  })

  it('keeps a rung outside the table inside it', () => {
    expect(scheduleState(standing('review', { ladderStage: 99 }), steps)).toBe('間隔 365 天')
    expect(scheduleState(standing('review', { ladderStage: -1 }), steps)).toBe('間隔 1 天')
  })
})

describe('scheduleDue', () => {
  const due = (minutes: number, state: CardState = 'review') => scheduleDue(standing(state, { dueAt: inMinutes(minutes) }), NOW)

  it('says nothing for a new card', () => {
    expect(due(0, 'new')).toBeNull()
  })

  it('says a card at or past its time is due', () => {
    expect(due(0)).toBe('已到期')
    expect(due(-600)).toBe('已到期')
  })

  it('counts minutes inside the hour, never showing zero', () => {
    expect(due(0.2)).toBe('1 分鐘後')
    expect(due(7)).toBe('7 分鐘後')
    expect(due(59)).toBe('59 分鐘後')
  })

  it('counts hours inside the day, and days beyond it', () => {
    expect(due(60)).toBe('1 小時後')
    expect(due(60 * 5)).toBe('5 小時後')
    expect(due(60 * 24)).toBe('1 天後')
    expect(due(60 * 24 * 21)).toBe('21 天後')
  })
})

describe('scheduleSummary', () => {
  it('joins the state and the due date', () => {
    expect(scheduleSummary(standing('review', { ladderStage: 2, dueAt: inMinutes(60 * 24 * 3) }), [5], NOW)).toBe('間隔 7 天 · 3 天後')
  })

  it('is the state alone for a new card', () => {
    expect(scheduleSummary(standing('new'), [5], NOW)).toBe('新卡')
  })
})
