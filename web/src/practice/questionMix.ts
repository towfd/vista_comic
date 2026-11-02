// Which kinds of question the reader wants, remembered in this browser.

/**
 * What a session may ask. One value rather than two switches, so that asking
 * nothing at all cannot be written down.
 */
export type QuestionMix = 'both' | 'cloze' | 'sentence'

const MIX_KEY = 'vista.questionMix'

/** The last mix chosen in this browser, or both. Storage may be missing or refuse. */
export function rememberedQuestionMix(): QuestionMix {
  try {
    const stored = localStorage.getItem(MIX_KEY)
    if (stored === 'cloze' || stored === 'sentence') return stored
  } catch {
    // Private mode, blocked storage: the default will do.
  }
  return 'both'
}

export function rememberQuestionMix(mix: QuestionMix) {
  try {
    localStorage.setItem(MIX_KEY, mix)
  } catch {
    // Not remembered, still used.
  }
}
