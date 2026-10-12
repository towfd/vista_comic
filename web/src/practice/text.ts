// Text keys and judging. Free of the DOM and of Vue; see "Judging" in
// .scratch/web-review/spec.md.
//
// The keys are spelled the way they are on purpose. Run against the phone's
// Swift and the backend's Python on 44 inputs, these forms agree for
// Vietnamese and the obvious ones do not: `\s` differs from Swift on U+0085
// and U+FEFF, and `\p{M}` strips marks the phone keeps.

/**
 * The key two texts share when they are the same apart from case and spacing.
 * The same rule that gives a card its identity on the phone and the backend.
 */
export function normalizedKey(text: string): string {
  return text.normalize('NFKC').replace(/\p{White_Space}/gu, '').toLowerCase()
}

const PUNCTUATION = /[\p{P}\p{S}]/gu

// Grave, acute, tilde, hook above, dot below: the five tones a syllable can
// carry. The circumflex, breve and horn are not here -- they make a different
// vowel, not a different tone.
const TONE_MARKS = /[̣̀́̃̉]/g

/**
 * A text's syllables, each reduced to its letters and the tone it carries.
 *
 * Vietnamese has two conventions for which vowel wears the mark -- `hoà` and
 * `hòa` -- and no Unicode normalisation brings them together. Lifting the tone
 * off the vowel does: both become `hoa` with a grave. A wrong or missing tone
 * still differs, as does a missing circumflex or horn.
 */
function syllables(text: string, ignorePunctuation: boolean): string[] {
  let folded = text.normalize('NFKC').toLowerCase()
  // To a space rather than to nothing, so `Được,cảm` and `Được, cảm` are the
  // same two syllables.
  if (ignorePunctuation) folded = folded.replace(PUNCTUATION, ' ')
  return folded
    .split(/\p{White_Space}+/u)
    .filter(Boolean)
    .map((syllable) => {
      const decomposed = syllable.normalize('NFD')
      const tones = (decomposed.match(TONE_MARKS) ?? []).sort().join('')
      return decomposed.replace(TONE_MARKS, '').normalize('NFC') + '\u0000' + tones
    })
}

function sameText(produced: string, expected: string, ignorePunctuation: boolean): boolean {
  const strip = (text: string) => (ignorePunctuation ? normalizedKey(text).replace(PUNCTUATION, '') : normalizedKey(text))
  const given = strip(produced)
  if (given === '') return false
  // Spacing never matters when the tones sit where the card has them...
  if (given === strip(expected)) return true
  // ...and where a tone sits never matters when the syllables are spaced as
  // the card has them. An answer that differs in both at once is wrong; that
  // is the price of keeping each rule simple.
  const a = syllables(produced, ignorePunctuation)
  const b = syllables(expected, ignorePunctuation)
  return a.length === b.length && a.every((syllable, index) => syllable === b[index])
}

/**
 * Whether `produced` is the card's whole text. Case, spacing, punctuation and
 * symbols are ignored; word order, spelling and tones are not.
 *
 * Stricter than the phone on purpose: the phone counts a missing tone as
 * correct and names it, because tones are laborious on a touch keyboard. At a
 * desk they are not.
 */
export function judgeSentence(produced: string, sourceText: string): boolean {
  return sameText(produced, sourceText, true)
}

/** Whether there is anything to judge. An empty field cannot be submitted. */
export function isBlank(text: string): boolean {
  return normalizedKey(text) === ''
}
