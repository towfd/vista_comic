// How the deck's coming reviews spread over the days ahead: the tiles on the
// card library and on the practice overview. Free of the DOM and of Vue;
// nothing here reads the clock.

import type { LearningCard } from '../api/types'
import { LEARN_AHEAD_MS } from './queue'

export type DueBucketKey = 'today' | 'd1' | 'd3' | 'd7' | 'd21' | 'later'

export interface DueBucket {
  key: DueBucketKey
  /** The tile's name. 1, 3, 7 and 21 are the owner's own examples. */
  label: string
  /** Which days the name covers, said under it. */
  range: string
  /** Calendar days from today, both ends included. */
  from: number
  to: number
}

/**
 * The tiles in reading order. Each card falls in exactly one: 3 天 is 2–3
 * days away, not "within 3 days" -- the owner chose separate tiles over a
 * running total on 2026-11-22.
 */
export const DUE_BUCKETS: readonly DueBucket[] = [
  { key: 'today', label: '今天', range: '含已到期', from: -Infinity, to: 0 },
  { key: 'd1', label: '1 天', range: '明天', from: 1, to: 1 },
  { key: 'd3', label: '3 天', range: '2–3 天後', from: 2, to: 3 },
  { key: 'd7', label: '7 天', range: '4–7 天後', from: 4, to: 7 },
  { key: 'd21', label: '21 天', range: '8–21 天後', from: 8, to: 21 },
  { key: 'later', label: '更久', range: '22 天以上', from: 22, to: Infinity },
]

const DAY = 24 * 60 * 60 * 1000

export function isDueBucketKey(value: unknown): value is DueBucketKey {
  return DUE_BUCKETS.some((bucket) => bucket.key === value)
}

/**
 * Calendar days from `now`'s local date to `date`'s: 23:00 tonight to 09:00
 * tomorrow is one day, as 明天 means. Negative once the date has passed.
 */
export function daysUntil(date: Date, now: Date): number {
  const from = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const to = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  // Rounded, so a day that is 23 or 25 hours long still counts as one.
  return Math.round((to.getTime() - from.getTime()) / DAY)
}

/** The tile a card is counted under, or `null` for a new card, which has no due date of its own. */
export function dueBucketOf(card: LearningCard, now: Date): DueBucketKey | null {
  if (card.state === 'new') return null
  const days = daysUntil(new Date(card.dueAt), now)
  return DUE_BUCKETS.find((bucket) => days >= bucket.from && days <= bucket.to)!.key
}

export interface DueCount {
  bucket: DueBucket
  count: number
}

/** Every tile with its count, zeros included, in reading order. */
export function dueForecast(deck: readonly LearningCard[], now: Date): DueCount[] {
  const keys = deck.map((card) => dueBucketOf(card, now))
  return DUE_BUCKETS.map((bucket) => ({ bucket, count: keys.filter((key) => key === bucket.key).length }))
}

/** Whether any card has a due date: a deck of only new cards has nothing to spread over the days. */
export function hasDueDates(deck: readonly LearningCard[]): boolean {
  return deck.some((card) => card.state !== 'new')
}

/**
 * Cards that fall due later today but a session would not ask yet: a review
 * card due after `now`, or a learning card due after the learn-ahead window.
 * The complement of what `waiting` counts among today's cards, so the
 * overview can name the ones neither its bubbles nor its tiles show.
 */
export function dueLaterToday(deck: readonly LearningCard[], now: Date): number {
  return deck.filter((card) => {
    if (card.state === 'new') return false
    const due = new Date(card.dueAt)
    if (daysUntil(due, now) > 0) return false
    const window = card.state === 'review' ? 0 : LEARN_AHEAD_MS
    return due.getTime() > now.getTime() + window
  }).length
}
