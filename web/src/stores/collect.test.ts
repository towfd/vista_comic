import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/client'
import type { LearningCard } from '../api/types'
import { SOURCE_TEXT_LIMIT, useCollectStore } from './collect'
import { useDeckStore } from './deck'

const api = vi.hoisted(() => ({ createCard: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, createCard: api.createCard }
})

function card(id: number, sourceText: string, translation = '意思'): LearningCard {
  return {
    id,
    sourceText,
    translation,
    kind: 'word',
    state: 'new',
    ladderStage: 1,
    learningStep: null,
    previousStage: null,
    introducedOn: null,
    dueAt: '2026-08-31T12:00:00+00:00',
    createdAt: '2026-08-31T12:00:00+00:00',
  }
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

/** The panel open in a chapter, on page 7. */
function reading() {
  const collect = useCollectStore()
  collect.enter('comic-a', 'chapter-1')
  collect.setCurrentPage(7)
  collect.openPanel()
  return collect
}

/** The panel with a whole card typed, ready to add. */
function typed(sourceText = 'xin chào', translation = '你好') {
  const collect = reading()
  collect.setSourceText(sourceText)
  collect.setTranslation(translation)
  return collect
}

beforeEach(() => {
  setActivePinia(createPinia())
  api.createCard.mockReset().mockImplementation(async (draft: { sourceText: string }) => ({
    card: card(1, draft.sourceText),
    created: true,
  }))
})

describe('the collecting panel', () => {
  it('is collapsed and empty when a chapter opens', () => {
    const collect = useCollectStore()
    collect.enter('comic-a', 'chapter-1')
    expect(collect.open).toBe(false)
    expect(collect.sourceText).toBe('')
    expect(collect.translation).toBe('')
    expect(collect.page).toBeNull()
  })

  it('opens when asked', () => {
    expect(reading().open).toBe(true)
  })

  it('discards everything when collapsed', () => {
    const collect = typed()
    collect.collapse()
    expect(collect.open).toBe(false)
    collect.openPanel()
    expect(collect.sourceText).toBe('')
    expect(collect.translation).toBe('')
    expect(collect.page).toBeNull()
  })

  it('discards what was typed when the reader moves to another chapter', () => {
    const collect = typed()
    collect.enter('comic-a', 'chapter-2')
    expect(collect.open).toBe(false)
    expect(collect.sourceText).toBe('')
  })
})

describe('the page a card records', () => {
  it('is not fixed before anything is typed', () => {
    expect(reading().page).toBeNull()
  })

  it('is fixed when the reader starts typing the source text', () => {
    const collect = reading()
    collect.setSourceText('x')
    expect(collect.page).toBe(7)
  })

  it('holds while the reader scrolls on mid-card', () => {
    const collect = reading()
    collect.setSourceText('x')
    collect.setCurrentPage(9)
    collect.setSourceText('xin')
    collect.setTranslation('請')
    expect(collect.page).toBe(7)
  })

  it('is released when the source text is emptied, and taken afresh from the page then current', () => {
    const collect = reading()
    collect.setSourceText('x')
    collect.setCurrentPage(9)
    collect.setSourceText('')
    expect(collect.page).toBeNull()
    collect.setSourceText('y')
    expect(collect.page).toBe(9)
  })

  it('is not fixed by typing the translation first', () => {
    const collect = reading()
    collect.setTranslation('你好')
    expect(collect.page).toBeNull()
  })

  it('is released by a collapse', () => {
    const collect = typed()
    collect.setCurrentPage(9)
    collect.collapse()
    collect.openPanel()
    collect.setSourceText('y')
    expect(collect.page).toBe(9)
  })
})

describe('when a card can be added', () => {
  it('can once both fields hold something', () => {
    expect(typed().canAdd).toBe(true)
  })

  it.each([
    ['an empty source text', '', '你好'],
    ['a source text of spaces', '   ', '你好'],
    ['an empty translation', 'xin chào', ''],
    ['a translation of spaces', 'xin chào', ' \n '],
  ])('cannot with %s', async (_name, sourceText, translation) => {
    const collect = typed(sourceText, translation)
    expect(collect.canAdd).toBe(false)
    await collect.add('word')
    expect(api.createCard).not.toHaveBeenCalled()
  })

  it('cannot with a source text over the limit', () => {
    expect(typed('a'.repeat(SOURCE_TEXT_LIMIT + 1)).canAdd).toBe(false)
    expect(typed('a'.repeat(SOURCE_TEXT_LIMIT)).canAdd).toBe(true)
  })

  it('cannot before any page has been seen', () => {
    const collect = useCollectStore()
    collect.enter('comic-a', 'chapter-1')
    collect.openPanel()
    collect.setSourceText('xin chào')
    collect.setTranslation('你好')
    expect(collect.canAdd).toBe(false)
  })

  it('cannot while a card is being saved, and a second press sends nothing', async () => {
    const slow = deferred<{ card: LearningCard; created: boolean }>()
    api.createCard.mockReturnValue(slow.promise)
    const collect = typed()
    const adding = collect.add('word')
    expect(collect.saving).toBe(true)
    expect(collect.canAdd).toBe(false)
    await collect.add('sentence')
    expect(api.createCard).toHaveBeenCalledTimes(1)
    slow.resolve({ card: card(1, 'xin chào'), created: true })
    await adding
    expect(collect.saving).toBe(false)
  })
})

describe('adding a card', () => {
  it('sends the line with its kind, its chapter and the fixed page', async () => {
    const collect = typed('  xin chào ', ' 你好  ')
    collect.setCurrentPage(9)
    await collect.add('sentence')
    expect(api.createCard).toHaveBeenCalledWith({
      sourceText: 'xin chào',
      translation: '你好',
      kind: 'sentence',
      comicId: 'comic-a',
      chapterId: 'chapter-1',
      pageNumber: 7,
    })
  })

  it('sends the kind of the button pressed', async () => {
    await typed().add('word')
    expect(api.createCard.mock.calls[0]![0]).toMatchObject({ kind: 'word' })
  })

  it('clears and collapses once a new card is saved, and names the line added', async () => {
    const collect = typed()
    await collect.add('word')
    expect(collect.open).toBe(false)
    expect(collect.sourceText).toBe('')
    expect(collect.translation).toBe('')
    expect(collect.page).toBeNull()
    expect(collect.added).toBe('xin chào')
  })

  it('puts the new card in the deck', async () => {
    await typed().add('word')
    expect(useDeckStore().cards.map((c) => c.sourceText)).toEqual(['xin chào'])
  })

  it('lets the confirmation be dismissed, and drops it when the panel is opened again', async () => {
    const collect = typed()
    await collect.add('word')
    collect.dismissAdded()
    expect(collect.added).toBeNull()

    collect.openPanel()
    collect.setSourceText('cảm ơn')
    collect.setTranslation('謝謝')
    await collect.add('word')
    expect(collect.added).toBe('cảm ơn')
    collect.openPanel()
    expect(collect.added).toBeNull()
  })
})

describe('a line already in the deck', () => {
  beforeEach(() => {
    api.createCard.mockResolvedValue({ card: card(4, 'Xin chào', '哈囉'), created: false })
  })

  it('keeps the panel open with the text as typed, and confirms nothing', async () => {
    const collect = typed()
    await collect.add('word')
    expect(collect.open).toBe(true)
    expect(collect.sourceText).toBe('xin chào')
    expect(collect.translation).toBe('你好')
    expect(collect.added).toBeNull()
  })

  it('says so, with the card the deck holds', async () => {
    const collect = typed()
    await collect.add('word')
    expect(collect.notice).toEqual({ kind: 'exists', card: card(4, 'Xin chào', '哈囉') })
  })

  it('puts that card in the deck, so one deleted here earlier is back', async () => {
    await typed().add('word')
    expect(useDeckStore().cards.map((c) => c.id)).toEqual([4])
  })

  it('stops saying so once the reader edits either field', async () => {
    const collect = typed()
    await collect.add('word')
    collect.setTranslation('你好啊')
    expect(collect.notice).toBeNull()
  })

  it('says so again for the other button: the card it holds is still the one shown', async () => {
    const collect = typed()
    await collect.add('word')
    await collect.add('sentence')
    expect(collect.notice).toEqual({ kind: 'exists', card: card(4, 'Xin chào', '哈囉') })
    expect(useDeckStore().cards).toHaveLength(1)
  })

  it('becomes an ordinary add once the text is changed to a line the deck does not have', async () => {
    const collect = typed()
    await collect.add('word')
    api.createCard.mockResolvedValue({ card: card(5, 'xin chào bạn'), created: true })
    collect.setSourceText('xin chào bạn')
    await collect.add('word')
    expect(collect.open).toBe(false)
    expect(collect.added).toBe('xin chào bạn')
  })
})

describe('a save that fails', () => {
  it('keeps the panel open with the text as typed, and says why', async () => {
    api.createCard.mockRejectedValue(new ApiError('unavailable', 'down'))
    const collect = typed()
    await collect.add('word')
    expect(collect.open).toBe(true)
    expect(collect.sourceText).toBe('xin chào')
    expect(collect.translation).toBe('你好')
    expect(collect.page).toBe(7)
    expect(collect.notice).toEqual({ kind: 'failed', error: 'unavailable' })
    expect(collect.added).toBeNull()
    expect(collect.saving).toBe(false)
  })

  it.each(['auth', 'unavailable', 'unexpected'] as const)('tells a failure of kind %s apart', async (kind) => {
    api.createCard.mockRejectedValue(new ApiError(kind, 'no'))
    const collect = typed()
    await collect.add('word')
    expect(collect.notice).toEqual({ kind: 'failed', error: kind })
  })

  it('reports a failure that is not the API\'s as unexpected', async () => {
    api.createCard.mockRejectedValue(new Error('boom'))
    const collect = typed()
    await collect.add('word')
    expect(collect.notice).toEqual({ kind: 'failed', error: 'unexpected' })
  })

  it('sends the same card again on a retry, so it cannot become a second one', async () => {
    api.createCard.mockRejectedValueOnce(new ApiError('unavailable', 'down'))
    const collect = typed()
    collect.setCurrentPage(9)
    await collect.add('word')
    await collect.add('word')
    expect(api.createCard.mock.calls[1]![0]).toEqual(api.createCard.mock.calls[0]![0])
  })

  it('succeeds on pressing again', async () => {
    api.createCard.mockRejectedValueOnce(new ApiError('unavailable', 'down'))
    const collect = typed()
    await collect.add('word')
    await collect.add('word')
    expect(collect.open).toBe(false)
    expect(collect.added).toBe('xin chào')
    expect(collect.notice).toBeNull()
  })

  it('stops saying so once the reader edits either field', async () => {
    api.createCard.mockRejectedValue(new ApiError('auth', 'refused'))
    const collect = typed()
    await collect.add('word')
    collect.setSourceText('xin chào!')
    expect(collect.notice).toBeNull()
  })
})

describe('an answer that arrives after the panel has gone', () => {
  it('does not reopen a collapsed panel or clear what was typed since, but the card is in the deck', async () => {
    const slow = deferred<{ card: LearningCard; created: boolean }>()
    api.createCard.mockReturnValue(slow.promise)
    const collect = typed()
    const adding = collect.add('word')
    collect.collapse()
    collect.openPanel()
    collect.setSourceText('cảm ơn')
    slow.resolve({ card: card(1, 'xin chào'), created: true })
    await adding
    expect(collect.open).toBe(true)
    expect(collect.sourceText).toBe('cảm ơn')
    expect(useDeckStore().cards.map((c) => c.id)).toEqual([1])
  })

  it('raises no already-collected notice on a panel reopened since', async () => {
    const slow = deferred<{ card: LearningCard; created: boolean }>()
    api.createCard.mockReturnValue(slow.promise)
    const collect = typed()
    const adding = collect.add('word')
    collect.collapse()
    collect.openPanel()
    slow.resolve({ card: card(4, 'Xin chào', '哈囉'), created: false })
    await adding
    expect(collect.notice).toBeNull()
    expect(useDeckStore().cards.map((c) => c.id)).toEqual([4])
  })

  it('raises no notice in the chapter the reader has moved to', async () => {
    const slow = deferred<{ card: LearningCard; created: boolean }>()
    api.createCard.mockReturnValue(slow.promise)
    const collect = typed()
    const adding = collect.add('word')
    collect.enter('comic-a', 'chapter-2')
    slow.reject(new ApiError('unavailable', 'down'))
    await adding
    expect(collect.notice).toBeNull()
    expect(collect.open).toBe(false)
  })
})
