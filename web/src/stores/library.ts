import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchComics, rescanLibrary, type ApiErrorKind } from '../api/client'
import type { ComicSummary } from '../api/types'

export const useLibraryStore = defineStore('library', () => {
  const comics = ref<ComicSummary[]>([])
  const loading = ref(false)
  const error = ref<ApiErrorKind | null>(null)
  // Whether a load has ever finished. Without it, "no comics yet" before the
  // first response and "the library is empty" would render the same.
  const loaded = ref(false)
  const refreshing = ref(false)
  // Whether the last refresh fell short: the rescan or the re-fetch failed, so
  // what is on screen is what the backend already knew, not the folder now.
  const refreshFailed = ref(false)

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

  /**
   * Rescan the library folder, then fetch the list again -- the web's version
   * of the phone's pull-to-refresh. A failed rescan still re-fetches, and once
   * a library is on screen a failed re-fetch keeps it rather than replacing it
   * with an error; either way `refreshFailed` says the list may be behind.
   */
  async function refresh() {
    if (refreshing.value) return
    refreshing.value = true
    refreshFailed.value = false
    try {
      try {
        await rescanLibrary()
      } catch (e) {
        console.warn('library rescan failed; re-fetching what the backend already knows:', e)
        refreshFailed.value = true
      }
      if (!loaded.value) {
        await load()
        return
      }
      try {
        comics.value = await fetchComics()
      } catch (e) {
        console.warn('library re-fetch failed; keeping the list on screen:', e)
        refreshFailed.value = true
      }
    } finally {
      refreshing.value = false
    }
  }

  return { comics, loading, error, loaded, refreshing, refreshFailed, load, refresh }
})
