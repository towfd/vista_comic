// How a card's place in the schedule is drawn (DESIGN 7.10): the chip's colour
// for each state, and whether its due date is already behind it. The words
// themselves come from practice/library.ts; this only decides the look.

import type { CardState, LearningCard } from '../api/types'

const chipColours: Record<CardState, string> = {
  new: 'bg-st-new-tint text-st-new',
  learning: 'bg-st-learn-tint text-st-learn',
  relearning: 'bg-st-relearn-tint text-st-relearn',
  review: 'bg-st-review-tint text-st-review',
}

/** The state chip: one shape, coloured by what the scheduler holds the card as. */
export function stateChipClass(state: CardState): string {
  return `inline-flex h-6.5 shrink-0 items-center rounded-full px-2.5 text-caption ${chipColours[state]}`
}

/**
 * Whether the card is waiting to be answered now -- the moment `scheduleDue`
 * says 已到期, which is drawn in the relearning red. A new card has no due date.
 */
export function isOverdue(card: LearningCard, now: Date): boolean {
  if (card.state === 'new') return false
  return new Date(card.dueAt).getTime() - now.getTime() <= 0
}
