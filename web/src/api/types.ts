// Shapes of the backend's JSON, as documented in docs/api-contract.md.
// Media URLs arrive absolute; the client rewrites them before they reach a
// component (see toMediaPath).

export interface ComicSummary {
  id: string
  title: string
  coverUrl: string
  chapterCount: number
  lastReadAt?: string | null
  continueChapterId: string
}

/** Derived by the backend from the phone's reading progress. Display only. */
export type ReadState = 'unread' | 'reading' | 'read'

export interface ChapterSummary {
  id: string
  number: number
  title: string
  pageCount: number
  /** The chapter's own first page. Absolute from the backend; rewritten by the client. */
  coverUrl: string
  /** Typed as string because the backend could add a value; unknown values render no badge. */
  readState: ReadState | string
}

export interface ComicDetail {
  id: string
  title: string
  coverUrl: string
  chapters: ChapterSummary[]
}

export interface ChapterDetail {
  id: string
  number: number
  title: string
  /** Page image URLs in reading order. Absolute from the backend; rewritten by the client. */
  pages: string[]
  /** The phone's resume position. Deliberately ignored by the web reader. */
  lastReadPage?: number
}
