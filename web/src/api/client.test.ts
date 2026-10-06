import { describe, expect, it } from 'vitest'
import { ApiError, fetchChapter, fetchComic, fetchComics, getJson, toMediaPath, type Fetcher } from './client'

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
