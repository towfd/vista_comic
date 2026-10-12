import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
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

describe('deck store standing', () => {
  const NOW = new Date('2026-08-31T12:00:00Z')
  const minutes = (n: number) => new Date(NOW.getTime() + n * 60_000).toISOString()
  const card = (id: number, state: string, dueIn: number) => ({
    id,
    state,
    dueAt: minutes(dueIn),
    createdAt: minutes(-id),
    introducedOn: state === 'new' ? null : '2026-08-01',
  })

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(NOW)
    api.fetchStudySettings.mockResolvedValue(settings)
  })
  afterEach(() => vi.useRealTimers())

  it('is unknown until a load has finished', () => {
    expect(useDeckStore().standing).toBeNull()
  })

  it('stays unknown when the load fails', async () => {
    api.fetchCards.mockRejectedValue(new ApiError('unavailable', 'down'))
    const store = useDeckStore()
    await store.load()
    expect(store.standing).toBeNull()
  })

  it('counts what is waiting at the moment the deck was fetched', async () => {
    api.fetchCards.mockResolvedValue([card(1, 'review', -5), card(2, 'learning', 10), card(3, 'new', 0), card(4, 'review', 600)])
    const store = useDeckStore()
    await store.load()
    expect(store.standing).toEqual({ counts: { due: 1, fresh: 1, learning: 1 }, remaining: 3, empty: null })
  })

  it('does not drift as the clock moves on without a fetch', async () => {
    api.fetchCards.mockResolvedValue([card(1, 'review', 5)])
    const store = useDeckStore()
    await store.load()
    vi.setSystemTime(new Date(NOW.getTime() + 60 * 60_000))
    expect(store.standing?.remaining).toBe(0)
  })

  it('says an empty deck is empty and a finished day is done', async () => {
    api.fetchCards.mockResolvedValueOnce([]).mockResolvedValue([card(1, 'review', 600)])
    const store = useDeckStore()
    await store.load()
    expect(store.standing).toMatchObject({ remaining: 0, empty: 'deckIsEmpty' })
    await store.load()
    expect(store.standing).toMatchObject({ remaining: 0, empty: 'dayIsDone' })
  })
})

describe('deck store refresh', () => {
  const NOW = new Date('2026-08-31T12:00:00Z')
  const at = (minutes: number) => new Date(NOW.getTime() + minutes * 60_000).toISOString()
  const card = (id: number, dueIn: number, ladderStage = 1) => ({
    id,
    state: 'review',
    ladderStage,
    dueAt: at(dueIn),
    createdAt: at(-id),
    introducedOn: '2026-08-01',
  })
  const schedule = { state: 'review' as const, learningStep: null, ladderStage: 5, previousStage: null, introducedOn: '2026-08-01', dueAt: at(9999) }

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(NOW)
    api.fetchStudySettings.mockResolvedValue(settings)
    vi.spyOn(console, 'warn').mockImplementation(() => {})
  })
  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  async function loadedWith(deck: object[]) {
    api.fetchCards.mockResolvedValueOnce(deck)
    const store = useDeckStore()
    await store.load()
    return store
  }

  it('replaces the deck and settings and moves the moment they are true for', async () => {
    const store = await loadedWith([card(1, -5)])
    vi.setSystemTime(new Date(NOW.getTime() + 60_000))
    api.fetchCards.mockResolvedValue([card(1, 600), card(2, -5)])
    api.fetchStudySettings.mockResolvedValue({ learningSteps: [1], newCardsPerDay: 3 })
    await store.refresh()
    expect(store.cards.map((c) => c.id)).toEqual([1, 2])
    expect(store.settings?.newCardsPerDay).toBe(3)
    expect(store.loadedAt?.getTime()).toBe(NOW.getTime() + 60_000)
    expect(store.standing?.remaining).toBe(1)
  })

  it('never shows a loading state', async () => {
    const store = await loadedWith([card(1, -5)])
    const slow = deferred<object[]>()
    api.fetchCards.mockReturnValue(slow.promise)
    const refreshing = store.refresh()
    expect(store.loading).toBe(false)
    slow.resolve([])
    await refreshing
  })

  it('keeps the held deck, and raises no error, when the fetch fails', async () => {
    const store = await loadedWith([card(1, -5)])
    api.fetchCards.mockRejectedValue(new ApiError('unavailable', 'down'))
    await store.refresh()
    expect(store.cards.map((c) => c.id)).toEqual([1])
    expect(store.error).toBeNull()
    expect(store.loaded).toBe(true)
  })

  it('does nothing before a first load has finished', async () => {
    const store = useDeckStore()
    await store.refresh()
    expect(api.fetchCards).not.toHaveBeenCalled()
  })

  it('gives way to a load already in flight', async () => {
    const store = await loadedWith([card(1, -5)])
    const slow = deferred<object[]>()
    api.fetchCards.mockReturnValue(slow.promise)
    const loading = store.load()
    await store.refresh()
    expect(api.fetchCards).toHaveBeenCalledTimes(2)
    slow.resolve([card(2, -5)])
    await loading
    expect(store.cards.map((c) => c.id)).toEqual([2])
  })

  it('does not undo a schedule written while the fetch was on its way', async () => {
    const store = await loadedWith([card(1, -5), card(2, -5)])
    const slow = deferred<object[]>()
    api.fetchCards.mockReturnValue(slow.promise)
    const refreshing = store.refresh()
    store.applySchedule(1, schedule)
    // What the server held when it answered: card 1 not yet answered.
    slow.resolve([card(1, -5), card(2, 600, 3)])
    await refreshing
    expect(store.cards.find((c) => c.id === 1)).toMatchObject({ ladderStage: 5, dueAt: schedule.dueAt })
    expect(store.cards.find((c) => c.id === 2)).toMatchObject({ ladderStage: 3 })
  })

  it('takes the server at its word for a card scheduled before the fetch set out', async () => {
    const store = await loadedWith([card(1, -5)])
    store.applySchedule(1, schedule)
    api.fetchCards.mockResolvedValue([card(1, 30, 2)])
    await store.refresh()
    expect(store.cards[0]).toMatchObject({ ladderStage: 2 })
  })

  it('does not bring back a card removed while the fetch was on its way', async () => {
    const store = await loadedWith([card(1, -5), card(2, -5)])
    const slow = deferred<object[]>()
    api.fetchCards.mockReturnValue(slow.promise)
    const refreshing = store.refresh()
    store.removeCard(1)
    slow.resolve([card(1, -5), card(2, -5)])
    await refreshing
    expect(store.cards.map((c) => c.id)).toEqual([2])
  })
})
