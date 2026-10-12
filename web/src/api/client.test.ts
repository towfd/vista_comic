import { describe, expect, it, vi } from 'vitest'
import {
  ApiError,
  REQUEST_TIMEOUT_MS,
  deleteCard,
  resetCard,
  updateCard,
  fetchCards,
  fetchChapter,
  fetchComic,
  fetchComics,
  fetchStudySettings,
  getJson,
  recordReview,
  saveProgress,
  saveStudySettings,
  toMediaPath,
  type Fetcher,
} from './client'

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

const respondWith = (response: Response | (() => never)): Fetcher => async () =>
  typeof response === 'function' ? response() : response

async function errorKind(promise: Promise<unknown>): Promise<string> {
  try {
    await promise
  } catch (error) {
    if (error instanceof ApiError) return error.kind
    throw error
  }
  throw new Error('expected the request to fail')
}

describe('toMediaPath', () => {
  it('reduces an absolute backend URL to its path', () => {
    expect(toMediaPath('https://api.vistabanana.com/media/abc/def/3')).toBe('/media/abc/def/3')
  })

  it('keeps a query string', () => {
    expect(toMediaPath('https://api.vistabanana.com/media/abc/cover?v=2')).toBe('/media/abc/cover?v=2')
  })

  it('leaves an already-relative path alone', () => {
    expect(toMediaPath('/media/abc/cover')).toBe('/media/abc/cover')
  })
})

describe('fetchComics', () => {
  it('decodes the library and rewrites every cover to a path', async () => {
    const comics = await fetchComics(
      respondWith(
        json([
          { id: 'a', title: 'One', coverUrl: 'https://api.vistabanana.com/media/a/cover', chapterCount: 3, continueChapterId: 'c1' },
          { id: 'b', title: 'Two', coverUrl: 'https://api.vistabanana.com/media/b/cover', chapterCount: 1, continueChapterId: 'c2' },
        ]),
      ),
    )
    expect(comics.map((c) => c.coverUrl)).toEqual(['/media/a/cover', '/media/b/cover'])
    expect(comics[0]?.title).toBe('One')
  })

  it('returns an empty list as empty, not as an error', async () => {
    expect(await fetchComics(respondWith(json([])))).toEqual([])
  })
})

describe('getJson error shaping', () => {
  it('reports a Cloudflare login redirect as an auth failure', async () => {
    // What fetch returns for a redirect under redirect: 'manual' in a browser.
    const redirect = Object.assign(new Response(null, { status: 200 }), {})
    Object.defineProperty(redirect, 'type', { value: 'opaqueredirect' })
    Object.defineProperty(redirect, 'status', { value: 0 })
    expect(await errorKind(getJson('/comics', respondWith(redirect)))).toBe('auth')
  })

  it('reports a plain 302 as an auth failure', async () => {
    const response = new Response(null, { status: 302, headers: { location: 'https://x.cloudflareaccess.com/login' } })
    expect(await errorKind(getJson('/comics', respondWith(response)))).toBe('auth')
  })

  it('reports a 200 login page served as HTML as an auth failure, not a parse error', async () => {
    const page = new Response('<html>Sign in</html>', { status: 200, headers: { 'content-type': 'text/html' } })
    expect(await errorKind(getJson('/comics', respondWith(page)))).toBe('auth')
  })

  it('reports 403 as an auth failure', async () => {
    expect(await errorKind(getJson('/comics', respondWith(json({}, 403))))).toBe('auth')
  })

  it('reports a thrown fetch as unavailable', async () => {
    const fail = (() => {
      throw new TypeError('Failed to fetch')
    }) as () => never
    expect(await errorKind(getJson('/comics', respondWith(fail)))).toBe('unavailable')
  })

  it('reports a proxy or server error as unavailable', async () => {
    expect(await errorKind(getJson('/comics', respondWith(json({}, 502))))).toBe('unavailable')
  })

  it('reports 404 as notFound', async () => {
    expect(await errorKind(getJson('/comics/nope', respondWith(json({ detail: 'Comic not found' }, 404))))).toBe('notFound')
  })
})

describe('fetchComic', () => {
  const detail = {
    id: 'a',
    title: 'One',
    coverUrl: 'https://api.vistabanana.com/media/a/cover',
    chapters: [
      { id: 'c1', number: 1, title: 'Chapter 1', pageCount: 30, coverUrl: 'https://api.vistabanana.com/media/a/c1/cover', readState: 'read' },
      { id: 'c2', number: 2, title: 'Chapter 2', pageCount: 28, coverUrl: 'https://api.vistabanana.com/media/a/c2/cover', readState: 'unread' },
    ],
  }

  it('rewrites the comic cover and every chapter cover to paths', async () => {
    const comic = await fetchComic('a', respondWith(json(detail)))
    expect(comic.coverUrl).toBe('/media/a/cover')
    expect(comic.chapters.map((c) => c.coverUrl)).toEqual(['/media/a/c1/cover', '/media/a/c2/cover'])
  })

  it('keeps chapters in the order the backend sent them', async () => {
    const comic = await fetchComic('a', respondWith(json(detail)))
    expect(comic.chapters.map((c) => c.number)).toEqual([1, 2])
  })

  it('requests the comic by an encoded id', async () => {
    let requested = ''
    await fetchComic('a/b', async (input) => {
      requested = input
      return json(detail)
    })
    expect(requested).toBe('/comics/a%2Fb')
  })

  it('decodes continueChapterId when the backend sends it', async () => {
    const comic = await fetchComic('a', respondWith(json({ ...detail, continueChapterId: 'c2' })))
    expect(comic.continueChapterId).toBe('c2')
  })

  it('decodes a response without continueChapterId (backend not yet deployed)', async () => {
    const comic = await fetchComic('a', respondWith(json(detail)))
    expect(comic.continueChapterId).toBeUndefined()
    expect(comic.chapters).toHaveLength(2)
  })

  it('reports an unknown comic as notFound', async () => {
    expect(await errorKind(fetchComic('nope', respondWith(json({ detail: 'Comic not found' }, 404))))).toBe('notFound')
  })
})

describe('fetchChapter', () => {
  const detail = {
    id: 'c1',
    number: 1,
    title: 'Chapter 1',
    pages: [
      'https://api.vistabanana.com/media/a/c1/1',
      'https://api.vistabanana.com/media/a/c1/2',
      'https://api.vistabanana.com/media/a/c1/3',
    ],
    lastReadPage: 2,
  }

  it('rewrites every page to a path, keeping reading order', async () => {
    const chapter = await fetchChapter('a', 'c1', respondWith(json(detail)))
    expect(chapter.pages).toEqual(['/media/a/c1/1', '/media/a/c1/2', '/media/a/c1/3'])
  })

  it('requests the chapter by encoded ids', async () => {
    let requested = ''
    await fetchChapter('a b', 'c/1', async (input) => {
      requested = input
      return json(detail)
    })
    expect(requested).toBe('/comics/a%20b/chapters/c%2F1')
  })

  it('reports an unknown chapter as notFound', async () => {
    expect(await errorKind(fetchChapter('a', 'nope', respondWith(json({ detail: 'Chapter not found' }, 404))))).toBe('notFound')
  })
})

describe('saveProgress', () => {
  const saved = { comicId: 'a', chapterId: 'c1', lastPage: 12, pageCount: 30, updatedAt: '2026-10-06T00:00:00Z' }

  function capture() {
    const seen: { input: string; init?: RequestInit } = { input: '' }
    const fetcher: Fetcher = async (input, init) => {
      seen.input = input
      seen.init = init
      return json(saved)
    }
    return { seen, fetcher }
  }

  it('PUTs { lastPage } as JSON, with redirects kept manual', async () => {
    const { seen, fetcher } = capture()
    const result = await saveProgress('a', 'c1', 12, {}, fetcher)
    expect(seen.init?.method).toBe('PUT')
    expect(seen.init?.redirect).toBe('manual')
    expect(new Headers(seen.init?.headers).get('content-type')).toBe('application/json')
    expect(JSON.parse(String(seen.init?.body))).toEqual({ lastPage: 12 })
    expect(seen.init?.keepalive).toBeUndefined()
    expect(result).toEqual(saved)
  })

  it('targets the progress path by encoded ids', async () => {
    const { seen, fetcher } = capture()
    await saveProgress('a b', 'c/1', 3, {}, fetcher)
    expect(seen.input).toBe('/comics/a%20b/chapters/c%2F1/progress')
  })

  it('passes keepalive through when asked', async () => {
    const { seen, fetcher } = capture()
    await saveProgress('a', 'c1', 12, { keepalive: true }, fetcher)
    expect(seen.init?.keepalive).toBe(true)
  })

  it('reports an Access redirect as an auth failure', async () => {
    const response = new Response(null, { status: 302, headers: { location: 'https://x.cloudflareaccess.com/login' } })
    expect(await errorKind(saveProgress('a', 'c1', 12, {}, respondWith(response)))).toBe('auth')
  })

  it('reports a progress store outage (503) as unavailable', async () => {
    expect(await errorKind(saveProgress('a', 'c1', 12, {}, respondWith(json({ detail: 'down' }, 503))))).toBe('unavailable')
  })

  it('reports an out-of-range page (422) as unexpected', async () => {
    expect(await errorKind(saveProgress('a', 'c1', 99, {}, respondWith(json({ detail: 'out of range' }, 422))))).toBe('unexpected')
  })
})

describe('fetchCards', () => {
  const raw = (extra: object = {}) => ({
    id: 7,
    sourceText: 'Tôi không biết',
    translation: '我不知道',
    kind: 'sentence',
    state: 'review',
    ladderStage: 2,
    learningStep: null,
    previousStage: null,
    introducedOn: '2026-08-30',
    dueAt: '2026-08-31T20:00:00+00:00',
    createdAt: '2026-07-29T22:20:10.081902+00:00',
    ...extra,
  })

  it('asks for the deck and decodes a card', async () => {
    let asked = ''
    const cards = await fetchCards(async (path) => {
      asked = path
      return json([raw()])
    })
    expect(asked).toBe('/cards')
    expect(cards[0]).toMatchObject({ id: 7, sourceText: 'Tôi không biết', kind: 'sentence', state: 'review', introducedOn: '2026-08-30' })
  })

  it('returns an empty deck as empty, not as an error', async () => {
    expect(await fetchCards(respondWith(json([])))).toEqual([])
  })

  it('reads a state it does not know as new, and a kind it does not know as none', async () => {
    const cards = await fetchCards(respondWith(json([raw({ state: 'suspended', kind: 'phrase' }), raw({ kind: null })])))
    expect(cards.map((c) => [c.state, c.kind])).toEqual([
      ['new', null],
      ['review', null],
    ])
  })

  it('classifies failures as every other read does', async () => {
    expect(await errorKind(fetchCards(respondWith(json({}, 503))))).toBe('unavailable')
    expect(await errorKind(fetchCards(respondWith(json({}, 403))))).toBe('auth')
    expect(await errorKind(fetchCards(respondWith(new Response('<html>', { status: 200, headers: { 'content-type': 'text/html' } }))))).toBe('auth')
    expect(
      await errorKind(
        fetchCards(
          respondWith(() => {
            throw new TypeError('offline')
          }),
        ),
      ),
    ).toBe('unavailable')
  })
})

describe('fetchStudySettings', () => {
  it('asks for the settings and returns both fields', async () => {
    let asked = ''
    const settings = await fetchStudySettings(async (path) => {
      asked = path
      return json({ learningSteps: [5, 7, 10], newCardsPerDay: 15 })
    })
    expect(asked).toBe('/study/settings')
    expect(settings).toEqual({ learningSteps: [5, 7, 10], newCardsPerDay: 15 })
  })

  it('reports a missing route as not found', async () => {
    expect(await errorKind(fetchStudySettings(respondWith(json({}, 404))))).toBe('notFound')
  })
})

describe('recordReview', () => {
  const review = {
    questionType: 'sentence_typed' as const,
    isCorrect: true,
    clientToken: 'token-1',
    localDate: '2026-08-31',
    answeredAt: '2026-08-31T12:00:00.000Z',
    context: 'review' as const,
  }
  const outcome = {
    review: { id: 1, cardId: 7, questionType: 'sentence_typed', isCorrect: true, reviewedAt: '2026-08-31T12:00:00+00:00' },
    state: 'review',
    ladderStage: 3,
    introducedOn: '2026-08-01',
    dueAt: '2026-09-07T20:00:00+00:00',
    intervalChanged: true,
  }

  it("posts the review to the card's own route as JSON", async () => {
    let seen: { path: string; init?: RequestInit } | undefined
    await recordReview(7, review, async (path, init) => {
      seen = { path, init }
      return json(outcome, 201)
    })
    expect(seen?.path).toBe('/cards/7/reviews')
    expect(seen?.init?.method).toBe('POST')
    expect(new Headers(seen?.init?.headers).get('content-type')).toBe('application/json')
    expect(JSON.parse(String(seen?.init?.body))).toEqual(review)
  })

  it("returns the card's scheduling block and nothing else, with absent fields as null", async () => {
    expect(await recordReview(7, review, respondWith(json(outcome, 201)))).toEqual({
      state: 'review',
      learningStep: null,
      ladderStage: 3,
      previousStage: null,
      introducedOn: '2026-08-01',
      dueAt: '2026-09-07T20:00:00+00:00',
    })
  })

  it('reports a deleted card as not found, and a refused body as unexpected', async () => {
    expect(await errorKind(recordReview(7, review, respondWith(json({}, 404))))).toBe('notFound')
    expect(await errorKind(recordReview(7, review, respondWith(json({}, 422))))).toBe('unexpected')
  })

  it('reports an outage and an Access refusal as every other request does', async () => {
    expect(await errorKind(recordReview(7, review, respondWith(json({}, 503))))).toBe('unavailable')
    expect(await errorKind(recordReview(7, review, respondWith(new Response('<html>', { status: 200, headers: { 'content-type': 'text/html' } }))))).toBe('auth')
  })
})

describe('request timeout', () => {
  /** A connection that never answers, and gives up only when told to. */
  const hanging: Fetcher = (_path, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')))
    })

  it('gives up on a request that never answers and reports the backend unavailable', async () => {
    vi.useFakeTimers()
    try {
      const outcome = errorKind(fetchCards(hanging))
      await vi.advanceTimersByTimeAsync(REQUEST_TIMEOUT_MS)
      expect(await outcome).toBe('unavailable')
    } finally {
      vi.useRealTimers()
    }
  })

  it('does not give up before the limit', async () => {
    vi.useFakeTimers()
    try {
      let settled = false
      const outcome = fetchCards(hanging).catch(() => {
        settled = true
      })
      await vi.advanceTimersByTimeAsync(REQUEST_TIMEOUT_MS - 1)
      expect(settled).toBe(false)
      await vi.advanceTimersByTimeAsync(1)
      await outcome
      expect(settled).toBe(true)
    } finally {
      vi.useRealTimers()
    }
  })

  it('leaves no timer running once a request has answered', async () => {
    vi.useFakeTimers()
    try {
      await fetchCards(respondWith(json([])))
      expect(vi.getTimerCount()).toBe(0)
    } finally {
      vi.useRealTimers()
    }
  })
})

describe('saveStudySettings', () => {
  const settings = { learningSteps: [1, 10], newCardsPerDay: 5 }

  it('puts both fields and returns what the server saved', async () => {
    let seen: { path: string; init?: RequestInit } | undefined
    const saved = await saveStudySettings(settings, async (path, init) => {
      seen = { path, init }
      return json(settings)
    })
    expect(seen?.path).toBe('/study/settings')
    expect(seen?.init?.method).toBe('PUT')
    expect(new Headers(seen?.init?.headers).get('content-type')).toBe('application/json')
    expect(JSON.parse(String(seen?.init?.body))).toEqual(settings)
    expect(saved).toEqual(settings)
  })

  it('reports a refused value as unexpected and an outage as unavailable', async () => {
    expect(await errorKind(saveStudySettings(settings, respondWith(json({}, 422))))).toBe('unexpected')
    expect(await errorKind(saveStudySettings(settings, respondWith(json({}, 503))))).toBe('unavailable')
  })
})

describe('fixing a card', () => {
  const stored = {
    id: 7,
    sourceText: 'đường',
    translation: '路',
    kind: 'word',
    state: 'review',
    ladderStage: 2,
    learningStep: null,
    previousStage: null,
    introducedOn: '2026-08-30',
    dueAt: '2026-08-31T20:00:00+00:00',
    createdAt: '2026-07-29T22:20:10+00:00',
  }
  const capture = (response: Response) => {
    const seen: { path?: string; init?: RequestInit } = {}
    const fetcher: Fetcher = async (path, init) => {
      seen.path = path
      seen.init = init
      return response
    }
    return { seen, fetcher }
  }

  it('patches only what is being corrected and returns the card', async () => {
    const { seen, fetcher } = capture(json({ ...stored, translation: '道路' }))
    const card = await updateCard(7, { translation: '道路' }, fetcher)
    expect(seen.path).toBe('/cards/7')
    expect(seen.init?.method).toBe('PATCH')
    expect(JSON.parse(String(seen.init?.body))).toEqual({ translation: '道路' })
    expect(card).toMatchObject({ id: 7, translation: '道路', kind: 'word', state: 'review' })
  })

  it('can send a kind alone, including clearing it', async () => {
    const { seen, fetcher } = capture(json({ ...stored, kind: null }))
    const card = await updateCard(7, { kind: null }, fetcher)
    expect(JSON.parse(String(seen.init?.body))).toEqual({ kind: null })
    expect(card.kind).toBeNull()
  })

  it("resets through the card's own route and returns it as new", async () => {
    const { seen, fetcher } = capture(json({ ...stored, state: 'new', ladderStage: 0, introducedOn: null }))
    const card = await resetCard(7, fetcher)
    expect(seen.path).toBe('/cards/7/reset')
    expect(seen.init?.method).toBe('POST')
    expect(seen.init?.body).toBeUndefined()
    expect(card).toMatchObject({ state: 'new', introducedOn: null })
  })

  it('deletes, and takes an empty 204 as success', async () => {
    const { seen, fetcher } = capture(new Response(null, { status: 204 }))
    await expect(deleteCard(7, fetcher)).resolves.toBeUndefined()
    expect(seen.path).toBe('/cards/7')
    expect(seen.init?.method).toBe('DELETE')
  })

  it("does not take Access's login page for a successful delete", async () => {
    const page = new Response('<html>', { status: 200, headers: { 'content-type': 'text/html' } })
    expect(await errorKind(deleteCard(7, respondWith(page)))).toBe('auth')
  })

  it('reports a card already gone as not found, for each of the three', async () => {
    expect(await errorKind(updateCard(7, { translation: 'x' }, respondWith(json({}, 404))))).toBe('notFound')
    expect(await errorKind(resetCard(7, respondWith(json({}, 404))))).toBe('notFound')
    expect(await errorKind(deleteCard(7, respondWith(json({}, 404))))).toBe('notFound')
  })

  it('reports a refused correction as unexpected and an outage as unavailable', async () => {
    expect(await errorKind(updateCard(7, {}, respondWith(json({}, 422))))).toBe('unexpected')
    expect(await errorKind(deleteCard(7, respondWith(json({}, 503))))).toBe('unavailable')
  })
})
