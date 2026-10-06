import type { ChapterDetail, ComicDetail, ComicSummary, ProgressSaved } from './types'

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
  let response: Response
  try {
    // 'manual' keeps Access's redirect visible to us. Followed, it would land on
    // a cross-origin login page, fail CORS, and surface as a network error --
    // indistinguishable from the server being down.
    response = await fetcher(path, { ...init, redirect: 'manual' })
  } catch (error) {
    throw new ApiError('unavailable', `request failed: ${String(error)}`)
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
  if (!response.ok) {
    throw new ApiError('unexpected', `status ${response.status}`)
  }

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

export async function fetchComics(fetcher: Fetcher = fetch): Promise<ComicSummary[]> {
  const comics = await getJson<ComicSummary[]>('/comics', fetcher)
  return comics.map((comic) => ({ ...comic, coverUrl: toMediaPath(comic.coverUrl) }))
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
