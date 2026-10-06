import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchComic, type ApiErrorKind } from '../api/client'
import type { ComicDetail } from '../api/types'

interface Entry {
  data: ComicDetail | null
  loading: boolean
  error: ApiErrorKind | null
}

/**
 * One entry per comic, so returning to a chapter list already visited is
 * instant instead of a second round trip through Cloudflare.
 */
export const useComicsStore = defineStore('comics', () => {
  const entries = ref<Record<string, Entry>>({})

  function entry(comicId: string): Entry {
    return entries.value[comicId] ?? { data: null, loading: false, error: null }
  }

  async function load(comicId: string) {
    entries.value[comicId] = { ...entry(comicId), loading: true, error: null }
    try {
      const data = await fetchComic(comicId)
      entries.value[comicId] = { data, loading: false, error: null }
    } catch (e) {
      const error = e instanceof ApiError ? e.kind : 'unexpected'
      entries.value[comicId] = { ...entry(comicId), loading: false, error }
    }
  }

  return { entries, entry, load }
})
