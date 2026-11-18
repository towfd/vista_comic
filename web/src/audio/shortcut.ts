// ⌘3 presses a play button, so a recording can be heard without the mouse.
//
// Two halves, because they live on different things:
// - a page **claims** the key for as long as it is on screen (useAudioShortcut),
//   so ⌘3 never falls through to the browser's "go to tab 3" there, even while
//   no button is showing, as while a question is being asked;
// - one button on that page **offers** its press (CardAudioButton's
//   `shortcut`), and the key triggers it.
// Pages that never claim it leave ⌘3 to the browser.

import { onMounted, onUnmounted } from 'vue'

/** What `isAudioShortcut` reads of a keydown. */
type Keys = Pick<KeyboardEvent, 'code' | 'metaKey' | 'ctrlKey' | 'altKey' | 'shiftKey'>

/** What the keydown handler needs of an event. */
export type ShortcutKeydown = Keys & Pick<KeyboardEvent, 'repeat' | 'preventDefault'>

/**
 * ⌘3 with nothing else held. `code` rather than `key`: the 3 on the number row
 * whatever the layout makes it type.
 */
export function isAudioShortcut(event: Keys): boolean {
  return event.code === 'Digit3' && event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey
}

/** What `aria-keyshortcuts` says on the button that answers the key. */
export const AUDIO_SHORTCUT_ARIA = 'Meta+3'

export function createAudioShortcut() {
  let press: (() => void) | null = null

  /** `fn` is what the key does from now on. The last button to offer wins. */
  function offer(fn: () => void) {
    press = fn
  }

  /** Take `fn` back, unless another button has offered since. */
  function withdraw(fn: () => void) {
    if (press === fn) press = null
  }

  /** The claiming page's keydown handler. A held key presses once. */
  function onKeydown(event: ShortcutKeydown) {
    if (!isAudioShortcut(event)) return
    event.preventDefault()
    if (!event.repeat) press?.()
  }

  return { offer, withdraw, onKeydown }
}

/** The page's shortcut. */
export const audioShortcut = createAudioShortcut()

/** Claim ⌘3 for as long as the calling page is on screen. */
export function useAudioShortcut() {
  onMounted(() => window.addEventListener('keydown', audioShortcut.onKeydown))
  onUnmounted(() => window.removeEventListener('keydown', audioShortcut.onKeydown))
}
