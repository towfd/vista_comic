import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import { useDeckStore } from './deck'

const api = vi.hoisted(() => ({ fetchCards: vi.fn(), fetchStudySettings: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, fetchCards: api.fetchCards, fetchStudySettings: api.fetchStudySettings }
})

const settings = { learningSteps: [5, 7, 10], newCardsPerDay: 15 }
const deck = (ids: number[]) => ids.map((id) => ({ id }))

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((r) => (resolve = r))
  return { promise, resolve }
}

beforeEach(() => {
  setActivePinia(createPinia())
  api.fetchCards.mockReset()
  api.fetchStudySettings.mockReset()
})

describe('deck store', () => {
  it('holds the deck and the settings once both have arrived', async () => {
    api.fetchCards.mockResolvedValue(deck([1, 2]))
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    expect(store.loaded).toBe(false)
    await store.load()
    expect(store.cards.map((c) => c.id)).toEqual([1, 2])
    expect(store.settings).toEqual(settings)
    expect(store.loaded).toBe(true)
    expect(store.loading).toBe(false)
    expect(store.error).toBeNull()
  })

  it('counts an empty deck as loaded', async () => {
    api.fetchCards.mockResolvedValue([])
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    await store.load()
    expect(store.loaded).toBe(true)
    expect(store.cards).toEqual([])
  })

  it('fails the load when the settings cannot be read, and substitutes no defaults', async () => {
    api.fetchCards.mockResolvedValue(deck([1]))
    api.fetchStudySettings.mockRejectedValue(new ApiError('unavailable', 'down'))
    const store = useDeckStore()
    await store.load()
    expect(store.error).toBe('unavailable')
    expect(store.loaded).toBe(false)
    expect(store.settings).toBeNull()
    expect(store.cards).toEqual([])
  })

  it('fails the load when the deck cannot be read', async () => {
    api.fetchCards.mockRejectedValue(new ApiError('auth', 'refused'))
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    await store.load()
    expect(store.error).toBe('auth')
    expect(store.loaded).toBe(false)
  })

  it('clears the error when a retry succeeds', async () => {
    api.fetchCards.mockRejectedValueOnce(new ApiError('unavailable', 'down')).mockResolvedValue(deck([1]))
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    await store.load()
    expect(store.error).toBe('unavailable')
    await store.load()
    expect(store.error).toBeNull()
    expect(store.loaded).toBe(true)
  })

  it('keeps the deck it has when a later load fails', async () => {
    api.fetchCards.mockResolvedValueOnce(deck([1])).mockRejectedValue(new ApiError('unavailable', 'down'))
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    await store.load()
    await store.load()
    expect(store.cards.map((c) => c.id)).toEqual([1])
    expect(store.loaded).toBe(true)
    expect(store.error).toBe('unavailable')
  })

  it('lets a newer load win over an older one that answers late', async () => {
    const slow = deferred<{ id: number }[]>()
    api.fetchCards.mockReturnValueOnce(slow.promise).mockResolvedValue(deck([2]))
    api.fetchStudySettings.mockResolvedValue(settings)
    const store = useDeckStore()
    const first = store.load()
    await store.load()
    slow.resolve(deck([1]))
    await first
    expect(store.cards.map((c) => c.id)).toEqual([2])
    expect(store.loading).toBe(false)
  })
})
