import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError, type LineAnalysis } from '../api/client'
import { POLL_MS, useAnalysisStore, wordTranslation, type AnalysedBubble } from './analysis'

const api = vi.hoisted(() => ({ requestLineAnalysis: vi.fn(), fetchLineAnalysis: vi.fn() }))

vi.mock('../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../api/client')>()
  return { ...actual, requestLineAnalysis: api.requestLineAnalysis, fetchLineAnalysis: api.fetchLineAnalysis }
})

const BUBBLE: AnalysedBubble = {
  sourceText: 'Anh Dok-ja, viện phí đã thanh toán rồi à?',
  translation: '獨子哥，住院費已經付了嗎？',
  page: 4,
  names: [{ source: 'Dok-ja', target: '獨子' }],
}

const RESULT = {
  words: [{ text: 'viện phí', meaning: '住院費', partOfSpeech: '名詞', hanViet: '院費', note: '' }],
  grammar: '…',
  tone: '…',
}

function analysis(overrides: Partial<LineAnalysis> = {}): LineAnalysis {
  return {
    id: 1,
    status: 'pending',
    model: 'sonnet',
    sourceText: BUBBLE.sourceText,
    translation: BUBBLE.translation,
    failure: null,
    result: null,
    updatedAt: '2026-10-29T12:00:00+00:00',
    ...overrides,
  }
}

const done = (overrides: Partial<LineAnalysis> = {}) => analysis({ status: 'done', result: RESULT, ...overrides })

/** A storage that works, for the tests about remembering the model. */
function memoryStorage() {
  const items = new Map<string, string>()
  return {
    getItem: (key: string) => items.get(key) ?? null,
    setItem: (key: string, value: string) => void items.set(key, value),
  }
}

beforeEach(() => {
  vi.useFakeTimers()
  setActivePinia(createPinia())
  api.requestLineAnalysis.mockReset().mockResolvedValue({ analysis: done() })
  api.fetchLineAnalysis.mockReset()
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('opening the panel for a bubble', () => {
  it('opens and asks for the line with its translation, the model and the names', async () => {
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    expect(store.open).toBe(true)
    expect(store.requesting).toBe(true)
    await vi.runAllTimersAsync()

    expect(api.requestLineAnalysis).toHaveBeenCalledWith({
      sourceText: BUBBLE.sourceText,
      translation: BUBBLE.translation,
      model: 'sonnet',
      names: BUBBLE.names,
    })
    expect(store.requesting).toBe(false)
    expect(store.analysis?.result).toEqual(RESULT)
  })

  it('shows a stored analysis without polling', async () => {
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.runAllTimersAsync()

    expect(api.fetchLineAnalysis).not.toHaveBeenCalled()
  })
})

describe('waiting for a pending analysis', () => {
  it('polls every two seconds until it is done', async () => {
    api.requestLineAnalysis.mockResolvedValue({ analysis: analysis() })
    api.fetchLineAnalysis.mockResolvedValueOnce(analysis()).mockResolvedValueOnce(done())
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)
    expect(store.analysis?.status).toBe('pending')

    await vi.advanceTimersByTimeAsync(POLL_MS)
    expect(api.fetchLineAnalysis).toHaveBeenCalledTimes(1)
    expect(store.analysis?.status).toBe('pending')

    await vi.advanceTimersByTimeAsync(POLL_MS)
    expect(store.analysis?.status).toBe('done')

    await vi.advanceTimersByTimeAsync(POLL_MS * 5)
    expect(api.fetchLineAnalysis).toHaveBeenCalledTimes(2)
  })

  it('stops at a failure and shows it', async () => {
    api.requestLineAnalysis.mockResolvedValue({ analysis: analysis() })
    api.fetchLineAnalysis.mockResolvedValue(analysis({ status: 'failed', failure: 'refused' }))
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(POLL_MS)

    expect(store.analysis?.failure).toBe('refused')
    await vi.advanceTimersByTimeAsync(POLL_MS * 3)
    expect(api.fetchLineAnalysis).toHaveBeenCalledTimes(1)
  })

  it('keeps polling through a connection blip', async () => {
    api.requestLineAnalysis.mockResolvedValue({ analysis: analysis() })
    api.fetchLineAnalysis.mockRejectedValueOnce(new ApiError('unavailable', 'blip')).mockResolvedValueOnce(done())
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(POLL_MS * 2)

    expect(store.analysis?.status).toBe('done')
    expect(store.problem).toBeNull()
  })

  it('stops polling when the panel is closed', async () => {
    api.requestLineAnalysis.mockResolvedValue({ analysis: analysis() })
    api.fetchLineAnalysis.mockResolvedValue(analysis())
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    store.close()
    await vi.advanceTimersByTimeAsync(POLL_MS * 3)

    expect(api.fetchLineAnalysis).not.toHaveBeenCalled()
    expect(store.open).toBe(false)
    expect(store.analysis).toBeNull()
  })

  it('drops an answer that arrives after the panel was closed', async () => {
    let answer!: (value: unknown) => void
    api.requestLineAnalysis.mockReturnValue(new Promise((resolve) => (answer = resolve)))
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    store.close()

    answer({ analysis: done() })
    await vi.advanceTimersByTimeAsync(0)

    expect(store.analysis).toBeNull()
    expect(store.requesting).toBe(false)
  })

  it('reopening the bubble finds the result', async () => {
    api.requestLineAnalysis.mockResolvedValueOnce({ analysis: analysis() }).mockResolvedValueOnce({ analysis: done() })
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)
    store.close()

    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    expect(store.analysis?.result).toEqual(RESULT)
  })
})

describe('failures', () => {
  it('reports a spent daily allowance as capped', async () => {
    api.requestLineAnalysis.mockResolvedValue({ capped: true })
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    expect(store.problem).toBe('capped')
    expect(store.analysis).toBeNull()
  })

  it('reports a request that did not go through by its kind', async () => {
    api.requestLineAnalysis.mockRejectedValue(new ApiError('auth', 'refused'))
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    expect(store.problem).toBe('auth')
    expect(store.requesting).toBe(false)
  })

  it('retry asks again and clears the problem', async () => {
    api.requestLineAnalysis.mockRejectedValueOnce(new ApiError('unavailable', 'down'))
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    store.retry()
    await vi.advanceTimersByTimeAsync(0)

    expect(store.problem).toBeNull()
    expect(store.analysis?.status).toBe('done')
    expect(api.requestLineAnalysis).toHaveBeenCalledTimes(2)
    expect(api.requestLineAnalysis.mock.calls[1]![0]).not.toHaveProperty('refresh')
  })
})

describe('choosing a model', () => {
  it('defaults to Sonnet without storage', () => {
    expect(useAnalysisStore().model).toBe('sonnet')
  })

  it('switching asks for that model and is remembered', async () => {
    const storage = memoryStorage()
    vi.stubGlobal('localStorage', storage)
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)

    store.setModel('fable')
    await vi.advanceTimersByTimeAsync(0)

    expect(api.requestLineAnalysis.mock.calls[1]![0]).toMatchObject({ model: 'fable' })
    expect(storage.getItem('vista.analysisModel')).toBe('fable')

    setActivePinia(createPinia())
    expect(useAnalysisStore().model).toBe('fable')
  })

  it('ignores a remembered value it does not know', () => {
    vi.stubGlobal('localStorage', { getItem: () => 'haiku', setItem: () => {} })
    expect(useAnalysisStore().model).toBe('sonnet')
  })

  it('still switches when storage refuses', async () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('blocked')
      },
      setItem: () => {
        throw new Error('blocked')
      },
    })
    const store = useAnalysisStore()
    store.setModel('opus')
    expect(store.model).toBe('opus')
  })

  it('switching with the panel closed asks for nothing', () => {
    useAnalysisStore().setModel('opus')
    expect(api.requestLineAnalysis).not.toHaveBeenCalled()
  })
})

describe('refreshing', () => {
  it('asks for a new call that replaces the result', async () => {
    const store = useAnalysisStore()
    store.openFor(BUBBLE)
    await vi.advanceTimersByTimeAsync(0)
    api.requestLineAnalysis.mockResolvedValue({ analysis: analysis() })

    store.refresh()
    expect(store.analysis).toBeNull()
    await vi.advanceTimersByTimeAsync(0)

    expect(api.requestLineAnalysis.mock.calls[1]![0]).toMatchObject({ refresh: true })
    expect(store.analysis?.status).toBe('pending')
  })
})

describe('wordTranslation', () => {
  it('puts the characters in brackets after the meaning', () => {
    expect(wordTranslation(RESULT.words[0]!)).toBe('住院費（院費）')
  })

  it('is the meaning alone for a word with no characters', () => {
    expect(wordTranslation({ text: 'à', meaning: '啊', partOfSpeech: '語氣詞', hanViet: '', note: '' })).toBe('啊')
  })
})
