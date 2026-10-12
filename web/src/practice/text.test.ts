import { describe, expect, it } from 'vitest'
import { isBlank, judgeSentence, normalizedKey } from './text'

describe('normalizedKey', () => {
  it('ignores case and every kind of spacing', () => {
    expect(normalizedKey('  Tôi KHÔNG\tbiết\n')).toBe('tôikhôngbiết')
  })

  it('gives precomposed and combining forms the same key', () => {
    expect(normalizedKey('biết')).toBe(normalizedKey('biết'))
  })

  it('folds full-width forms', () => {
    expect(normalizedKey('ＡＢＣ')).toBe('abc')
  })
})

describe('judgeSentence', () => {
  const card = 'Tôi không biết đường.'

  it('accepts the exact text', () => {
    expect(judgeSentence('Tôi không biết đường.', card)).toBe(true)
  })

  it('ignores case, spacing and punctuation', () => {
    expect(judgeSentence('  tôi   KHÔNG biết đường  ', card)).toBe(true)
    expect(judgeSentence('Tôi, không biết đường!', card)).toBe(true)
    expect(judgeSentence('tôikhôngbiếtđường', card)).toBe(true)
  })

  it('treats punctuation with no space after it as a break', () => {
    expect(judgeSentence('Được,cảm ơn em', 'Được, cảm ơn em.')).toBe(true)
  })

  it('accepts combining input for a precomposed card', () => {
    expect(judgeSentence('Tôi không biết đường', card)).toBe(true)
  })

  it('rejects a different word order', () => {
    expect(judgeSentence('Không tôi biết đường', card)).toBe(false)
  })

  it('rejects a different word', () => {
    expect(judgeSentence('Tôi không thấy đường', card)).toBe(false)
  })

  it('rejects a missing word', () => {
    expect(judgeSentence('Tôi không biết', card)).toBe(false)
  })

  it('rejects a missing tone, which the phone would forgive', () => {
    expect(judgeSentence('Tôi không biêt đường', card)).toBe(false)
    expect(judgeSentence('Toi khong biet duong', card)).toBe(false)
  })

  it('rejects a wrong tone', () => {
    expect(judgeSentence('Tôi không biệt đường', card)).toBe(false)
  })

  it('rejects a missing circumflex, breve or horn', () => {
    expect(judgeSentence('Toi không biết đường', card)).toBe(false)
    expect(judgeSentence('Tôi không biết đuờng', card)).toBe(false)
    expect(judgeSentence('an', 'ăn')).toBe(false)
  })

  it('rejects d for đ', () => {
    expect(judgeSentence('Tôi không biết dường', card)).toBe(false)
  })

  it('rejects an empty or blank answer', () => {
    expect(judgeSentence('', card)).toBe(false)
    expect(judgeSentence('   ', card)).toBe(false)
    expect(judgeSentence('...', card)).toBe(false)
  })

  it('judges a word card the same way', () => {
    expect(judgeSentence('trường', 'Trường')).toBe(true)
    expect(judgeSentence('truong', 'Trường')).toBe(false)
  })
})

describe('tone placement', () => {
  it.each([
    ['hoà', 'hòa'],
    ['thuý', 'thúy'],
    ['khoẻ', 'khỏe'],
    ['Hoà bình', 'hòa bình.'],
  ])('treats %s and %s as one answer', (a, b) => {
    expect(judgeSentence(a, b)).toBe(true)
    expect(judgeSentence(b, a)).toBe(true)
  })

  it('still tells one tone from another on the same syllable', () => {
    expect(judgeSentence('hoá', 'hòa')).toBe(false)
  })

  it('still notices a missing tone', () => {
    expect(judgeSentence('hoa', 'hòa')).toBe(false)
  })

  it('does not let a tone move to another syllable', () => {
    expect(judgeSentence('hoa bình̀', 'hòa bình')).toBe(false)
    expect(judgeSentence('ma mà', 'mà ma')).toBe(false)
  })

  it('passes a tone on a vowel neither convention would choose', () => {
    expect(judgeSentence('cuả', 'của')).toBe(true)
  })
})

describe('isBlank', () => {
  it('is true for nothing and for spacing alone', () => {
    expect(isBlank('')).toBe(true)
    expect(isBlank(' \t ')).toBe(true)
  })

  it('is false once anything is typed', () => {
    expect(isBlank(' a ')).toBe(false)
  })
})
