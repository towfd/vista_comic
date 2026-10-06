import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchChapter, saveProgress as putProgress, type ApiErrorKind } from '../api/client'
import type { ChapterDetail } from '../api/types'

interface Entry {
  data: ChapterDetail | null
  loading: boolean
  error: ApiErrorKind | null
}

const keyOf = (comicId: string, chapterId: string) => `${comicId}/${chapterId}`

export const useChaptersStore = defineStore('chapters', () => {
  const entries = ref<Record<string, Entry>>({})
  // Which load of a key is the latest, so an older response arriving late
  // cannot overwrite a newer one.
  const generations: Record<string, number> = {}
  // Progress saves not yet answered. Not reactive: nothing renders from it, it
  // is only awaited (see savesSettled).
  const inFlight = new Set<Promise<boolean>>()

  function entry(comicId: string, chapterId: string): Entry {
    return entries.value[keyOf(comicId, chapterId)] ?? { data: null, loading: false, error: null }
  }

  /**
   * Resolves once every progress save sent so far has been answered (stored or
   * failed). Never rejects. Whoever reads progress back -- the reader reopening
   * a chapter, the chapter list refreshing its badges -- awaits this first, so
   * it sees the position the reader just flushed on its way out.
   */
  async function savesSettled(): Promise<void> {
    await Promise.all([...inFlight])
  }

  /**
   * Fetch a chapter fresh. Any cached copy is dropped first: the reader resumes
   * from `lastReadPage`, and a cached one would resume at a stale page, so the
   * reader shows 「載入中」 until the fresh one arrives instead.
   */
  async function load(comicId: string, chapterId: string) {
    const key = keyOf(comicId, chapterId)
    const generation = (generations[key] ?? 0) + 1
    generations[key] = generation
    entries.value[key] = { data: null, loading: true, error: null }
    await savesSettled()
    try {
      const data = await fetchChapter(comicId, chapterId)
      if (generations[key] !== generation) return
      entries.value[key] = { data, loading: false, error: null }
    } catch (e) {
      if (generations[key] !== generation) return
      const error = e instanceof ApiError ? e.kind : 'unexpected'
      entries.value[key] = { data: null, loading: false, error }
    }
  }

  /**
   * Send the reading position. Resolves `true` when stored, `false` when not;
   * never rejects. A failure logs one console.warn and nothing else -- saving
   * must never interrupt reading, and the next save is the natural retry.
   */
  function saveProgress(comicId: string, chapterId: string, lastPage: number, options: { keepalive?: boolean } = {}) {
    const request: Promise<boolean> = putProgress(comicId, chapterId, lastPage, options).then(
      () => true,
      (error: unknown) => {
        console.warn(`progress save failed (page ${lastPage} of ${comicId}/${chapterId}):`, error)
        return false
      },
    )
    inFlight.add(request)
    void request.finally(() => inFlight.delete(request))
    return request
  }

  return { entry, load, saveProgress, savesSettled }
})
