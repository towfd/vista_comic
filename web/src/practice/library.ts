// The card library's rules, free of the DOM and of Vue: which cards a search
// keeps, how they are grouped, and what a card says about where it stands.

import type { LearningCard } from '../api/types'
import { normalizedKey } from './text'

/** The interval, in days, of each rung a review card can stand on. The backend's table. */
export const LADDER_INTERVALS = [1, 3, 7, 21, 60, 150, 365]

export type CardGroupKey = 'word' | 'sentence' | 'unsorted'

export interface CardGroup {
  key: CardGroupKey
  cards: LearningCard[]
}

/**
 * Whether a card's text or its meaning contains what was typed, ignoring case
 * and spacing -- so `khong biet` typed with or without its space finds the
 * same cards, while tones still tell words apart. An empty search keeps all.
 */
export function matchesSearch(card: LearningCard, search: string): boolean {
  const wanted = normalizedKey(search)
  if (wanted === '') return true
  return normalizedKey(card.sourceText).includes(wanted) || normalizedKey(card.translation).includes(wanted)
}

/**
 * The cards a search keeps, as words then sentences, each in the order the
 * deck came in (newest first). Cards with no kind follow under their own
 * heading, which is left out when there are none: most decks have none, and
 * an empty heading would only raise the question.
 */
export function groupCards(deck: readonly LearningCard[], search = ''): CardGroup[] {
  const kept = deck.filter((card) => matchesSearch(card, search))
  const groups: CardGroup[] = [
    { key: 'word', cards: kept.filter((card) => card.kind === 'word') },
    { key: 'sentence', cards: kept.filter((card) => card.kind === 'sentence') },
  ]
  const unsorted = kept.filter((card) => card.kind === null)
  if (unsorted.length > 0) groups.push({ key: 'unsorted', cards: unsorted })
  return groups
}

/**
 * Where a card stands, in what the scheduler actually knows: new, which
 * learning step it is on, or the interval it is being tested against.
 */
export function scheduleState(card: LearningCard, learningSteps: readonly number[]): string {
  if (card.state === 'new') return '新卡'
  if (card.state === 'review') {
    const rung = Math.min(Math.max(card.ladderStage, 0), LADDER_INTERVALS.length - 1)
    return `間隔 ${LADDER_INTERVALS[rung]} 天`
  }
  const total = Math.max(learningSteps.length, 1)
  const step = Math.min((card.learningStep ?? 0) + 1, total)
  return `${card.state === 'learning' ? '學習中' : '重新學習'} ${step}/${total}`
}

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/** When a card is next due, relative to `now`. A new card has no due date worth showing. */
export function scheduleDue(card: LearningCard, now: Date): string | null {
  if (card.state === 'new') return null
  const wait = new Date(card.dueAt).getTime() - now.getTime()
  if (wait <= 0) return '已到期'
  if (wait < HOUR) return `${Math.max(Math.round(wait / MINUTE), 1)} 分鐘後`
  if (wait < DAY) return `${Math.round(wait / HOUR)} 小時後`
  return `${Math.round(wait / DAY)} 天後`
}

/** State and due date on one line. */
export function scheduleSummary(card: LearningCard, learningSteps: readonly number[], now: Date): string {
  const due = scheduleDue(card, now)
  const state = scheduleState(card, learningSteps)
  return due ? `${state} · ${due}` : state
}
