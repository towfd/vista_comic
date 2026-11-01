// What a card is asked, as data. Free of the DOM and of Vue.

import type { LearningCard, QuestionType } from '../api/types'
import { makeCloze, type Cloze } from './cloze'
import type { QuestionMix } from './questionMix'

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
 *
 * `mix` narrows the draw only where a card offers a choice. A card with no cloze
 * is asked by translation even when the reader wants only clozes: skipped, it
 * would stay due for good and the day could never finish.
 */
export function drawAsking(
  card: LearningCard,
  deck: readonly LearningCard[],
  random: () => number,
  mix: QuestionMix = 'both',
): Asking {
  const cloze = mix === 'sentence' ? null : makeCloze(card, deck)
  if (cloze && (mix === 'cloze' || random() < 0.5)) return { type: 'cloze_typed', cloze }
  return { type: 'sentence_typed', cloze: null }
}
