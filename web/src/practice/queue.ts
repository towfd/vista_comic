// What to ask next, and when there is nothing left to ask. Free of the DOM and
// of Vue; see "The queue" in .scratch/web-review/spec.md.
//
// Nothing here reads the clock. `now` and `today` are passed in so a tab left
// open overnight is right at its next question, and a test can stand at 20:07.

import type { LearningCard, StudySettings } from '../api/types'

/**
 * How far ahead a learning card may be pulled forward when nothing else is
 * due, so a session does not stall on a five-minute timer.
 */
export const LEARN_AHEAD_MS = 20 * 60 * 1000

/**
 * Why the queue had nothing to offer. They send the reader to different
 * places: collect some cards, or come back tomorrow.
 */
export type QueueEmpty = 'deckIsEmpty' | 'dayIsDone'

export type NextCard = { card: LearningCard; empty?: undefined } | { card?: undefined; empty: QueueEmpty }

/** What is waiting, taken apart for the overview. The three add up to `remainingCards`. */
export interface Waiting {
  /** Review cards due now. */
  due: number
  /** New cards, capped by what is left of the day's allowance. */
  fresh: number
  /** Learning and relearning cards due now or inside the learn-ahead window. */
  learning: number
}

/**
 * The reader's local calendar day, `yyyy-MM-dd`.
 *
 * Deliberately not `toISOString()`: on UTC+8 the UTC day lags until eight in
 * the morning, and the phone counts the new-card allowance by local day. The
 * two devices share that allowance only by producing the same string.
 */
export function localDay(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

const at = (iso: string) => new Date(iso).getTime()

const isInLearning = (card: LearningCard) => card.state === 'learning' || card.state === 'relearning'

const byDue = (a: LearningCard, b: LearningCard) => at(a.dueAt) - at(b.dueAt)

/** How many cards were met for the first time on `day`. */
export function introducedCount(deck: readonly LearningCard[], day: string): number {
  return deck.filter((card) => card.introducedOn === day).length
}

function allowanceLeft(deck: readonly LearningCard[], settings: StudySettings, today: string): number {
  return Math.max(settings.newCardsPerDay - introducedCount(deck, today), 0)
}

/**
 * The card to ask next: learning cards due now, then other cards due now,
 * then new cards in the order they were collected while the day's allowance
 * has room, then a learning card coming due inside the learn-ahead window.
 * Longest-waiting first within a group; `avoiding` is skipped whenever the
 * group holds another card.
 */
export function nextCard(
  deck: readonly LearningCard[],
  settings: StudySettings,
  now: Date,
  today: string,
  avoiding?: number,
): NextCard {
  if (deck.length === 0) return { empty: 'deckIsEmpty' }

  const pick = (candidates: LearningCard[]) => candidates.find((card) => card.id !== avoiding) ?? candidates[0]

  const dueNow = deck.filter((card) => card.state !== 'new' && at(card.dueAt) <= now.getTime()).sort(byDue)
  const chosen =
    pick(dueNow.filter(isInLearning)) ??
    pick(dueNow.filter((card) => !isInLearning(card))) ??
    (allowanceLeft(deck, settings, today) > 0
      ? pick(deck.filter((card) => card.state === 'new').sort((a, b) => at(a.createdAt) - at(b.createdAt)))
      : undefined) ??
    pick(deck.filter((card) => isInLearning(card) && at(card.dueAt) <= now.getTime() + LEARN_AHEAD_MS).sort(byDue))

  return chosen ? { card: chosen } : { empty: 'dayIsDone' }
}

/** What is waiting right now, by kind. Zero in every field exactly when `nextCard` has nothing to offer. */
export function waiting(deck: readonly LearningCard[], settings: StudySettings, now: Date, today: string): Waiting {
  const met = deck.filter((card) => card.state !== 'new')
  // Up to the window's end rather than up to now, so a learning card already
  // due and one coming due are counted by the same line and neither twice.
  const learning = met.filter((card) => isInLearning(card) && at(card.dueAt) <= now.getTime() + LEARN_AHEAD_MS).length
  const due = met.filter((card) => !isInLearning(card) && at(card.dueAt) <= now.getTime()).length
  // Capped by the deck as well as by the allowance: room for twenty new cards
  // and three left uncollected is three.
  const fresh = Math.min(allowanceLeft(deck, settings, today), deck.length - met.length)
  return { due, fresh, learning }
}

/** How many cards the session still has to ask. */
export function remainingCards(deck: readonly LearningCard[], settings: StudySettings, now: Date, today: string): number {
  const { due, fresh, learning } = waiting(deck, settings, now, today)
  return due + fresh + learning
}
