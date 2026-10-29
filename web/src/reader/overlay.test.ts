import { describe, expect, it } from 'vitest'
import { bubbleSourceText } from './overlay'

describe('the original filled in from a bubble', () => {
  it('is upper-cased when OCR read it in mixed case', () => {
    expect(bubbleSourceText('Không nghe máy à?')).toBe('KHÔNG NGHE MÁY À?')
  })

  it('is unchanged when it is already upper case', () => {
    expect(bubbleSourceText('TÊN KHỐN NÀY.')).toBe('TÊN KHỐN NÀY.')
  })

  it('keeps every Vietnamese mark and turns đ into Đ', () => {
    expect(bubbleSourceText('đã vậy còn không chịu ở bên cạnh mình nữa')).toBe(
      'ĐÃ VẬY CÒN KHÔNG CHỊU Ở BÊN CẠNH MÌNH NỮA',
    )
    expect(bubbleSourceText('ưởng ợ ỹ')).toBe('ƯỞNG Ợ Ỹ')
  })
})
