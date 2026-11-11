// When the reader's top bar shows, free of the DOM and of Vue. Opened from the
// home screen there is no browser back button, so the bar's back link has to
// be one small scroll up away from anywhere in a chapter -- yet out of the
// way of the pages while reading down.

/** Within this many pixels of the top the bar always shows. */
export const TOP_ZONE = 64
/** Reading down this far past where the bar last showed hides it. */
export const HIDE_AFTER = 24
/** Scrolling up this far from the lowest point read reveals it. */
export const REVEAL_AFTER = 12

/**
 * `anchor` is the scroll offset the next change is measured from: the lowest
 * point reached while the bar shows, the deepest while it is hidden. A small
 * wobble of the finger in either direction never flips the bar.
 */
export interface HeaderState {
  visible: boolean
  anchor: number
}

export const initialHeader: HeaderState = { visible: true, anchor: 0 }

export function trackHeader(state: HeaderState, y: number): HeaderState {
  if (y <= TOP_ZONE) return { visible: true, anchor: y }
  if (state.visible) {
    if (y - state.anchor > HIDE_AFTER) return { visible: false, anchor: y }
    return { visible: true, anchor: Math.min(state.anchor, y) }
  }
  if (state.anchor - y > REVEAL_AFTER) return { visible: true, anchor: y }
  return { visible: false, anchor: Math.max(state.anchor, y) }
}
