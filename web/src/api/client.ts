import type {
  CardSchedule,
  CardState,
  ChapterDetail,
  ComicDetail,
  ComicSummary,
  LearningCard,
  ProgressSaved,
  ReviewRequest,
  StudySettings,
} from './types'

/**
 * Why a request failed, in the terms the screens need to tell apart.
 *
 * - `auth`: Cloudflare Access refused the request -- the Service Token in
 *   web/.env is missing or wrong. Access answers with a redirect to its login
 *   page rather than an error status, so this is recognised by the redirect
 *   (or by a response that is not the API's JSON), never by a status code.
 * - `unavailable`: the backend could not be reached -- no network, the proxy
 *   could not connect upstream, or the server errored.
 * - `notFound`: the API answered 404 for this id.
 * - `unexpected`: anything else; carries the detail for debugging.
 */
export type ApiErrorKind = 'auth' | 'unavailable' | 'notFound' | 'unexpected'

export class ApiError extends Error {
  constructor(
    readonly kind: ApiErrorKind,
    detail: string,
  ) {
    super(detail)
    this.name = 'ApiError'
  }
}

/**
 * Reduce a media URL to its path so it is fetched through the dev proxy.
 *
 * The backend builds absolute URLs from the host it was reached on, which
 * through the proxy is api.vistabanana.com. Handed to an <img> as-is, the
 * browser would go straight to Cloudflare without the token and be refused --
 * the library would render with every image broken. This is the one place the
 * design can fail silently, so every media URL passes through here.
 */
export function toMediaPath(url: string): string {
  if (url.startsWith('/')) return url
  const parsed = new URL(url)
  return parsed.pathname + parsed.search
}

/**
 * How long a request may take before it counts as the backend being
 * unreachable. Without it a request into a dead connection never settles, and
 * a session waiting on a save would wait for ever.
 */
export const REQUEST_TIMEOUT_MS = 10_000

/** The fetch implementation, injectable so tests never touch the network. */
export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>

export async function getJson<T>(path: string, fetcher: Fetcher = fetch): Promise<T> {
  return requestJson<T>(path, { headers: { Accept: 'application/json' } }, fetcher)
}

/**
 * One request to the API, with the error shaping every screen relies on.
 * Shared by reads and the progress write so an Access refusal on a PUT is
 * recognised exactly as it is on a GET.
 */
async function requestJson<T>(path: string, init: RequestInit, fetcher: Fetcher): Promise<T> {
  return readJson<T>(await send(path, init, fetcher))
}

/** The JSON body of an answer `send` let through; split out for the caller that also needs its status. */
async function readJson<T>(response: Response): Promise<T> {
  const contentType = response.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    // A 200 that is not JSON is Access's login page served in place.
    throw new ApiError('auth', `expected JSON, got ${contentType || 'no content type'}`)
  }
  try {
    return (await response.json()) as T
  } catch (error) {
    throw new ApiError('unexpected', `invalid JSON: ${String(error)}`)
  }
}

/**
 * The request itself and every failure a status can tell: what a body-less answer and a JSON one share.
 * `answers` names a refusal the caller reads for itself rather than as a failure.
 */
async function send(
  path: string,
  init: RequestInit,
  fetcher: Fetcher,
  answers: readonly number[] = [],
  timeoutMs: number = REQUEST_TIMEOUT_MS,
): Promise<Response> {
  let response: Response
  // A timer and a controller rather than AbortSignal.timeout, so the clock a
  // test controls is the clock this runs on.
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    // 'manual' keeps Access's redirect visible to us. Followed, it would land on
    // a cross-origin login page, fail CORS, and surface as a network error --
    // indistinguishable from the server being down.
    response = await fetcher(path, { ...init, redirect: 'manual', signal: controller.signal })
  } catch (error) {
    const reason = controller.signal.aborted ? `timed out after ${timeoutMs}ms` : `request failed: ${String(error)}`
    throw new ApiError('unavailable', reason)
  } finally {
    clearTimeout(timer)
  }

  if (response.type === 'opaqueredirect' || (response.status >= 300 && response.status < 400)) {
    throw new ApiError('auth', `redirected (status ${response.status}) -- Cloudflare Access refused the token`)
  }
  if (response.status === 401 || response.status === 403) {
    throw new ApiError('auth', `status ${response.status}`)
  }
  if (response.status === 404) {
    throw new ApiError('notFound', `status 404 for ${path}`)
  }
  if (response.status >= 500) {
    throw new ApiError('unavailable', `status ${response.status}`)
  }
  if (!response.ok && !answers.includes(response.status)) {
    throw new ApiError('unexpected', `status ${response.status}`)
  }
  return response
}

export async function fetchComics(fetcher: Fetcher = fetch): Promise<ComicSummary[]> {
  const comics = await getJson<ComicSummary[]>('/comics', fetcher)
  return comics.map((comic) => ({ ...comic, coverUrl: toMediaPath(comic.coverUrl) }))
}

/** How long a rescan may take: it walks the whole library folder, which an ordinary read never waits on. */
export const RESCAN_TIMEOUT_MS = 60_000

/**
 * Have the backend walk the library folder again. Its catalog is scanned once
 * at startup and held in memory, so without this a re-fetch hands back the
 * same list. The counts it answers with are not read: the caller re-fetches.
 */
export async function rescanLibrary(fetcher: Fetcher = fetch): Promise<void> {
  await send('/rescan', { method: 'POST', headers: { Accept: 'application/json' } }, fetcher, [], RESCAN_TIMEOUT_MS)
}

export async function fetchComic(comicId: string, fetcher: Fetcher = fetch): Promise<ComicDetail> {
  const comic = await getJson<ComicDetail>(`/comics/${encodeURIComponent(comicId)}`, fetcher)
  return {
    ...comic,
    coverUrl: toMediaPath(comic.coverUrl),
    // Not shown by the chapter list yet, but rewritten anyway: an absolute URL
    // left here is a broken image waiting for whoever renders it first.
    chapters: comic.chapters.map((chapter) => ({ ...chapter, coverUrl: toMediaPath(chapter.coverUrl) })),
  }
}

export async function fetchChapter(comicId: string, chapterId: string, fetcher: Fetcher = fetch): Promise<ChapterDetail> {
  const chapter = await getJson<ChapterDetail>(
    `/comics/${encodeURIComponent(comicId)}/chapters/${encodeURIComponent(chapterId)}`,
    fetcher,
  )
  return { ...chapter, pages: chapter.pages.map(toMediaPath) }
}

/**
 * Save the reading position into the one progress store the phone shares.
 *
 * `keepalive` lets the request outlive the page -- used for the flush sent as
 * the tab is hidden or closed. 422 (page out of range) surfaces as
 * `unexpected`, 503 (progress store down) as `unavailable`.
 */
export async function saveProgress(
  comicId: string,
  chapterId: string,
  lastPage: number,
  options: { keepalive?: boolean } = {},
  fetcher: Fetcher = fetch,
): Promise<ProgressSaved> {
  return requestJson<ProgressSaved>(
    `/comics/${encodeURIComponent(comicId)}/chapters/${encodeURIComponent(chapterId)}/progress`,
    {
      method: 'PUT',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ lastPage }),
      ...(options.keepalive ? { keepalive: true } : {}),
    },
    fetcher,
  )
}

const CARD_STATES: readonly CardState[] = ['new', 'learning', 'review', 'relearning']

const cardState = (state: unknown): CardState => (CARD_STATES.includes(state as CardState) ? (state as CardState) : 'new')

/**
 * The deck shared with the phone, newest card first.
 *
 * Decoded as leniently as the phone decodes it: a state this client does not
 * know becomes `new` and a kind it does not know becomes `null`, so a value
 * the backend adds later degrades a card rather than breaking the deck.
 */
export async function fetchCards(fetcher: Fetcher = fetch): Promise<LearningCard[]> {
  const cards = await getJson<LearningCard[]>('/cards', fetcher)
  return cards.map(decodeCard)
}

function decodeCard(card: LearningCard): LearningCard {
  return {
    ...card,
    state: cardState(card.state),
    kind: card.kind === 'word' || card.kind === 'sentence' ? card.kind : null,
  }
}

export async function fetchStudySettings(fetcher: Fetcher = fetch): Promise<StudySettings> {
  return getJson<StudySettings>('/study/settings', fetcher)
}

const JSON_BODY = { Accept: 'application/json', 'Content-Type': 'application/json' }

/**
 * Record one answer and learn where the card went.
 *
 * The web has no scheduler of its own: the block returned here is the only
 * source of a card's next due date. Only the scheduling fields are kept -- the
 * echoed review row is of no use to a session. 404 (the card was deleted
 * elsewhere) surfaces as `notFound`, 422 as `unexpected`.
 */
export async function recordReview(cardId: number, review: ReviewRequest, fetcher: Fetcher = fetch): Promise<CardSchedule> {
  const outcome = await requestJson<CardSchedule>(
    `/cards/${cardId}/reviews`,
    { method: 'POST', headers: JSON_BODY, body: JSON.stringify(review) },
    fetcher,
  )
  return {
    state: cardState(outcome.state),
    learningStep: outcome.learningStep ?? null,
    ladderStage: outcome.ladderStage,
    previousStage: outcome.previousStage ?? null,
    introducedOn: outcome.introducedOn ?? null,
    dueAt: outcome.dueAt,
  }
}

/**
 * Replace the study settings, both fields at once, and return what was saved.
 * A value the backend refuses (an empty step list, a step of zero) surfaces
 * as `unexpected`; the settings page is meant to refuse it first.
 */
export async function saveStudySettings(settings: StudySettings, fetcher: Fetcher = fetch): Promise<StudySettings> {
  return requestJson<StudySettings>(
    '/study/settings',
    { method: 'PUT', headers: JSON_BODY, body: JSON.stringify(settings) },
    fetcher,
  )
}

/** What the reader may correct on a card besides its source text, which has its own route: `changeSourceText`. */
export interface CardCorrection {
  translation?: string
  /** `null` clears the kind. Left out, the kind is untouched. */
  kind?: 'word' | 'sentence' | null
}

/** Correct a card's translation, its kind, or both, and return the card as it now stands. */
export async function updateCard(cardId: number, correction: CardCorrection, fetcher: Fetcher = fetch): Promise<LearningCard> {
  const card = await requestJson<LearningCard>(
    `/cards/${cardId}`,
    { method: 'PATCH', headers: JSON_BODY, body: JSON.stringify(correction) },
    fetcher,
  )
  return decodeCard(card)
}

/** A corrected source text: the card as it now stands, or the other card that already holds the text. */
export type SourceTextChange = { card: LearningCard; taken?: undefined } | { card?: undefined; taken: LearningCard }

/**
 * Correct a typo in a card's source text. The card keeps its schedule, history
 * and translation. When the text is already another card's, the backend
 * answers 409 with that card and changes nothing; it comes back as `taken`.
 * Text with nothing to learn, or too long, surfaces as `unexpected`.
 */
export async function changeSourceText(cardId: number, sourceText: string, fetcher: Fetcher = fetch): Promise<SourceTextChange> {
  const response = await send(
    `/cards/${cardId}/source-text`,
    { method: 'PUT', headers: JSON_BODY, body: JSON.stringify({ sourceText }) },
    fetcher,
    [409],
  )
  if (response.status === 409) {
    const refusal = await readJson<{ card?: LearningCard }>(response)
    if (!refusal.card) throw new ApiError('unexpected', 'status 409 without the card that holds the text')
    return { taken: decodeCard(refusal.card) }
  }
  return { card: decodeCard(await readJson<LearningCard>(response)) }
}

/** Put a card back to never having been met, and return it. */
export async function resetCard(cardId: number, fetcher: Fetcher = fetch): Promise<LearningCard> {
  const card = await requestJson<LearningCard>(`/cards/${cardId}/reset`, { method: 'POST', headers: { Accept: 'application/json' } }, fetcher)
  return decodeCard(card)
}

/**
 * The target language every card collected here carries: the identifier the
 * phone sends for Traditional Chinese. Not a parameter, because a card's
 * identity includes it -- another spelling of the same language would give the
 * same line a second card.
 */
export const TARGET_LANGUAGE = 'zh-Hant'

/** One line as the reader typed it, and where in the library they were reading. */
export interface CardDraft {
  sourceText: string
  translation: string
  /** Always said: the web never collects a card of undecided kind. */
  kind: 'word' | 'sentence'
  comicId: string
  chapterId: string
  pageNumber: number
}

/** The card the deck now holds for a line, and whether this request is what made it. */
export interface Collected {
  card: LearningCard
  created: boolean
}

/**
 * Collect one line into the deck shared with the phone.
 *
 * The backend answers 201 for a new card and 200 for a line already there,
 * returning the existing card untouched -- the translation, kind and page
 * sent here are dropped. The status is the only thing that tells the two
 * apart, so it is read here rather than left behind in `requestJson`. A source
 * text the backend refuses (nothing to learn, or too long) surfaces as
 * `unexpected`.
 */
export async function createCard(draft: CardDraft, fetcher: Fetcher = fetch): Promise<Collected> {
  const response = await send(
    '/cards',
    { method: 'POST', headers: JSON_BODY, body: JSON.stringify({ ...draft, targetLanguage: TARGET_LANGUAGE }) },
    fetcher,
  )
  const card = await readJson<LearningCard>(response)
  return { card: decodeCard(card), created: response.status === 201 }
}

/**
 * Delete a card for good. The backend answers 204 with no body, so anything
 * else that claims success is Access's login page served in place.
 */
export async function deleteCard(cardId: number, fetcher: Fetcher = fetch): Promise<void> {
  const response = await send(`/cards/${cardId}`, { method: 'DELETE' }, fetcher)
  if (response.status !== 204) throw new ApiError('auth', `expected 204, got ${response.status}`)
}
