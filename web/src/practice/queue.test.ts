import { afterEach, describe, expect, it } from 'vitest'
import type { CardState, LearningCard, StudySettings } from '../api/types'
import { LEARN_AHEAD_MS, localDay, nextCard, remainingCards, waiting } from './queue'

const NOW = new Date('2026-08-31T12:00:00Z')
const TODAY = '2026-08-31'
const MINUTE = 60 * 1000
const settings = (newCardsPerDay = 15): StudySettings => ({ learningSteps: [5, 7, 10], newCardsPerDay })

/** A card due `dueInMinutes` from NOW (negative: already due). */
function card(id: number, state: CardState, dueInMinutes = 0, extra: Partial<LearningCard> = {}): LearningCard {
  return {
    id,
    sourceText: `text ${id}`,
    translation: `meaning ${id}`,
    kind: 'sentence',
    state,
    ladderStage: 0,
    learningStep: null,
    previousStage: null,
    introducedOn: state === 'new' ? null : '2026-08-01',
    dueAt: new Date(NOW.getTime() + dueInMinutes * MINUTE).toISOString(),
    createdAt: new Date(NOW.getTime() - id * MINUTE).toISOString(),
    ...extra,
  }
}

const next = (deck: LearningCard[], s = settings(), avoiding?: number) => nextCard(deck, s, NOW, TODAY, avoiding)

describe('nextCard order', () => {
  it('asks a learning card due now before a review card due now', () => {
    expect(next([card(1, 'review', -60), card(2, 'learning', -1)]).card?.id).toBe(2)
  })

  it('treats relearning as learning', () => {
    expect(next([card(1, 'review', -60), card(2, 'relearning', -1)]).card?.id).toBe(2)
  })

  it('asks what is due before anything new', () => {
    expect(next([card(1, 'new'), card(2, 'review', -1)]).card?.id).toBe(2)
  })

  it('asks the longest-waiting card of a group first', () => {
    expect(next([card(1, 'review', -5), card(2, 'review', -500), card(3, 'review', -50)]).card?.id).toBe(2)
  })

  it('introduces new cards in the order they were collected', () => {
    // card() makes a higher id older, and the backend lists newest first.
    expect(next([card(1, 'new'), card(2, 'new'), card(3, 'new')]).card?.id).toBe(3)
  })

  it('does not offer a review card that is not due yet', () => {
    expect(next([card(1, 'review', 1)]).empty).toBe('dayIsDone')
  })
})

describe('nextCard and the card just asked', () => {
  it('skips it when the group holds another', () => {
    expect(next([card(1, 'review', -10), card(2, 'review', -5)], settings(), 1).card?.id).toBe(2)
  })

  it('repeats it when it is the only candidate', () => {
    expect(next([card(1, 'review', -10)], settings(), 1).card?.id).toBe(1)
  })

  it('repeats a lone learning card rather than moving on to a review card', () => {
    expect(next([card(1, 'learning', -1), card(2, 'review', -60)], settings(), 1).card?.id).toBe(1)
  })
})

describe("the day's allowance", () => {
  it('introduces nothing once the allowance is spent', () => {
    const deck = [card(1, 'new'), card(2, 'review', 600, { introducedOn: TODAY }), card(3, 'review', 600, { introducedOn: TODAY })]
    expect(next(deck, settings(2)).empty).toBe('dayIsDone')
  })

  it('still has room when only some of it is spent', () => {
    const deck = [card(1, 'new'), card(2, 'review', 600, { introducedOn: TODAY })]
    expect(next(deck, settings(2)).card?.id).toBe(1)
  })

  it('does not count cards introduced on another day', () => {
    const deck = [card(1, 'new'), card(2, 'review', 600, { introducedOn: '2026-08-30' })]
    expect(next(deck, settings(1)).card?.id).toBe(1)
  })

  it('introduces nothing when the allowance is zero', () => {
    expect(next([card(1, 'new')], settings(0)).empty).toBe('dayIsDone')
  })
})

describe('learn-ahead', () => {
  it('offers a learning card due in three minutes when nothing else is waiting', () => {
    expect(next([card(1, 'learning', 3)]).card?.id).toBe(1)
  })

  it('offers one due exactly at the end of the window', () => {
    expect(next([card(1, 'learning', LEARN_AHEAD_MS / MINUTE)]).card?.id).toBe(1)
  })

  it('never offers one due in forty minutes', () => {
    expect(next([card(1, 'learning', 40)]).empty).toBe('dayIsDone')
  })

  it('does not pull one forward while a new card can be introduced', () => {
    expect(next([card(1, 'learning', 3), card(2, 'new')]).card?.id).toBe(2)
  })

  it('does not pull a review card forward', () => {
    expect(next([card(1, 'review', 3)]).empty).toBe('dayIsDone')
  })
})

describe('an empty queue', () => {
  it('says the deck is empty when nothing was ever collected', () => {
    expect(next([]).empty).toBe('deckIsEmpty')
  })

  it('says the day is done when cards exist but none is waiting', () => {
    expect(next([card(1, 'review', 600)]).empty).toBe('dayIsDone')
  })
})

describe('waiting', () => {
  it('splits what is waiting into due, new and in learning', () => {
    const deck = [
      card(1, 'review', -5),
      card(2, 'review', -50),
      card(3, 'review', 600),
      card(4, 'learning', -1),
      card(5, 'relearning', 10),
      card(6, 'learning', 40),
      card(7, 'new'),
      card(8, 'new'),
      card(9, 'new'),
    ]
    expect(waiting(deck, settings(2), NOW, TODAY)).toEqual({ due: 2, fresh: 2, learning: 2 })
  })

  it('caps new cards by the deck when the allowance is larger', () => {
    expect(waiting([card(1, 'new')], settings(20), NOW, TODAY).fresh).toBe(1)
  })

  it('counts a learning card already due once', () => {
    expect(remainingCards([card(1, 'learning', -1)], settings(), NOW, TODAY)).toBe(1)
  })

  it('never goes below zero when more were introduced than the allowance', () => {
    const deck = [card(1, 'new'), card(2, 'review', 600, { introducedOn: TODAY }), card(3, 'review', 600, { introducedOn: TODAY })]
    expect(waiting(deck, settings(1), NOW, TODAY).fresh).toBe(0)
  })

  it('is zero exactly when the queue has nothing to offer', () => {
    const decks: LearningCard[][] = [
      [],
      [card(1, 'review', 600)],
      [card(1, 'review', -1)],
      [card(1, 'learning', 3)],
      [card(1, 'learning', 40)],
      [card(1, 'new')],
      [card(1, 'new'), card(2, 'review', 600, { introducedOn: TODAY })],
      [card(1, 'relearning', -1), card(2, 'new'), card(3, 'review', 600)],
    ]
    for (const allowance of [0, 1, 15]) {
      for (const deck of decks) {
        const s = settings(allowance)
        expect(remainingCards(deck, s, NOW, TODAY) === 0).toBe(nextCard(deck, s, NOW, TODAY).empty !== undefined)
      }
    }
  })

  it('reads timestamps as the backend writes them, with microseconds and an offset', () => {
    const deck = [card(1, 'review', 0, { dueAt: '2026-08-31T11:59:59.081902+00:00' })]
    expect(waiting(deck, settings(), NOW, TODAY).due).toBe(1)
  })
})

describe('localDay', () => {
  const zone = process.env.TZ
  afterEach(() => {
    if (zone === undefined) delete process.env.TZ
    else process.env.TZ = zone
  })

  it('formats the local calendar day with padding', () => {
    expect(localDay(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05')
  })

  it('is the local day, not the UTC one, in the hours they differ', () => {
    process.env.TZ = 'Asia/Taipei'
    // 01:00 on the 13th in Taipei; still the 12th in UTC.
    const moment = new Date('2026-10-12T17:00:00Z')
    expect(moment.toISOString().slice(0, 10)).toBe('2026-10-12')
    expect(localDay(moment)).toBe('2026-10-13')
  })

  it('does not roll over at 04:00, the hour the server rounds intervals to', () => {
    process.env.TZ = 'Asia/Taipei'
    // 03:00 on the 13th in Taipei: before the scheduling day turns, after the calendar day has.
    expect(localDay(new Date('2026-10-12T19:00:00Z'))).toBe('2026-10-13')
  })
})
