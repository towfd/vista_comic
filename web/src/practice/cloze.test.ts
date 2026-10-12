import { describe, expect, it } from 'vitest'
import type { LearningCard } from '../api/types'
import { deckWords, makeCloze } from './cloze'
import { drawAsking } from './question'
import { judgeCloze } from './text'

let nextId = 1
function card(sourceText: string, extra: Partial<LearningCard> = {}): LearningCard {
  return {
    id: nextId++,
    sourceText,
    translation: `meaning of ${sourceText}`,
    kind: 'word',
    state: 'review',
    ladderStage: 0,
    learningStep: null,
    previousStage: null,
    introducedOn: '2026-08-01',
    dueAt: '2026-08-31T12:00:00+00:00',
    createdAt: '2026-08-01T12:00:00+00:00',
    ...extra,
  }
}
const sentence = (text: string, extra: Partial<LearningCard> = {}) => card(text, { kind: 'sentence', ...extra })
const found = (text: string, deck: LearningCard[]) => deckWords(text, deck).map((match) => text.slice(match.start, match.end))

describe('deckWords', () => {
  it('finds a deck word and reports where it sits in the original sentence', () => {
    expect(found('Tôi không biết đường.', [card('biết')])).toEqual(['biết'])
  })

  it('finds a word of several syllables', () => {
    expect(found('Đây là đạo luật mới', [card('đạo luật')])).toEqual(['đạo luật'])
  })

  it('ignores case', () => {
    expect(found('TÔI KHÔNG BIẾT', [card('biết')])).toEqual(['BIẾT'])
    expect(found('tôi không biết', [card('BIẾT')])).toEqual(['biết'])
  })

  it('sees through doubled spaces and line breaks, and still blanks the right span', () => {
    const text = 'Đây  là đạo\n luật mới'
    expect(found(text, [card('đạo luật')])).toEqual(['đạo\n luật'])
  })

  it('matches full-width forms', () => {
    expect(found('ＡＢＣ là gì', [card('abc')])).toEqual(['ＡＢＣ'])
  })

  it('matches combining input against a precomposed card', () => {
    expect(found('Tôi không biết', [card('biết')])).toEqual(['biết'])
  })

  it('does not match inside a longer word', () => {
    expect(found('THÂN THỂ', [card('AN')])).toEqual([])
    expect(found('thanh', [card('than')])).toEqual([])
  })

  it('does not match inside a longer word whose neighbour is not ASCII', () => {
    // The case JavaScript's \b gets wrong: À is not a word character to it.
    expect(found('XIN CHÀO', [card('ÀO')])).toEqual([])
    expect(found('ôm', [card('m')])).toEqual([])
  })

  it('does not match next to a digit', () => {
    expect(found('số 12', [card('1')])).toEqual([])
  })

  it('treats punctuation and the ends of the sentence as boundaries', () => {
    expect(found('Được, cảm ơn!', [card('được')])).toEqual(['Được'])
    expect(found('"cảm ơn"', [card('cảm ơn')])).toEqual(['cảm ơn'])
    expect(found('cảm ơn', [card('ơn')])).toEqual(['ơn'])
  })

  it('does not match a word that differs only by tone', () => {
    expect(found('THÂN THÊ', [card('thân thể')])).toEqual([])
    expect(found('hòa bình', [card('hoà')])).toEqual([])
  })

  it('finds a word every time it occurs, in order of appearance', () => {
    const matches = deckWords('ma và ma', [card('ma')])
    expect(matches.map((match) => match.start)).toEqual([0, 6])
  })

  it('lists matches of different cards by where they appear, not by deck order', () => {
    const text = 'Tôi không biết đường'
    expect(found(text, [card('đường'), card('không')])).toEqual(['không', 'đường'])
  })

  it('finds nothing in an empty sentence or for a card with no text', () => {
    expect(found('', [card('a')])).toEqual([])
    expect(found('a b', [card('   ')])).toEqual([])
  })
})

describe('makeCloze', () => {
  it('blanks a deck word and leaves the rest of the sentence intact', () => {
    const word = card('đường')
    const asked = sentence('Tôi không  biết ĐƯỜNG\nđến trường.')
    const cloze = makeCloze(asked, [asked, word])
    expect(cloze).toEqual({ answer: word, before: 'Tôi không  biết ', removed: 'ĐƯỜNG', after: '\nđến trường.' })
  })

  it('blanks the least familiar of the words present', () => {
    const known = card('không', { ladderStage: 4 })
    const shaky = card('đường', { ladderStage: 1 })
    const asked = sentence('Tôi không biết đường')
    expect(makeCloze(asked, [known, shaky, asked])?.removed).toBe('đường')
  })

  it('breaks a tie by taking the word that appears first', () => {
    const later = card('đường', { ladderStage: 2 })
    const earlier = card('không', { ladderStage: 2 })
    const asked = sentence('Tôi không biết đường')
    expect(makeCloze(asked, [later, earlier, asked])?.removed).toBe('không')
  })

  it('has none for a sentence holding no deck word', () => {
    const asked = sentence('Tôi không biết')
    expect(makeCloze(asked, [asked, card('đường')])).toBeNull()
  })

  it('has none for a word card or a card with no kind', () => {
    const deck = [card('biết')]
    expect(makeCloze(card('Tôi không biết'), deck)).toBeNull()
    expect(makeCloze(card('Tôi không biết', { kind: null }), deck)).toBeNull()
  })

  it('never blanks a card with itself', () => {
    const asked = sentence('đường')
    expect(makeCloze(asked, [asked])).toBeNull()
  })

  it('does not use a match that would leave nothing to read', () => {
    const asked = sentence('  Cảm ơn  ')
    const twin = sentence('cảm ơn')
    expect(makeCloze(asked, [asked, twin])).toBeNull()
  })

  it('uses a smaller word when a larger one covers the whole sentence', () => {
    const asked = sentence('Cảm ơn')
    const twin = sentence('cảm ơn', { ladderStage: 0 })
    const part = card('ơn', { ladderStage: 5 })
    expect(makeCloze(asked, [asked, twin, part])?.removed).toBe('ơn')
  })
})

describe('drawAsking', () => {
  const word = card('đường')
  const asked = sentence('Tôi không biết đường')
  const deck = [asked, word]

  it('offers a cloze and a translation in equal measure when a card supports both', () => {
    expect(drawAsking(asked, deck, () => 0).type).toBe('cloze_typed')
    expect(drawAsking(asked, deck, () => 0.49).type).toBe('cloze_typed')
    expect(drawAsking(asked, deck, () => 0.5).type).toBe('sentence_typed')
    expect(drawAsking(asked, deck, () => 0.99).type).toBe('sentence_typed')
  })

  it('carries the cloze exactly when the question is one', () => {
    expect(drawAsking(asked, deck, () => 0).cloze?.removed).toBe('đường')
    expect(drawAsking(asked, deck, () => 0.99).cloze).toBeNull()
  })

  it('asks a word card by translation whatever the draw', () => {
    expect(drawAsking(word, deck, () => 0)).toEqual({ type: 'sentence_typed', cloze: null })
  })
})

describe('judgeCloze', () => {
  it('accepts the word as it was written in the sentence', () => {
    expect(judgeCloze('ĐƯỜNG', 'ĐƯỜNG', 'đường')).toBe(true)
  })

  it("accepts the word as the reader's own card has it", () => {
    expect(judgeCloze('đạo luật', 'đạo\n luật', 'Đạo luật')).toBe(true)
  })

  it('ignores case and spacing', () => {
    expect(judgeCloze('  Đường ', 'ĐƯỜNG', 'đường')).toBe(true)
    expect(judgeCloze('đạoluật', 'đạo luật', 'đạo luật')).toBe(true)
  })

  it('is strict about tones', () => {
    expect(judgeCloze('duong', 'ĐƯỜNG', 'đường')).toBe(false)
    expect(judgeCloze('đương', 'ĐƯỜNG', 'đường')).toBe(false)
    expect(judgeCloze('đướng', 'ĐƯỜNG', 'đường')).toBe(false)
  })

  it('treats both tone placements as one answer', () => {
    expect(judgeCloze('hòa', 'hoà', 'hoà')).toBe(true)
  })

  it('does not ignore punctuation', () => {
    expect(judgeCloze('đường.', 'ĐƯỜNG', 'đường')).toBe(false)
  })

  it('rejects another word, and nothing at all', () => {
    expect(judgeCloze('trường', 'ĐƯỜNG', 'đường')).toBe(false)
    expect(judgeCloze('  ', 'ĐƯỜNG', 'đường')).toBe(false)
  })
})
