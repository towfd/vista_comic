// Finding the reader's own words inside a sentence, and building a cloze from
// one. Free of the DOM and of Vue; see "Question types" in
// .scratch/web-review/spec.md.
//
// There is no tokeniser here, on purpose: the blank in a cloze is always a
// word the reader collected, so the question is never "what words is this
// sentence made of" -- hard for Vietnamese, where spaces separate syllables --
// but "which of my cards are in here", a search against a list already held.

import type { LearningCard } from '../api/types'
import { normalizedKey } from './text'

/** One place a deck word occurs in a sentence. */
export interface DeckWordMatch {
  card: LearningCard
  /** Offsets into the **original** sentence, so blanking leaves everything else intact. */
  start: number
  end: number
}

/** A sentence with one of the reader's own words taken out. */
export interface Cloze {
  /** The card whose text is the missing word. */
  answer: LearningCard
  /** The sentence up to the blank, and after it, exactly as collected. */
  before: string
  after: string
  /** The word as it was written in the sentence. */
  removed: string
}

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
const LETTER_OR_NUMBER = /^[\p{L}\p{N}]/u

/**
 * `text` in its comparison form, with a map from each unit of that form back
 * to the character it came from.
 *
 * The map is what makes a match usable: comparison happens with whitespace
 * stripped, so a hit at offset i there is not offset i in the sentence the
 * moment the source has a doubled space -- which collected text does.
 *
 * Walked a whole character at a time rather than a code unit, so a letter and
 * its combining marks are never split and a blank never lands inside one.
 */
function withOrigins(text: string) {
  const characters = [...graphemes.segment(text)].map((part) => ({ start: part.index, end: part.index + part.segment.length, text: part.segment }))
  let key = ''
  const origins: number[] = []
  characters.forEach((character, ordinal) => {
    const folded = normalizedKey(character.text)
    key += folded
    for (let unit = 0; unit < folded.length; unit++) origins.push(ordinal)
  })
  return { key, origins, characters }
}

/**
 * Every occurrence of a deck word in `sentence`, in order of appearance.
 *
 * Matching is on the same key that gives a card its identity, so case, width,
 * doubled spaces and line breaks cannot hide a word -- while a changed tone
 * still can, which is right: in Vietnamese those are different words.
 *
 * A hit must sit on a boundary: the characters either side must not be
 * letters or digits. That is what stops a card holding `AN` matching inside
 * `THÂN`. JavaScript's `\b` cannot do this -- it knows only ASCII letters, and
 * would find `ÀO` inside `CHÀO`.
 */
export function deckWords(sentence: string, deck: readonly LearningCard[]): DeckWordMatch[] {
  const { key, origins, characters } = withOrigins(sentence)
  if (key === '') return []

  const matches: DeckWordMatch[] = []
  for (const card of deck) {
    const needle = normalizedKey(card.sourceText)
    if (needle === '') continue
    for (let found = key.indexOf(needle); found !== -1; found = key.indexOf(needle, found + 1)) {
      const first = origins[found]!
      const last = origins[found + needle.length - 1]!
      const before = characters[first - 1]
      const after = characters[last + 1]
      if ((before && LETTER_OR_NUMBER.test(before.text)) || (after && LETTER_OR_NUMBER.test(after.text))) continue
      matches.push({ card, start: characters[first]!.start, end: characters[last]!.end })
    }
  }
  // Stable, so two cards matching at one place stay in deck order.
  return matches.sort((a, b) => a.start - b.start)
}

/**
 * A cloze from `card`, or `null` when it cannot carry one.
 *
 * A card qualifies when it is a sentence and another card's text occurs in it
 * as a whole word. The least familiar such word is the one removed -- it is
 * the one worth testing -- and a tie goes to the earliest in the sentence.
 *
 * A blank must leave something to read: the deck can hold near-identical
 * copies of one sentence, so a different card can match the whole of this one.
 * What disqualifies a match is covering the sentence, not being the same row.
 */
export function makeCloze(card: LearningCard, deck: readonly LearningCard[]): Cloze | null {
  if (card.kind !== 'sentence') return null
  const sentence = card.sourceText
  const others = deck.filter((other) => other.id !== card.id)
  const candidates = deckWords(sentence, others).filter(
    (match) => (sentence.slice(0, match.start) + sentence.slice(match.end)).trim() !== '',
  )
  // Already in order of appearance, so the first of the lowest stage is the earliest.
  const chosen = candidates.reduce<DeckWordMatch | null>(
    (best, match) => (best === null || match.card.ladderStage < best.card.ladderStage ? match : best),
    null,
  )
  if (!chosen) return null
  return {
    answer: chosen.card,
    before: sentence.slice(0, chosen.start),
    after: sentence.slice(chosen.end),
    removed: sentence.slice(chosen.start, chosen.end),
  }
}
