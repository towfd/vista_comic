import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchChapter, type ApiErrorKind } from '../api/client'
import type { ChapterDetail } from '../api/types'

interface Entry {
  data: ChapterDetail | null
  loading: boolean
  error: ApiErrorKind | null
}

const keyOf = (comicId: string, chapterId: string) => `${comicId}/${chapterId}`

export const useChaptersStore = defineStore('chapters', () => {
  const entries = ref<Record<string, Entry>>({})

  function entry(comicId: string, chapterId: string): Entry {
    return entries.value[keyOf(comicId, chapterId)] ?? { data: null, loading: false, error: null }
  }

  async function load(comicId: string, chapterId: string) {
    const key = keyOf(comicId, chapterId)
    entries.value[key] = { ...entry(comicId, chapterId), loading: true, error: null }
    try {
      const data = await fetchChapter(comicId, chapterId)
      entries.value[key] = { data, loading: false, error: null }
    } catch (e) {
      const error = e instanceof ApiError ? e.kind : 'unexpected'
      entries.value[key] = { ...entry(comicId, chapterId), loading: false, error }
    }
  }

  return { entry, load }
})
