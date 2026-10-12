import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, recordReview, type ApiErrorKind } from '../api/client'
import type { LearningCard, QuestionType, ReviewRequest } from '../api/types'
import { localDay, nextCard, remainingCards } from '../practice/queue'
import { isBlank, judgeSentence } from '../practice/text'
import { useDeckStore } from './deck'

/** One question, as data: what is asked, of which card, and the token its answer will carry. */
export interface Question {
  card: LearningCard
  type: QuestionType
  /** What the reader is shown: for a translation, the card's meaning. */
  prompt: string
  /** Made once, when the question is, so every attempt to save its answer carries the same one. */
  token: string
}

export interface Verdict {
  correct: boolean
  /** What the reader typed, as typed. */
  given: string
  /** The card's text. */
  expected: string
}

/**
 * - `loading`: fetching the deck.
 * - `unavailable`: the deck could not be fetched; `loadError` says why.
 * - `asking`: a question is on screen, unanswered.
 * - `feedback`: the verdict is showing.
 * - `finished`: the queue has nothing left.
 */
export type Phase = 'loading' | 'unavailable' | 'asking' | 'feedback' | 'finished'

/** Where the answer on screen stands with the backend. */
export type SaveState = 'saving' | 'saved' | 'failed'

/**
 * One practice session: ask, judge, save, and only then ask again.
 *
 * The two halves of an answer come apart here. Whether it was right is judged
 * in the browser and shown at once. Where the card goes next is the server's
 * to say, so the next question is never drawn until the response is in -- the
 * queue is only ever computed from schedules the server actually returned.
 */
export const useSessionStore = defineStore('session', () => {
  const deck = useDeckStore()

  const phase = ref<Phase>('loading')
  const loadError = ref<ApiErrorKind | null>(null)
  const question = ref<Question | null>(null)
  const verdict = ref<Verdict | null>(null)
  const saveState = ref<SaveState | null>(null)
  /** Cards still to ask, this question included. */
  const remaining = ref(0)
  /** The reader asked for the next question before the answer was saved. */
  const waitingToAdvance = ref(false)
  let lastCardId: number | undefined

  /** Begin from the server: fetch the deck, then draw the first question. */
  async function start() {
    phase.value = 'loading'
    loadError.value = null
    question.value = null
    verdict.value = null
    saveState.value = null
    waitingToAdvance.value = false
    lastCardId = undefined
    await deck.load()
    if (deck.error || !deck.settings) {
      loadError.value = deck.error ?? 'unexpected'
      phase.value = 'unavailable'
      return
    }
    draw()
  }

  /** Ask the queue, with the clock read now rather than held from an earlier question. */
  function draw() {
    const settings = deck.settings
    if (!settings) return
    const now = new Date()
    const today = localDay(now)
    const next = nextCard(deck.cards, settings, now, today, lastCardId)
    verdict.value = null
    saveState.value = null
    waitingToAdvance.value = false
    if (!next.card) {
      question.value = null
      remaining.value = 0
      phase.value = 'finished'
      return
    }
    question.value = { card: next.card, type: 'sentence_typed', prompt: next.card.translation, token: crypto.randomUUID() }
    remaining.value = remainingCards(deck.cards, settings, now, today)
    phase.value = 'asking'
  }

  /**
   * Judge what was typed and send it. The verdict does not wait for the
   * request; the next question does. Nothing happens for an empty field, or
   * when no question is waiting for an answer.
   */
  function submit(typed: string) {
    const asked = question.value
    if (phase.value !== 'asking' || !asked || isBlank(typed)) return
    const correct = judgeSentence(typed, asked.card.sourceText)
    verdict.value = { correct, given: typed.trim(), expected: asked.card.sourceText }
    phase.value = 'feedback'
    lastCardId = asked.card.id

    const answeredAt = new Date()
    void save(asked, {
      questionType: asked.type,
      isCorrect: correct,
      clientToken: asked.token,
      localDate: localDay(answeredAt),
      answeredAt: answeredAt.toISOString(),
      context: 'review',
    })
  }

  async function save(asked: Question, review: ReviewRequest) {
    saveState.value = 'saving'
    try {
      const schedule = await recordReview(asked.card.id, review)
      // The session may have been restarted while this was in flight.
      if (question.value !== asked) return
      deck.applySchedule(asked.card.id, schedule)
      saveState.value = 'saved'
      if (waitingToAdvance.value) draw()
    } catch (e) {
      if (question.value !== asked) return
      console.warn(`review for card ${asked.card.id} was not saved:`, e instanceof ApiError ? e.kind : e)
      saveState.value = 'failed'
      waitingToAdvance.value = false
    }
  }

  /**
   * Move to the next question -- at once if the answer is saved, and as soon
   * as it is if not. An answer that failed to save holds the session here.
   */
  function advance() {
    if (phase.value !== 'feedback') return
    if (saveState.value === 'saved') draw()
    else if (saveState.value === 'saving') waitingToAdvance.value = true
  }

  return { phase, loadError, question, verdict, saveState, remaining, waitingToAdvance, start, submit, advance }
})
