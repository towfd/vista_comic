import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, recordReview, type ApiErrorKind } from '../api/client'
import type { LearningCard, QuestionType, ReviewRequest } from '../api/types'
import { localDay, nextCard, remainingCards } from '../practice/queue'
import type { Cloze } from '../practice/cloze'
import { drawAsking } from '../practice/question'
import { isBlank, judgeCloze, judgeSentence } from '../practice/text'
import { useDeckStore } from './deck'

/** One question, as data: what is asked, of which card, and the token its answer will carry. */
export interface Question {
  card: LearningCard
  type: QuestionType
  /** The card's meaning: the whole prompt for a translation, the gloss under a cloze. */
  prompt: string
  /** The sentence with one word out, when the question is a cloze. */
  cloze: Cloze | null
  /** Made once, when the question is, so every attempt to save its answer carries the same one. */
  token: string
}

export interface Verdict {
  correct: boolean
  /** What the reader typed, as typed. */
  given: string
  /** What was asked for: the card's text, or the word missing from a cloze. */
  expected: string
  /** The whole sentence, when the question was a cloze. */
  sentence: string | null
}

/**
 * - `loading`: fetching the deck.
 * - `unavailable`: the deck could not be fetched; `loadError` says why.
 * - `asking`: a question is on screen, unanswered.
 * - `feedback`: the verdict is showing.
 * - `finished`: the queue has nothing left.
 */
export type Phase = 'loading' | 'unavailable' | 'asking' | 'feedback' | 'finished'

/**
 * Where the answer on screen stands with the backend.
 *
 * - `saving`: on its way, including the automatic retries.
 * - `saved`: the card's new schedule is held; the session may move on.
 * - `failed`: not saved, and the session will not move on. `saveFailure` says why.
 * - `gone`: the card was deleted elsewhere. Nothing to save; the session may move on.
 */
export type SaveState = 'saving' | 'saved' | 'failed' | 'gone'

/**
 * How long to wait before each automatic retry. Short, because the reader is
 * sitting on the feedback screen: a blip should heal before they finish
 * reading it, and anything longer is theirs to know about.
 */
export const RETRY_DELAYS_MS = [1_000, 2_000, 4_000]

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

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
  /** Why the answer on screen is not saved, while `saveState` is `failed`. */
  const saveFailure = ref<ApiErrorKind | null>(null)
  /** Cards still to ask, this question included. */
  const remaining = ref(0)
  /** The reader asked for the next question before the answer was saved. */
  const waitingToAdvance = ref(false)
  let lastCardId: number | undefined
  // The answer on screen, kept so a retry sends exactly what the first attempt
  // did: the same token, and the moment the reader answered rather than the
  // moment the network came back.
  let pending: { asked: Question; review: ReviewRequest } | null = null

  /** Begin from the server: fetch the deck, then draw the first question. */
  async function start() {
    phase.value = 'loading'
    loadError.value = null
    question.value = null
    verdict.value = null
    saveState.value = null
    saveFailure.value = null
    pending = null
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
    saveFailure.value = null
    pending = null
    waitingToAdvance.value = false
    if (!next.card) {
      question.value = null
      remaining.value = 0
      phase.value = 'finished'
      return
    }
    const asking = drawAsking(next.card, deck.cards, Math.random)
    question.value = { card: next.card, ...asking, prompt: next.card.translation, token: crypto.randomUUID() }
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
    const cloze = asked.cloze
    const correct = cloze
      ? judgeCloze(typed, cloze.removed, cloze.answer.sourceText)
      : judgeSentence(typed, asked.card.sourceText)
    verdict.value = {
      correct,
      given: typed.trim(),
      expected: cloze ? cloze.removed : asked.card.sourceText,
      sentence: cloze ? asked.card.sourceText : null,
    }
    phase.value = 'feedback'
    lastCardId = asked.card.id

    const answeredAt = new Date()
    pending = {
      asked,
      review: {
        questionType: asked.type,
        isCorrect: correct,
        clientToken: asked.token,
        localDate: localDay(answeredAt),
        answeredAt: answeredAt.toISOString(),
        context: 'review',
      },
    }
    void save()
  }

  /**
   * Send the answer on screen until it is saved or cannot be.
   *
   * Only an unreachable backend is retried on its own -- it is the one failure
   * that time fixes. Every attempt is the same request, so one that reached
   * the server and lost only its response cannot count twice.
   */
  async function save() {
    const current = pending
    if (!current) return
    const { asked, review } = current
    const stale = () => pending !== current
    saveState.value = 'saving'
    saveFailure.value = null

    for (let attempt = 0; ; attempt++) {
      try {
        const schedule = await recordReview(asked.card.id, review)
        // The session may have been restarted while this was in flight.
        if (stale()) return
        deck.applySchedule(asked.card.id, schedule)
        saveState.value = 'saved'
        if (waitingToAdvance.value) draw()
        return
      } catch (e) {
        if (stale()) return
        const kind = e instanceof ApiError ? e.kind : 'unexpected'
        if (kind === 'notFound') {
          // Deleted on the phone while it was on screen here. There is no card
          // left to schedule, so there is nothing to hold the session for.
          deck.removeCard(asked.card.id)
          saveState.value = 'gone'
          if (waitingToAdvance.value) draw()
          return
        }
        const delay = kind === 'unavailable' ? RETRY_DELAYS_MS[attempt] : undefined
        if (delay === undefined) {
          console.warn(`review for card ${asked.card.id} was not saved (${kind}):`, e)
          saveState.value = 'failed'
          saveFailure.value = kind
          waitingToAdvance.value = false
          return
        }
        await sleep(delay)
        if (stale()) return
      }
    }
  }

  /** Try again to save an answer the automatic retries gave up on. */
  function retrySave() {
    if (saveState.value === 'failed' && pending) void save()
  }

  /**
   * Move to the next question -- at once if the answer is saved, and as soon
   * as it is if not. An answer that failed to save holds the session here.
   */
  function advance() {
    if (phase.value !== 'feedback') return
    if (saveState.value === 'saved' || saveState.value === 'gone') draw()
    else if (saveState.value === 'saving') waitingToAdvance.value = true
  }

  return { phase, loadError, question, verdict, saveState, saveFailure, remaining, waitingToAdvance, start, submit, advance, retrySave }
})
