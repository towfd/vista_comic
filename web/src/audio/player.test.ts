import { describe, expect, it } from 'vitest'
import { createPlayer, type AudioLike } from './player'

/** An audio element that plays only when told to, and records what it was asked. */
class FakeAudio implements AudioLike {
  src = ''
  currentTime = 0
  paused = true
  private listeners = new Map<string, (() => void)[]>()
  /** Every play() asked for, oldest first, so a test can refuse an earlier one. */
  private plays: { resolve: () => void; reject: (e: Error) => void }[] = []

  play() {
    this.paused = false
    return new Promise<void>((resolve, reject) => {
      this.plays.push({ resolve, reject })
    })
  }
  pause() {
    this.paused = true
  }
  addEventListener(type: string, listener: () => void) {
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener])
  }

  /** The browser started making sound. */
  started() {
    this.plays.at(-1)?.resolve()
    this.fire('playing')
  }
  /** The browser refused a play() (a blocked autoplay, an aborted load); the latest unless told which. */
  async refused(which: 'latest' | 'first' = 'latest') {
    const play = which === 'first' ? this.plays[0] : this.plays.at(-1)
    play?.reject(new Error('NotAllowedError'))
    await Promise.resolve()
    await Promise.resolve()
  }
  fire(type: string) {
    for (const listener of this.listeners.get(type) ?? []) listener()
  }
}

function setup() {
  const audio = new FakeAudio()
  const player = createPlayer(() => audio)
  return { audio, player, a: Symbol('a'), b: Symbol('b') }
}

describe('the card audio player', () => {
  it('is idle for everyone until a press', () => {
    const { player, a } = setup()
    expect(player.phaseOf(a)).toBe('idle')
  })

  it('loads on a press, then plays once the sound starts', () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    expect(audio.src).toBe('/cards/7/audio')
    expect(player.phaseOf(a)).toBe('loading')
    audio.started()
    expect(player.phaseOf(a)).toBe('playing')
  })

  it('stops on a second press while playing', () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    audio.started()
    player.toggle(a, '/cards/7/audio')
    expect(player.phaseOf(a)).toBe('idle')
    expect(audio.paused).toBe(true)
  })

  it('stops on a second press while still loading', () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    player.toggle(a, '/cards/7/audio')
    expect(player.phaseOf(a)).toBe('idle')
    expect(audio.paused).toBe(true)
  })

  it('plays one recording at a time: another press takes over', () => {
    const { audio, player, a, b } = setup()
    player.toggle(a, '/cards/7/audio')
    audio.started()
    player.toggle(b, '/cards/8/audio')
    expect(player.phaseOf(a)).toBe('idle')
    expect(player.phaseOf(b)).toBe('loading')
    expect(audio.src).toBe('/cards/8/audio')
  })

  it('goes back to idle when the recording ends', () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    audio.started()
    audio.fire('ended')
    expect(player.phaseOf(a)).toBe('idle')
  })

  it('goes back to idle when the recording cannot be loaded', () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    audio.fire('error')
    expect(player.phaseOf(a)).toBe('idle')
  })

  it('goes back to idle when the browser refuses to play', async () => {
    const { audio, player, a } = setup()
    player.toggle(a, '/cards/7/audio')
    await audio.refused()
    expect(player.phaseOf(a)).toBe('idle')
  })

  it('ignores a refusal that belongs to a recording already replaced', async () => {
    const { audio, player, a, b } = setup()
    player.toggle(a, '/cards/7/audio')
    player.toggle(b, '/cards/8/audio')
    // The first play() is rejected because its load was cut short.
    await audio.refused('first')
    expect(player.phaseOf(b)).toBe('loading')
  })

  it('lets a button stop only its own recording', () => {
    const { audio, player, a, b } = setup()
    player.toggle(a, '/cards/7/audio')
    audio.started()
    player.stop(b)
    expect(player.phaseOf(a)).toBe('playing')
    player.stop(a)
    expect(player.phaseOf(a)).toBe('idle')
  })

  it('creates its audio element only when first pressed', () => {
    let made = 0
    const player = createPlayer(() => {
      made += 1
      return new FakeAudio()
    })
    player.stop(Symbol('nobody'))
    expect(made).toBe(0)
    player.toggle(Symbol('a'), '/cards/7/audio')
    player.toggle(Symbol('b'), '/cards/8/audio')
    expect(made).toBe(1)
  })
})
