import { afterEach, describe, expect, it, vi } from 'vitest'
import { rememberQuestionMix, rememberedQuestionMix } from './questionMix'

function memoryStorage() {
  const held = new Map<string, string>()
  return {
    getItem: (key: string) => held.get(key) ?? null,
    setItem: (key: string, value: string) => void held.set(key, value),
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('the remembered question mix', () => {
  it('asks both until the reader chooses', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    expect(rememberedQuestionMix()).toBe('both')
  })

  it('remembers what was chosen', () => {
    vi.stubGlobal('localStorage', memoryStorage())
    rememberQuestionMix('sentence')
    expect(rememberedQuestionMix()).toBe('sentence')
    rememberQuestionMix('cloze')
    expect(rememberedQuestionMix()).toBe('cloze')
    rememberQuestionMix('both')
    expect(rememberedQuestionMix()).toBe('both')
  })

  it('ignores a remembered value it does not know', () => {
    vi.stubGlobal('localStorage', { getItem: () => 'neither', setItem: () => {} })
    expect(rememberedQuestionMix()).toBe('both')
  })

  it('still works when storage refuses', () => {
    const refuse = () => {
      throw new Error('blocked')
    }
    vi.stubGlobal('localStorage', { getItem: refuse, setItem: refuse })
    expect(() => rememberQuestionMix('cloze')).not.toThrow()
    expect(rememberedQuestionMix()).toBe('both')
  })
})
