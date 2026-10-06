import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import type { ComicDetail } from '../api/types'
import { useChaptersStore } from './chapters'
import { continueChapter, useComicsStore } from './comics'

const api = vi.hoisted(() => ({ fetchComic: vi.fn(), saveProgress: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, fetchComic: api.fetchComic, saveProgress: api.saveProgress }
})

const comic = (readState: string, continueChapterId?: string): ComicDetail => ({
  id: 'a',
  title: 'One',
  coverUrl: '/media/a/cover',
  ...(continueChapterId ? { continueChapterId } : {}),
  chapters: [
    { id: 'c1', number: 1, title: 'Chapter 1', pageCount: 30, coverUrl: '/m/c1', readState },
    { id: 'c2', number: 2, title: 'Chapter 2', pageCount: 28, coverUrl: '/m/c2', readState: 'unread' },
  ],
})

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

// Let queued microtasks (the savesSettled await, then the fetch call) run.
const tick = () => new Promise((r) => setTimeout(r, 0))

beforeEach(() => {
  setActivePinia(createPinia())
  api.fetchComic.mockReset()
  api.saveProgress.mockReset()
})
afterEach(() => vi.restoreAllMocks())

describe('comics store', () => {
  it('shows loading, then the data, on a first visit', async () => {
    const store = useComicsStore()
    api.fetchComic.mockResolvedValueOnce(comic('unread'))
    const loading = store.load('a')
    expect(store.entry('a')).toMatchObject({ data: null, loading: true, error: null })
    await loading
    expect(store.entry('a')).toMatchObject({ loading: false, error: null })
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('unread')
  })

  it('keeps the cached copy visible while revalidating, then swaps in the fresh one', async () => {
    const store = useComicsStore()
    api.fetchComic.mockResolvedValueOnce(comic('unread'))
    await store.load('a')

    const fresh = deferred<ComicDetail>()
    api.fetchComic.mockReturnValueOnce(fresh.promise)
    const revalidating = store.load('a')
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('unread')
    expect(store.entry('a').error).toBeNull()

    fresh.resolve(comic('reading'))
    await revalidating
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('reading')
    expect(api.fetchComic).toHaveBeenCalledTimes(2)
  })

  it('waits for an in-flight progress save before refetching', async () => {
    const store = useComicsStore()
    const put = deferred<unknown>()
    api.saveProgress.mockReturnValueOnce(put.promise)
    api.fetchComic.mockResolvedValue(comic('reading'))

    void useChaptersStore().saveProgress('a', 'c1', 12)
    const loading = store.load('a')
    await tick()
    expect(api.fetchComic).not.toHaveBeenCalled()

    put.resolve({})
    await loading
    expect(api.fetchComic).toHaveBeenCalledTimes(1)
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('reading')
  })

  it('keeps the cached copy, with no error, when a background refetch fails', async () => {
    const store = useComicsStore()
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    api.fetchComic.mockResolvedValueOnce(comic('read'))
    await store.load('a')

    api.fetchComic.mockRejectedValueOnce(new ApiError('unavailable', 'status 502'))
    await store.load('a')
    expect(store.entry('a')).toMatchObject({ loading: false, error: null })
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('read')
  })

  it('reports the error when there is no cached copy', async () => {
    const store = useComicsStore()
    api.fetchComic.mockRejectedValueOnce(new ApiError('notFound', 'status 404'))
    await store.load('a')
    expect(store.entry('a')).toMatchObject({ data: null, loading: false, error: 'notFound' })
  })

  it('ignores an older response that arrives after a newer one', async () => {
    const store = useComicsStore()
    const older = deferred<ComicDetail>()
    const newer = deferred<ComicDetail>()
    api.fetchComic.mockReturnValueOnce(older.promise).mockReturnValueOnce(newer.promise)

    const first = store.load('a')
    const second = store.load('a')
    await tick()
    newer.resolve(comic('reading'))
    await second
    older.resolve(comic('unread'))
    await first
    expect(store.entry('a').data?.chapters[0]?.readState).toBe('reading')
    expect(store.entry('a').loading).toBe(false)
  })

  it('ignores an older failure that arrives after a newer success', async () => {
    const store = useComicsStore()
    const older = deferred<ComicDetail>()
    api.fetchComic.mockReturnValueOnce(older.promise).mockResolvedValueOnce(comic('reading'))

    const first = store.load('a')
    await store.load('a')
    older.reject(new ApiError('unavailable', 'status 502'))
    await first
    expect(store.entry('a')).toMatchObject({ loading: false, error: null })
  })
})

describe('continueChapter', () => {
  it('finds the chapter named by continueChapterId', () => {
    expect(continueChapter(comic('reading', 'c2'))?.number).toBe(2)
  })

  it('is null when the backend sent no continueChapterId', () => {
    expect(continueChapter(comic('reading'))).toBeNull()
  })

  it('is null when the id is not in the chapter list', () => {
    expect(continueChapter(comic('reading', 'gone'))).toBeNull()
  })
})
