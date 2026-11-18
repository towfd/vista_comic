// Plays a card's recording on a press. Free of the DOM except for the one
// audio element it is handed, so a test can hand it a stand-in.
//
// One element for the whole page, so one recording plays at a time: a press on
// another button takes the element over, and the first button goes back to
// idle. Each button is an `owner` (a symbol it makes for itself) rather than a
// card id, because one card can have two buttons on a screen.

import { shallowRef } from 'vue'

/** What the player needs of an `HTMLAudioElement`. */
export interface AudioLike {
  src: string
  currentTime: number
  play(): Promise<void>
  pause(): void
  addEventListener(type: 'playing' | 'ended' | 'error', listener: () => void): void
}

/** `loading`: pressed, no sound yet. `playing`: sound. A press in either stops it. */
export type Phase = 'idle' | 'loading' | 'playing'

interface Now {
  owner: symbol | null
  phase: Phase
}

const IDLE: Now = { owner: null, phase: 'idle' }

export function createPlayer(makeAudio: () => AudioLike) {
  let audio: AudioLike | null = null
  // Bumped by every press and every stop. A play() that is refused after the
  // element has moved on to another recording must not touch the new one.
  let generation = 0
  const now = shallowRef<Now>(IDLE)

  function element(): AudioLike {
    if (audio) return audio
    const made = makeAudio()
    made.addEventListener('playing', () => {
      if (now.value.owner) now.value = { owner: now.value.owner, phase: 'playing' }
    })
    // A failed load says nothing on screen: the button simply goes back to
    // idle and can be pressed again.
    made.addEventListener('ended', () => void (now.value = IDLE))
    made.addEventListener('error', () => void (now.value = IDLE))
    audio = made
    return made
  }

  function phaseOf(owner: symbol): Phase {
    return now.value.owner === owner ? now.value.phase : 'idle'
  }

  /** Play `url` for `owner`; if `owner` is already loading or playing, stop. */
  function toggle(owner: symbol, url: string) {
    if (phaseOf(owner) !== 'idle') return stop(owner)
    const el = element()
    const mine = ++generation
    el.src = url
    now.value = { owner, phase: 'loading' }
    // Called inside the press itself: iOS plays only what a touch started.
    el.play().catch(() => {
      if (generation === mine) now.value = IDLE
    })
  }

  /** Stop, if what is playing is `owner`'s. A button leaving the screen calls this. */
  function stop(owner: symbol) {
    if (now.value.owner !== owner) return
    generation += 1
    if (audio) {
      audio.pause()
      audio.currentTime = 0
    }
    now.value = IDLE
  }

  return { phaseOf, toggle, stop }
}

/** The page's player. Its element is made on the first press, never during render. */
export const player = createPlayer(() => {
  const el = new Audio()
  el.preload = 'none'
  return el
})
