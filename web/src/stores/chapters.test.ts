import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import { useChaptersStore } from './chapters'

const api = vi.hoisted(() => ({ fetchChapter: vi.fn(), saveProgress: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, fetchChapter: api.fetchChapter, saveProgress: api.saveProgress }
})

const chapter = (lastReadPage?: number) => ({ id: 'c1', number: 1, title: 'One', pages: ['/m/1', '/m/2'], lastReadPage })

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((r) => (resolve = r))
  return { promise, resolve }
}

beforeEach(() => {
  setActivePinia(createPinia())
  api.fetchChapter.mockReset()
  api.saveProgress.mockReset()
})
afterEach(() => vi.restoreAllMocks())

describe('chapters store', () => {
  it('refetches on every load and drops the cached copy meanwhile', async () => {
    const store = useChaptersStore()
    api.fetchChapter.mockResolvedValueOnce(chapter(3))
    await store.load('a', 'c1')
    expect(store.entry('a', 'c1').data?.lastReadPage).toBe(3)

    const second = deferred<ReturnType<typeof chapter>>()
    api.fetchChapter.mockReturnValueOnce(second.promise)
    const loading = store.load('a', 'c1')
    expect(store.entry('a', 'c1')).toMatchObject({ data: null, loading: true })
    second.resolve(chapter(9))
    await loading
    expect(store.entry('a', 'c1').data?.lastReadPage).toBe(9)
  })

  it('waits for an in-flight save before reading the chapter back', async () => {
    const store = useChaptersStore()
    const put = deferred<unknown>()
    api.saveProgress.mockReturnValueOnce(put.promise)
    api.fetchChapter.mockResolvedValue(chapter(20))

    void store.saveProgress('a', 'c1', 20)
    const loading = store.load('a', 'c1')
    await Promise.resolve()
    expect(api.fetchChapter).not.toHaveBeenCalled()

    put.resolve({})
    await loading
    expect(api.fetchChapter).toHaveBeenCalledTimes(1)
  })

  it('exposes the in-flight save as a promise that settles with it', async () => {
    const store = useChaptersStore()
    const put = deferred<unknown>()
    api.saveProgress.mockReturnValueOnce(put.promise)
    let settled = false

    const saving = store.saveProgress('a', 'c1', 5, { keepalive: true })
    void store.savesSettled().then(() => (settled = true))
    await Promise.resolve()
    expect(settled).toBe(false)
    expect(api.saveProgress).toHaveBeenCalledWith('a', 'c1', 5, { keepalive: true })

    put.resolve({})
    expect(await saving).toBe(true)
    await store.savesSettled()
    expect(settled).toBe(true)
  })

  it('logs one warning for a failed save and resolves false instead of throwing', async () => {
    const store = useChaptersStore()
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    api.saveProgress.mockRejectedValueOnce(new ApiError('unavailable', 'status 503'))

    expect(await store.saveProgress('a', 'c1', 5)).toBe(false)
    expect(warn).toHaveBeenCalledTimes(1)
    await expect(store.savesSettled()).resolves.toBeUndefined()
  })
})
