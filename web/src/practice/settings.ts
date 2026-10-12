// Reading the study settings as the reader types them. Free of the DOM and of
// Vue; see "Settings" in .scratch/web-review/spec.md.

const WHOLE_NUMBER = /^\d+$/

/**
 * A list of minutes the way a person writes one: `5, 7, 10`.
 *
 * `null` rather than a partial list when anything is wrong, because there is
 * no safe half-answer: an empty list has no first step to restart a card on,
 * and a zero-minute step would have a card due before it was answered. The
 * backend refuses both; this refuses them before a save has to fail.
 * Separators are lenient -- commas, spaces, or both.
 */
export function parseLearningSteps(text: string): number[] | null {
  const pieces = text.split(/[,，\p{White_Space}]+/u).filter(Boolean)
  if (pieces.length === 0) return null
  const steps: number[] = []
  for (const piece of pieces) {
    if (!WHOLE_NUMBER.test(piece)) return null
    const minutes = Number(piece)
    if (!Number.isSafeInteger(minutes) || minutes <= 0) return null
    steps.push(minutes)
  }
  return steps
}

/** Written back the same way, so the field shows what was last saved rather than an array. */
export function formatLearningSteps(steps: readonly number[]): string {
  return steps.join(', ')
}

/** How many new cards a day: a whole number, zero or more. `null` for anything else. */
export function parseNewCardsPerDay(text: string): number | null {
  const trimmed = text.trim()
  if (!WHOLE_NUMBER.test(trimmed)) return null
  const count = Number(trimmed)
  return Number.isSafeInteger(count) ? count : null
}
