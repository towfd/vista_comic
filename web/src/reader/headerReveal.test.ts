import { describe, expect, it } from 'vitest'
import { HIDE_AFTER, initialHeader, REVEAL_AFTER, TOP_ZONE, trackHeader, type HeaderState } from './headerReveal'

const scroll = (offsets: number[], from: HeaderState = initialHeader) => offsets.reduce(trackHeader, from)

describe('trackHeader', () => {
  it('shows the bar at the top of the chapter', () => {
    expect(scroll([0]).visible).toBe(true)
  })

  it('keeps the bar shown anywhere within the top zone', () => {
    expect(scroll([TOP_ZONE]).visible).toBe(true)
    expect(scroll([2000, TOP_ZONE]).visible).toBe(true)
  })

  it('hides the bar on reading down past the top zone', () => {
    expect(scroll([100, 400, 900]).visible).toBe(false)
  })

  it('keeps the bar through a small scroll down', () => {
    const shown = scroll([0, 2000, 1000])
    expect(shown.visible).toBe(true)
    expect(scroll([1000 + HIDE_AFTER], shown).visible).toBe(true)
    expect(scroll([1000 + HIDE_AFTER + 1], shown).visible).toBe(false)
  })

  it('reveals the bar on a small scroll up from deep in the chapter', () => {
    const hidden = scroll([500, 3000])
    expect(hidden.visible).toBe(false)
    expect(scroll([3000 - REVEAL_AFTER], hidden).visible).toBe(false)
    expect(scroll([3000 - REVEAL_AFTER - 1], hidden).visible).toBe(true)
  })

  it('measures the reveal from the deepest point, not the last step', () => {
    // Up a little, down further, then up: the first nudge did not count.
    const hidden = scroll([500, 3000, 2995, 3200])
    expect(scroll([3200 - REVEAL_AFTER], hidden).visible).toBe(false)
    expect(scroll([3200 - REVEAL_AFTER - 1], hidden).visible).toBe(true)
  })

  it('measures the hide from the highest point the bar showed at', () => {
    const shown = scroll([500, 3000, 2000, 1990, 2005])
    expect(shown.visible).toBe(true)
    expect(scroll([1990 + HIDE_AFTER + 1], shown).visible).toBe(false)
  })
})
