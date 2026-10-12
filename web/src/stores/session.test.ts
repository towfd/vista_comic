import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import type { CardSchedule, CardState, LearningCard } from '../api/types'
import { useDeckStore } from './deck'
import { RETRY_DELAYS_MS, useSessionStore } from './session'

const api = vi.hoisted(() => ({ fetchCards: vi.fn(), fetchStudySettings: vi.fn(), recordReview: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, fetchCards: api.fetchCards, fetchStudySettings: api.fetchStudySettings, recordReview: api.recordReview }
})

const NOW = new Date('2026-08-31T12:00:00Z')
const minutes = (n: number) => new Date(NOW.getTime() + n * 60_000).toISOString()

function card(id: number, state: CardState, dueIn: number, sourceText = `câu ${id}`): LearningCard {
  return {
    id,
    sourceText,
    translation: `meaning ${id}`,
    kind: 'sentence',
    state,
    ladderStage: 1,
    learningStep: null,
    previousStage: null,
    introducedOn: state === 'new' ? null : '2026-08-01',
    dueAt: minutes(dueIn),
    createdAt: minutes(-id),
  }
}

/** Where a review card lands after a correct answer: out of today's queue. */
const promoted: CardSchedule = {
  state: 'review',
  learningStep: null,
  ladderStage: 2,
  previousStage: null,
  introducedOn: '2026-08-01',
  dueAt: minutes(3 * 24 * 60),
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

/** Let the awaits inside the store run. Timers are faked, so this cannot be a timeout. */
const settle = async () => {
  for (let i = 0; i < 5; i++) await Promise.resolve()
}

async function started(deck: LearningCard[]) {
  api.fetchCards.mockResolvedValue(deck)
  const session = useSessionStore()
  await session.start()
  return session
}

beforeEach(() => {
  setActivePinia(createPinia())
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  api.fetchCards.mockReset()
  api.fetchStudySettings.mockReset().mockResolvedValue({ learningSteps: [5, 7, 10], newCardsPerDay: 15 })
  api.recordReview.mockReset().mockResolvedValue(promoted)
  vi.spyOn(console, 'warn').mockImplementation(() => {})
})
afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
})

describe('starting a session', () => {
  it("asks the queue's first card as a translation, prompting with its meaning", async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    expect(session.phase).toBe('asking')
    expect(session.question).toMatchObject({ type: 'sentence_typed', prompt: 'meaning 2' })
    expect(session.question?.card.id).toBe(2)
    expect(session.remaining).toBe(2)
  })

  it('finishes at once when nothing is waiting', async () => {
    const session = await started([card(1, 'review', 600)])
    expect(session.phase).toBe('finished')
    expect(session.question).toBeNull()
  })

  it('reports a deck that cannot be fetched and asks nothing', async () => {
    api.fetchCards.mockRejectedValue(new ApiError('unavailable', 'down'))
    const session = useSessionStore()
    await session.start()
    expect(session.phase).toBe('unavailable')
    expect(session.loadError).toBe('unavailable')
    expect(session.question).toBeNull()
  })

  it('does not fall back to default settings when they cannot be read', async () => {
    api.fetchCards.mockResolvedValue([card(1, 'new', 0)])
    api.fetchStudySettings.mockRejectedValue(new ApiError('unavailable', 'down'))
    const session = useSessionStore()
    await session.start()
    expect(session.phase).toBe('unavailable')
  })

  it('starts again from the server when started twice', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await settle()
    await session.start()
    expect(api.fetchCards).toHaveBeenCalledTimes(2)
    expect(session.verdict).toBeNull()
  })
})

describe('answering', () => {
  it('shows the verdict before the save has returned', async () => {
    const pending = deferred<CardSchedule>()
    api.recordReview.mockReturnValue(pending.promise)
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    expect(session.phase).toBe('feedback')
    expect(session.verdict).toEqual({ correct: true, given: 'câu 1', expected: 'câu 1' })
    expect(session.saveState).toBe('saving')
  })

  it('marks a missing tone wrong and keeps what was typed', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('  cau 1 ')
    expect(session.verdict).toEqual({ correct: false, given: 'cau 1', expected: 'câu 1' })
  })

  it('ignores an empty or blank field', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('')
    session.submit('   ')
    expect(session.phase).toBe('asking')
    expect(api.recordReview).not.toHaveBeenCalled()
  })

  it('ignores a second submission of the same question', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    session.submit('something else')
    expect(api.recordReview).toHaveBeenCalledTimes(1)
    expect(session.verdict?.given).toBe('câu 1')
  })

  it('posts the answer with its type, verdict, token, local date and moment', async () => {
    const session = await started([card(7, 'review', -5)])
    const token = session.question!.token
    session.submit('wrong')
    expect(api.recordReview).toHaveBeenCalledWith(7, {
      questionType: 'sentence_typed',
      isCorrect: false,
      clientToken: token,
      localDate: '2026-08-31',
      answeredAt: NOW.toISOString(),
      context: 'review',
    })
    expect(token.length).toBeGreaterThan(0)
  })

  it('gives each question its own token', async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    const first = session.question!.token
    session.submit('câu 2')
    await settle()
    session.advance()
    expect(session.question!.token).not.toBe(first)
  })
})

describe('moving on', () => {
  it('does not draw the next question until the save has returned', async () => {
    const pending = deferred<CardSchedule>()
    api.recordReview.mockReturnValue(pending.promise)
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    session.advance()
    expect(session.phase).toBe('feedback')
    expect(session.question?.card.id).toBe(2)
    expect(session.waitingToAdvance).toBe(true)

    pending.resolve(promoted)
    await settle()
    expect(session.phase).toBe('asking')
    expect(session.question?.card.id).toBe(1)
    expect(session.waitingToAdvance).toBe(false)
  })

  it('stays on the feedback after the save until the reader moves on', async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    await settle()
    expect(session.saveState).toBe('saved')
    expect(session.phase).toBe('feedback')
    session.advance()
    expect(session.phase).toBe('asking')
    expect(session.verdict).toBeNull()
  })

  it("writes the returned schedule onto the card, so the queue moves by the server's word", async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    await settle()
    const held = useDeckStore().cards.find((c) => c.id === 2)
    expect(held).toMatchObject({ ladderStage: 2, dueAt: promoted.dueAt })
    session.advance()
    expect(session.remaining).toBe(1)
  })

  it('asks a card again when the server keeps it in learning and it is the only one left', async () => {
    api.recordReview.mockResolvedValue({ ...promoted, state: 'relearning', learningStep: 0, dueAt: minutes(5) })
    const session = await started([card(1, 'review', -5)])
    session.submit('wrong')
    await settle()
    session.advance()
    expect(session.phase).toBe('asking')
    expect(session.question?.card.id).toBe(1)
  })

  it('does not ask the card just answered when another of its group is waiting', async () => {
    // Still the longest-waiting review card after the answer, so only the
    // rule against an immediate repeat can put card 1 ahead of it.
    api.recordReview.mockResolvedValue({ ...promoted, dueAt: minutes(-100) })
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('wrong')
    await settle()
    session.advance()
    expect(session.question?.card.id).toBe(1)
  })

  it('finishes when the last answer empties the queue', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await settle()
    session.advance()
    expect(session.phase).toBe('finished')
  })

  it('reads the clock afresh for each question', async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', 30)])
    expect(session.remaining).toBe(1)
    session.submit('câu 1')
    await settle()
    vi.setSystemTime(new Date(NOW.getTime() + 60 * 60_000))
    session.advance()
    expect(session.question?.card.id).toBe(2)
  })

  it('does nothing when asked to move on with no answer given', async () => {
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.advance()
    expect(session.phase).toBe('asking')
    expect(session.question?.card.id).toBe(2)
  })
})

describe('an answer that will not save', () => {
  const down = () => new ApiError('unavailable', 'down')
  const allDelays = RETRY_DELAYS_MS.reduce((sum, ms) => sum + ms, 0)

  it('retries an unreachable backend on its own and saves once it answers', async () => {
    api.recordReview.mockRejectedValueOnce(down()).mockRejectedValueOnce(down()).mockResolvedValue(promoted)
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await settle()
    expect(session.saveState).toBe('saving')
    await vi.advanceTimersByTimeAsync(RETRY_DELAYS_MS[0]! + RETRY_DELAYS_MS[1]!)
    expect(api.recordReview).toHaveBeenCalledTimes(3)
    expect(session.saveState).toBe('saved')
  })

  it('sends the same token, moment and local date on every attempt', async () => {
    api.recordReview.mockRejectedValue(down())
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    // Long enough for the day to have changed by the last attempt.
    vi.setSystemTime(new Date(NOW.getTime() + 13 * 60 * 60_000))
    await vi.advanceTimersByTimeAsync(allDelays)
    session.retrySave()
    await settle()
    const bodies = api.recordReview.mock.calls.map((call) => call[1])
    expect(bodies).toHaveLength(RETRY_DELAYS_MS.length + 2)
    for (const body of bodies) expect(body).toEqual(bodies[0])
    expect(bodies[0]).toMatchObject({ answeredAt: NOW.toISOString(), localDate: '2026-08-31' })
  })

  it('reports the answer unsaved once the automatic attempts are spent, and will not move on', async () => {
    api.recordReview.mockRejectedValue(down())
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    session.advance()
    await vi.advanceTimersByTimeAsync(allDelays)
    expect(api.recordReview).toHaveBeenCalledTimes(RETRY_DELAYS_MS.length + 1)
    expect(session.saveState).toBe('failed')
    expect(session.saveFailure).toBe('unavailable')
    expect(session.waitingToAdvance).toBe(false)
    session.advance()
    expect(session.phase).toBe('feedback')
    expect(session.question?.card.id).toBe(2)
    await vi.advanceTimersByTimeAsync(60_000)
    expect(api.recordReview).toHaveBeenCalledTimes(RETRY_DELAYS_MS.length + 1)
  })

  it('saves on a manual retry and then moves on when asked', async () => {
    api.recordReview.mockRejectedValue(down())
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    await vi.advanceTimersByTimeAsync(allDelays)
    api.recordReview.mockResolvedValue(promoted)
    session.retrySave()
    await settle()
    expect(session.saveState).toBe('saved')
    expect(session.saveFailure).toBeNull()
    session.advance()
    expect(session.question?.card.id).toBe(1)
  })

  it('ignores a manual retry while nothing has failed', async () => {
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await settle()
    session.retrySave()
    await settle()
    expect(api.recordReview).toHaveBeenCalledTimes(1)
  })

  it('drops a card deleted elsewhere and lets the session carry on, with no retry', async () => {
    api.recordReview.mockRejectedValue(new ApiError('notFound', 'gone'))
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    await settle()
    expect(session.saveState).toBe('gone')
    expect(useDeckStore().cards.map((c) => c.id)).toEqual([1])
    await vi.advanceTimersByTimeAsync(allDelays)
    expect(api.recordReview).toHaveBeenCalledTimes(1)
    session.advance()
    expect(session.question?.card.id).toBe(1)
  })

  it('moves on by itself from a deleted card when the reader had already asked to', async () => {
    const pending = deferred<CardSchedule>()
    api.recordReview.mockReturnValue(pending.promise)
    const session = await started([card(1, 'review', -5), card(2, 'review', -50)])
    session.submit('câu 2')
    session.advance()
    pending.reject(new ApiError('notFound', 'gone'))
    await settle()
    expect(session.phase).toBe('asking')
    expect(session.question?.card.id).toBe(1)
  })

  it('says a lapsed sign-in is one, without retrying', async () => {
    api.recordReview.mockRejectedValue(new ApiError('auth', 'refused'))
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await vi.advanceTimersByTimeAsync(allDelays)
    expect(api.recordReview).toHaveBeenCalledTimes(1)
    expect(session.saveState).toBe('failed')
    expect(session.saveFailure).toBe('auth')
  })

  it('shows any other refusal as unsaved, without retrying on its own', async () => {
    api.recordReview.mockRejectedValue(new ApiError('unexpected', 'status 422'))
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await vi.advanceTimersByTimeAsync(allDelays)
    expect(api.recordReview).toHaveBeenCalledTimes(1)
    expect(session.saveFailure).toBe('unexpected')
  })

  it('abandons its retries when the session is started again', async () => {
    api.recordReview.mockRejectedValue(down())
    const session = await started([card(1, 'review', -5)])
    session.submit('câu 1')
    await settle()
    await session.start()
    await vi.advanceTimersByTimeAsync(allDelays)
    expect(api.recordReview).toHaveBeenCalledTimes(1)
    expect(session.saveState).toBeNull()
    expect(session.phase).toBe('asking')
  })
})
