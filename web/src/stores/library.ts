import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchComics, type ApiErrorKind } from '../api/client'
import type { ComicSummary } from '../api/types'

export const useLibraryStore = defineStore('library', () => {
  const comics = ref<ComicSummary[]>([])
  const loading = ref(false)
  const error = ref<ApiErrorKind | null>(null)
  // Whether a load has ever finished. Without it, "no comics yet" before the
  // first response and "the library is empty" would render the same.
  const loaded = ref(false)

  async function load() {
    loading.value = true
    error.value = null
    try {
      comics.value = await fetchComics()
      loaded.value = true
    } catch (e) {
      error.value = e instanceof ApiError ? e.kind : 'unexpected'
    } finally {
      loading.value = false
    }
  }

  return { comics, loading, error, loaded, load }
})
