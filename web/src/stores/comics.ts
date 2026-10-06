import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchComic, type ApiErrorKind } from '../api/client'
import type { ChapterSummary, ComicDetail } from '../api/types'
import { useChaptersStore } from './chapters'

interface Entry {
  data: ComicDetail | null
  loading: boolean
  error: ApiErrorKind | null
}

/**
 * The chapter the Continue button opens: the one whose id is the backend's
 * `continueChapterId`. `null` when the field is absent (backend not yet
 * deployed) or names a chapter not in the list -- the button is then hidden.
 */
export function continueChapter(comic: ComicDetail): ChapterSummary | null {
  if (!comic.continueChapterId) return null
  return comic.chapters.find((chapter) => chapter.id === comic.continueChapterId) ?? null
}

/**
 * One entry per comic, revalidated on every visit (stale-while-revalidate): a
 * cached copy renders at once while a fresh one is fetched in the background,
 * so read badges and Continue catch up with what was just read without the
 * list flashing back to 「載入中」.
 */
export const useComicsStore = defineStore('comics', () => {
  const entries = ref<Record<string, Entry>>({})
  // Which load of a comic is the latest, so an older response arriving late
  // cannot overwrite a newer one.
  const generations: Record<string, number> = {}

  function entry(comicId: string): Entry {
    return entries.value[comicId] ?? { data: null, loading: false, error: null }
  }

  /**
   * Fetch the comic fresh, keeping any cached copy visible meanwhile.
   *
   * Waits for the reader's in-flight progress saves first, so the refreshed
   * badges include the chapter just left. With a cached copy, a failed refetch
   * is dropped silently -- good data stays on screen, no error over it. With
   * none, `loading` and `error` drive the screen as before.
   */
  async function load(comicId: string) {
    const generation = (generations[comicId] ?? 0) + 1
    generations[comicId] = generation
    entries.value[comicId] = { ...entry(comicId), loading: true, error: null }
    await useChaptersStore().savesSettled()
    try {
      const data = await fetchComic(comicId)
      if (generations[comicId] !== generation) return
      entries.value[comicId] = { data, loading: false, error: null }
    } catch (e) {
      if (generations[comicId] !== generation) return
      const cached = entry(comicId).data
      if (cached) {
        console.warn(`comic refresh failed for ${comicId}; keeping the cached copy:`, e)
        entries.value[comicId] = { data: cached, loading: false, error: null }
        return
      }
      const error = e instanceof ApiError ? e.kind : 'unexpected'
      entries.value[comicId] = { data: null, loading: false, error }
    }
  }

  return { entries, entry, load }
})
