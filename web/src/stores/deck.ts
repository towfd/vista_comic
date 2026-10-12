import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { ApiError, fetchCards, fetchStudySettings, type ApiErrorKind } from '../api/client'
import type { CardSchedule, LearningCard, StudySettings } from '../api/types'
import { localDay, nextCard, waiting, type QueueEmpty, type Waiting } from '../practice/queue'

/** What is waiting, and why nothing is when nothing is. */
export interface Standing {
  counts: Waiting
  /** The three counts added together: what a session started now would ask. */
  remaining: number
  empty: QueueEmpty | null
}

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
  // The moment the held deck was fetched, and so the moment `standing` is true
  // for. Kept here rather than read by each screen, so the navigation bar and
  // the overview can never show numbers from two different instants.
  const loadedAt = ref<Date | null>(null)
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
      loadedAt.value = new Date()
    } catch (e) {
      if (mine !== generation) return
      error.value = e instanceof ApiError ? e.kind : 'unexpected'
    } finally {
      if (mine === generation) loading.value = false
    }
  }

  /**
   * Write the schedule an answer earned onto its card. The moment the deck is
   * true for moves with it, so the count beside 練習 follows a session along.
   * A card no longer held -- deleted meanwhile -- is ignored.
   */
  function applySchedule(cardId: number, schedule: CardSchedule) {
    const index = cards.value.findIndex((card) => card.id === cardId)
    if (index === -1) return
    cards.value[index] = { ...cards.value[index]!, ...schedule }
    loadedAt.value = new Date()
  }

  const standing = computed<Standing | null>(() => {
    if (!settings.value || !loadedAt.value) return null
    const now = loadedAt.value
    const today = localDay(now)
    const counts = waiting(cards.value, settings.value, now, today)
    return {
      counts,
      remaining: counts.due + counts.fresh + counts.learning,
      empty: nextCard(cards.value, settings.value, now, today).empty ?? null,
    }
  })

  return { cards, settings, loading, error, loaded, loadedAt, standing, load, applySchedule }
})
