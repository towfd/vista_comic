// Which words of a wrong answer differ from what was asked for. Free of the DOM
// and of Vue; see .scratch/web-answer-diff/spec.md.

import { syllableKey } from './text'

/** A run of a text as written, and whether it is a word that differs. */
export interface Piece {
  text: string
  marked: boolean
}

/** Both texts, cut into pieces that join back into exactly what was written. */
export interface Differences {
  given: Piece[]
  expected: Piece[]
}

// What stands between two words. A sentence's judge reads punctuation and
// symbols as a break, so they separate words here too and are never marked; a
// cloze's judge counts them, so there they stay part of the word.
const SENTENCE_GAP = /[\p{White_Space}\p{P}\p{S}]+/gu
const CLOZE_GAP = /\p{White_Space}+/gu

interface Word {
  piece: Piece
  key: string
}

/** `text` cut into words and the gaps between them, keeping every character. */
function cut(text: string, gap: RegExp): { pieces: Piece[]; words: Word[] } {
  const pieces: Piece[] = []
  const words: Word[] = []
  const addWord = (word: string) => {
    const piece = { text: word, marked: false }
    pieces.push(piece)
    words.push({ piece, key: syllableKey(word) })
  }
  let at = 0
  for (const match of text.matchAll(gap)) {
    if (match.index > at) addWord(text.slice(at, match.index))
    pieces.push({ text: match[0], marked: false })
    at = match.index + match[0].length
  }
  if (at < text.length) addWord(text.slice(at))
  return { pieces, words }
}

/**
 * Marks the words of `given` that are not in `expected`, and the words of
 * `expected` that `given` lacks, compared as the judge compares syllables.
 *
 * The two are lined up by their longest common run of words in order, so one
 * wrong or missing word marks that word alone rather than everything after it.
 * `ignorePunctuation` is the judge's own: on for a sentence, off for a cloze.
 */
export function markDifferences(given: string, expected: string, ignorePunctuation: boolean): Differences {
  const gap = ignorePunctuation ? SENTENCE_GAP : CLOZE_GAP
  const a = cut(given, gap)
  const b = cut(expected, gap)
  const n = a.words.length
  const m = b.words.length

  // common[i][j]: the most words a.words[i..] and b.words[j..] share in order.
  const common = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0))
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      common[i]![j] =
        a.words[i]!.key === b.words[j]!.key ? common[i + 1]![j + 1]! + 1 : Math.max(common[i + 1]![j]!, common[i]![j + 1]!)
    }
  }

  let i = 0
  let j = 0
  while (i < n && j < m) {
    if (a.words[i]!.key === b.words[j]!.key) {
      i++
      j++
    } else if (common[i + 1]![j]! >= common[i]![j + 1]!) {
      a.words[i++]!.piece.marked = true
    } else {
      b.words[j++]!.piece.marked = true
    }
  }
  while (i < n) a.words[i++]!.piece.marked = true
  while (j < m) b.words[j++]!.piece.marked = true

  return { given: a.pieces, expected: b.pieces }
}
