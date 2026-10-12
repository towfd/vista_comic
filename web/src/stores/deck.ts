import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, fetchCards, fetchStudySettings, type ApiErrorKind } from '../api/client'
import type { LearningCard, StudySettings } from '../api/types'

/**
 * The deck and the study settings, held together because nothing practice
 * computes -- the queue, the allowance, what is waiting -- makes sense from
 * one without the other.
 */
export const useDeckStore = defineStore('deck', () => {
  const cards = ref<LearningCard[]>([])
  const settings = ref<StudySettings | null>(null)
  const loading = ref(false)
  const error = ref<ApiErrorKind | null>(null)
  // Whether a load has ever finished, so "not fetched yet" and "an empty deck"
  // do not render the same.
  const loaded = ref(false)
  // Which load is the latest, so an older response arriving late cannot
  // overwrite a newer one.
  let generation = 0

  /**
   * Fetch both fresh. Either failing fails the load: default settings are
   * never substituted, because a guessed allowance introduces new cards the
   * day has no room for -- the one thing the backend does not refuse.
   */
  async function load() {
    const mine = ++generation
    loading.value = true
    error.value = null
    try {
      const [deck, study] = await Promise.all([fetchCards(), fetchStudySettings()])
      if (mine !== generation) return
      cards.value = deck
      settings.value = study
      loaded.value = true
    } catch (e) {
      if (mine !== generation) return
      error.value = e instanceof ApiError ? e.kind : 'unexpected'
    } finally {
      if (mine === generation) loading.value = false
    }
  }

  return { cards, settings, loading, error, loaded, load }
})
