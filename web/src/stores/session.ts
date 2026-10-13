import { defineStore } from 'pinia'
import { ref } from 'vue'
import { ApiError, recordReview, type ApiErrorKind } from '../api/client'
import type { LearningCard, QuestionType, ReviewRequest } from '../api/types'
import { localDay, nextCard, remainingCards } from '../practice/queue'
import type { Cloze } from '../practice/cloze'
import { drawAsking } from '../practice/question'
import { isBlank, judgeCloze, judgeSentence } from '../practice/text'
import { useDeckStore } from './deck'

/**
 * A fresh idempotency key. `crypto.randomUUID` exists only in a secure context
 * -- HTTPS or localhost -- so the page opened by IP address or over plain HTTP
 * has none, and a question could not be drawn at all. `getRandomValues` carries
 * no such restriction.
 */
export function newToken(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
}

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
 * - `checking`: the queue came up empty and the deck is being fetched once more to be sure.
 * - `finished`: the queue has nothing left.
 */
export type Phase = 'loading' | 'unavailable' | 'asking' | 'feedback' | 'checking' | 'finished'

/** What a session achieved, counted from answers that were saved. */
export interface Outcome {
  correct: number
  wrong: number
  /** Cards standing in review after their last answer this session. */
  graduated: number
}

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
  const outcome = ref<Outcome>({ correct: 0, wrong: 0, graduated: 0 })
  // By id rather than as a tally: a card that graduates and is then missed in
  // the same session has not graduated, and only a set can take it back out.
  const graduatedIds = new Set<number>()
  // Raised by anything that abandons the question in hand -- a restart -- so
  // work still in flight for the old one can tell it is no longer wanted.
  let run = 0
  let lastCardId: number | undefined
  // The answer on screen, kept so a retry sends exactly what the first attempt
  // did: the same token, and the moment the reader answered rather than the
  // moment the network came back.
  let pending: { asked: Question; review: ReviewRequest } | null = null

  /** Begin from the server: fetch the deck, then draw the first question. */
  async function start() {
    run++
    phase.value = 'loading'
    outcome.value = { correct: 0, wrong: 0, graduated: 0 }
    graduatedIds.clear()
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
    // Fetched a moment ago: an empty queue here needs no second look.
    draw({ recheck: false })
  }

  /** The queue's answer for this instant: the clock is read now, never held from an earlier question. */
  function ask() {
    const settings = deck.settings
    if (!settings) return null
    const now = new Date()
    const today = localDay(now)
    return { next: nextCard(deck.cards, settings, now, today, lastCardId), left: remainingCards(deck.cards, settings, now, today) }
  }

  /**
   * Put the next question on screen, or end the session.
   *
   * "Finished" is the one thing a session says about the whole deck, so it is
   * not said from an old copy: when the queue comes up empty the deck is
   * fetched once more and the queue asked again. A fetch that fails changes
   * nothing, and the session ends on what it holds.
   */
  function draw({ recheck = true } = {}) {
    verdict.value = null
    saveState.value = null
    saveFailure.value = null
    pending = null
    waitingToAdvance.value = false

    const asked = ask()
    if (!asked) return
    if (asked.next.card) return show(asked.next.card, asked.left)
    question.value = null
    remaining.value = 0
    if (!recheck) {
      phase.value = 'finished'
      return
    }
    phase.value = 'checking'
    const mine = run
    void deck.refresh().then(() => {
      if (mine !== run || phase.value !== 'checking') return
      const again = ask()
      if (again?.next.card) show(again.next.card, again.left)
      else phase.value = 'finished'
    })
  }

  function show(card: LearningCard, left: number) {
    const asking = drawAsking(card, deck.cards, Math.random)
    question.value = { card, ...asking, prompt: card.translation, token: newToken() }
    remaining.value = left
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
        record(asked.card.id, review.isCorrect, schedule.state)
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

  /** Count an answer that reached the server. One the server never took is not part of what the session achieved. */
  function record(cardId: number, correct: boolean, state: string) {
    if (state === 'review') graduatedIds.add(cardId)
    else graduatedIds.delete(cardId)
    outcome.value = {
      correct: outcome.value.correct + (correct ? 1 : 0),
      wrong: outcome.value.wrong + (correct ? 0 : 1),
      graduated: graduatedIds.size,
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

  return {
    phase,
    loadError,
    question,
    verdict,
    saveState,
    saveFailure,
    remaining,
    waitingToAdvance,
    outcome,
    start,
    submit,
    advance,
    retrySave,
  }
})
