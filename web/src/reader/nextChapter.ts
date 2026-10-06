// The next-chapter button's rules, free of the DOM and of Vue. See the
// "Next-chapter button" section of .scratch/web-reading-progress/spec.md.

/**
 * The chapter after `currentId` in the comic's chapter list order, or `null`
 * on the last chapter, for an id not in the list, or before the list exists.
 * `ChapterDetail` carries no neighbour, so the comic's list is the source.
 */
export function nextChapter<T extends { id: string }>(
  chapters: readonly T[] | null | undefined,
  currentId: string,
): T | null {
  if (!chapters) return null
  const index = chapters.findIndex((chapter) => chapter.id === currentId)
  if (index === -1) return null
  return chapters[index + 1] ?? null
}

/**
 * The `history.state` key the next-chapter button sets so the chapter it opens
 * starts at the top. It rides in history state, not the URL, and is removed
 * once applied, so a reload resumes from the saved position.
 */
export const START_AT_TOP_KEY = 'vistaStartAtTop'

/**
 * Reads the start-at-top flag from a history state object and returns the
 * state without it (every other key -- vue-router's own -- kept as is).
 * `rest` is `null` when there was nothing to remove.
 */
export function takeStartAtTopFlag(state: unknown): { startAtTop: boolean; rest: Record<string, unknown> | null } {
  if (state === null || typeof state !== 'object' || !(START_AT_TOP_KEY in state)) {
    return { startAtTop: false, rest: null }
  }
  const { [START_AT_TOP_KEY]: flag, ...rest } = state as Record<string, unknown>
  return { startAtTop: flag === true, rest }
}
