import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import type { ComicSummary } from '../api/types'
import { useLibraryStore } from './library'

const api = vi.hoisted(() => ({ fetchComics: vi.fn(), rescanLibrary: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, fetchComics: api.fetchComics, rescanLibrary: api.rescanLibrary }
})

const comic = (id: string): ComicSummary => ({ id, title: id, coverUrl: `/media/${id}/cover`, chapterCount: 1, continueChapterId: 'c1' })

beforeEach(() => {
  setActivePinia(createPinia())
  api.fetchComics.mockReset()
  api.rescanLibrary.mockReset()
  vi.spyOn(console, 'warn').mockImplementation(() => {})
})

describe('library refresh', () => {
  it('rescans before re-fetching, so the list reflects the folder now', async () => {
    const order: string[] = []
    api.rescanLibrary.mockImplementation(async () => void order.push('rescan'))
    api.fetchComics.mockImplementation(async () => {
      order.push('fetch')
      return [comic('a'), comic('b')]
    })
    const store = useLibraryStore()
    await store.refresh()
    expect(order).toEqual(['rescan', 'fetch'])
    expect(store.comics.map((c) => c.id)).toEqual(['a', 'b'])
    expect(store.refreshFailed).toBe(false)
    expect(store.refreshing).toBe(false)
  })

  it('still re-fetches after a failed rescan, and says the list may be behind', async () => {
    const store = useLibraryStore()
    api.fetchComics.mockResolvedValueOnce([comic('a')])
    await store.load()
    api.rescanLibrary.mockRejectedValue(new ApiError('unavailable', 'timed out'))
    api.fetchComics.mockResolvedValueOnce([comic('a'), comic('b')])
    await store.refresh()
    expect(store.comics).toHaveLength(2)
    expect(store.refreshFailed).toBe(true)
  })

  it('keeps the library on screen when the re-fetch fails', async () => {
    const store = useLibraryStore()
    api.fetchComics.mockResolvedValueOnce([comic('a')])
    await store.load()
    api.rescanLibrary.mockResolvedValue(undefined)
    api.fetchComics.mockRejectedValueOnce(new ApiError('unavailable', 'down'))
    await store.refresh()
    expect(store.comics.map((c) => c.id)).toEqual(['a'])
    expect(store.error).toBeNull()
    expect(store.refreshFailed).toBe(true)
  })

  it('ignores a second press while one is running', async () => {
    let finish!: () => void
    api.rescanLibrary.mockReturnValue(new Promise<void>((resolve) => (finish = resolve)))
    api.fetchComics.mockResolvedValue([])
    const store = useLibraryStore()
    const first = store.refresh()
    await store.refresh()
    finish()
    await first
    expect(api.rescanLibrary).toHaveBeenCalledTimes(1)
  })
})
