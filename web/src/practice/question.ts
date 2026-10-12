// What a card is asked, as data. Free of the DOM and of Vue.

import type { LearningCard, QuestionType } from '../api/types'
import { makeCloze, type Cloze } from './cloze'

/** How a card is to be asked. */
export interface Asking {
  type: QuestionType
  /** Present exactly when `type` is `cloze_typed`. */
  cloze: Cloze | null
}

/**
 * Draws how to ask `card`, uniformly from what it supports.
 *
 * Every card supports translation -- which is how a word card, appearing in no
 * sentence, is asked at all. A sentence holding one of the reader's own words
 * supports a cloze as well. `random` returns a number in [0, 1), and is passed
 * in so a test can say which way the draw goes.
 */
export function drawAsking(card: LearningCard, deck: readonly LearningCard[], random: () => number): Asking {
  const cloze = makeCloze(card, deck)
  if (cloze && random() < 0.5) return { type: 'cloze_typed', cloze }
  return { type: 'sentence_typed', cloze: null }
}
