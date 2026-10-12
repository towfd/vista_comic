import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { ApiError, createCard, type ApiErrorKind, type Collected } from '../api/client'
import type { LearningCard } from '../api/types'
import { isBlank } from '../practice/text'
import { useDeckStore } from './deck'

/** The longest source text the deck accepts. The backend refuses anything longer. */
export const SOURCE_TEXT_LIMIT = 200

/**
 * Why the last add made no new card.
 *
 * - `exists`: the line was already in the deck. `card` is the one it holds --
 *   untouched, so what was typed here was not saved onto it.
 * - `failed`: the request did not go through.
 */
export type Notice = { kind: 'exists'; card: LearningCard } | { kind: 'failed'; error: ApiErrorKind }

/**
 * The collecting panel: one line typed into the deck from the chapter being
 * read. Everything the panel does is decided here; the component renders it
 * and the reader feeds in the one fact this cannot know -- which page is
 * current. See .scratch/web-card-collection/spec.md.
 */
export const useCollectStore = defineStore('collect', () => {
  const deck = useDeckStore()

  const open = ref(false)
  const sourceText = ref('')
  const translation = ref('')
  // The page the card will record, fixed when the reader starts typing so that
  // scrolling on mid-card cannot change where the line is said to come from.
  const page = ref<number | null>(null)
  const saving = ref(false)
  const notice = ref<Notice | null>(null)
  // The line just added, for the confirmation shown once the panel has gone.
  const added = ref<string | null>(null)

  let chapter: { comicId: string; chapterId: string } | null = null
  let currentPage: number | null = null
  // Moves on every reset. An add that set out under an older one finds the
  // panel it belonged to gone, and must not act on the one that replaced it.
  let epoch = 0

  function reset() {
    epoch++
    open.value = false
    sourceText.value = ''
    translation.value = ''
    page.value = null
    notice.value = null
  }

  /** The reader opened a chapter. Whatever was being typed belonged to the last one. */
  function enter(comicId: string, chapterId: string) {
    reset()
    chapter = { comicId, chapterId }
    currentPage = null
    added.value = null
  }

  /** The reader's current page, as the progress rules define it; `null` before anything has been seen. */
  function setCurrentPage(value: number | null) {
    currentPage = value
  }

  function openPanel() {
    open.value = true
    added.value = null
  }

  /** Close the panel and discard everything in it. There is no draft. */
  function collapse() {
    reset()
  }

  function setSourceText(text: string) {
    const wasEmpty = sourceText.value === ''
    sourceText.value = text
    notice.value = null
    if (text === '') page.value = null
    else if (wasEmpty || page.value === null) page.value = currentPage
  }

  function setTranslation(text: string) {
    translation.value = text
    notice.value = null
  }

  const canAdd = computed(
    () =>
      !saving.value &&
      page.value !== null &&
      !isBlank(sourceText.value) &&
      !isBlank(translation.value) &&
      sourceText.value.trim().length <= SOURCE_TEXT_LIMIT,
  )

  /**
   * Send the line as a card of this kind. A new card clears and closes the
   * panel; a line already collected, or a failure, leaves it open with the
   * text as typed. Whatever card comes back goes to the deck either way -- a
   * line collected again may be a deleted card returning.
   */
  async function add(kind: 'word' | 'sentence') {
    if (!canAdd.value || !chapter || page.value === null) return
    const mine = epoch
    const line = sourceText.value.trim()
    saving.value = true
    notice.value = null
    let collected: Collected
    try {
      collected = await createCard({
        sourceText: line,
        translation: translation.value.trim(),
        kind,
        comicId: chapter.comicId,
        chapterId: chapter.chapterId,
        pageNumber: page.value,
      })
    } catch (e) {
      // Only the request is in here. Anything that goes wrong after the server
      // has answered must never be reported as the card not being saved.
      console.warn('collecting a card failed:', e)
      if (mine === epoch) notice.value = { kind: 'failed', error: e instanceof ApiError ? e.kind : 'unexpected' }
      return
    } finally {
      saving.value = false
    }

    const { card, created } = collected
    if (created) {
      // Said even when the panel was closed meanwhile: the card is in the deck.
      added.value = line
      if (mine === epoch) reset()
    } else if (mine === epoch) {
      notice.value = { kind: 'exists', card }
    }
    try {
      deck.takeCard(card)
    } catch (e) {
      // The card is on the server either way; the next deck load brings it in.
      console.error('collected, but the held deck could not take the card:', e)
    }
  }

  function dismissAdded() {
    added.value = null
  }

  return {
    open,
    sourceText,
    translation,
    page,
    saving,
    notice,
    added,
    canAdd,
    enter,
    setCurrentPage,
    openPanel,
    collapse,
    setSourceText,
    setTranslation,
    add,
    dismissAdded,
  }
})
