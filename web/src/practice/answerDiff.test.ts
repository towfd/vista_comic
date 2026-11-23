import { describe, expect, it } from 'vitest'
import { markDifferences, type Piece } from './answerDiff'

/** The pieces as text, a marked word in brackets, so a test reads like the screen. */
const shown = (pieces: Piece[]) => pieces.map((piece) => (piece.marked ? `[${piece.text}]` : piece.text)).join('')

describe('markDifferences in a sentence', () => {
  const sentence = (given: string, expected: string) => {
    const marks = markDifferences(given, expected, true)
    return { given: shown(marks.given), expected: shown(marks.expected) }
  }

  it('marks the word typed wrong, and the word it should have been', () => {
    expect(sentence('Tôi khong biết đường', 'Tôi không biết đường.')).toEqual({
      given: 'Tôi [khong] biết đường',
      expected: 'Tôi [không] biết đường.',
    })
  })

  it('marks a missing word in the expected text only', () => {
    expect(sentence('Tôi biết đường', 'Tôi không biết đường.')).toEqual({
      given: 'Tôi biết đường',
      expected: 'Tôi [không] biết đường.',
    })
  })

  it('marks an extra word in the answer only', () => {
    expect(sentence('Tôi không biết đường đi', 'Tôi không biết đường.')).toEqual({
      given: 'Tôi không biết đường [đi]',
      expected: 'Tôi không biết đường.',
    })
  })

  it('marks words out of order without marking the ones in order', () => {
    const marks = sentence('Không tôi biết đường', 'Tôi không biết đường.')
    expect(marks.given.match(/\[/g)).toHaveLength(1)
    expect(marks.expected.match(/\[/g)).toHaveLength(1)
    expect(marks.given).toContain('biết đường')
  })

  it('marks a wrong tone', () => {
    expect(sentence('hoá đơn', 'hoà đơn')).toEqual({ given: '[hoá] đơn', expected: '[hoà] đơn' })
  })

  it('never marks what the judge ignores: case, punctuation, where the tone sits', () => {
    expect(sentence('TÔI, hòa! đường', 'Tôi hoà đường.')).toEqual({
      given: 'TÔI, hòa! đường',
      expected: 'Tôi hoà đường.',
    })
  })

  it('treats punctuation with no space after it as a break', () => {
    expect(sentence('Được,cam ơn', 'Được, cảm ơn.')).toEqual({ given: 'Được,[cam] ơn', expected: 'Được, [cảm] ơn.' })
  })

  it('compares combining and precomposed input as the same', () => {
    expect(sentence('Tôi không', 'Tôi không')).toEqual({ given: 'Tôi không', expected: 'Tôi không' })
  })

  it('keeps every space and line break exactly as written', () => {
    expect(sentence('Tôi  khong', 'Tôi\nkhông')).toEqual({ given: 'Tôi  [khong]', expected: 'Tôi\n[không]' })
  })

  it('marks everything when nothing matches', () => {
    expect(sentence('xin chào', 'tạm biệt')).toEqual({ given: '[xin] [chào]', expected: '[tạm] [biệt]' })
  })
})

describe('markDifferences in a cloze', () => {
  const cloze = (given: string, expected: string) => {
    const marks = markDifferences(given, expected, false)
    return { given: shown(marks.given), expected: shown(marks.expected) }
  }

  it('marks the syllable typed wrong in a word of two', () => {
    expect(cloze('học sing', 'học sinh')).toEqual({ given: 'học [sing]', expected: 'học [sinh]' })
  })

  it('counts punctuation, as the cloze judge does', () => {
    expect(cloze('đi.', 'đi')).toEqual({ given: '[đi.]', expected: '[đi]' })
  })
})
