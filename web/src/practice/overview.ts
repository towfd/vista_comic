// What the practice overview draws beyond the queue's own counts: the three
// bubbles, and -- once the day is done -- what tomorrow holds and where the
// whole deck stands. Free of the DOM and of Vue; nothing here reads the clock.

import type { CardState, LearningCard } from '../api/types'
import { localDay, type Waiting } from './queue'

/**
 * How many cards fall due on the reader's local tomorrow. New cards are left
 * out: they have no due date of their own, only the day's allowance.
 */
export function dueTomorrow(deck: readonly LearningCard[], now: Date): number {
  // Built from the calendar fields, not by adding 24 hours, so a day that is
  // 23 or 25 hours long still lands on the next date.
  const tomorrow = localDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1))
  return deck.filter((card) => card.state !== 'new' && localDay(new Date(card.dueAt)) === tomorrow).length
}

/** The deck counted by stage, in the order the legend reads. */
export interface StageCount {
  state: CardState
  label: string
  count: number
}

const STAGES: { state: CardState; label: string }[] = [
  { state: 'new', label: '新卡' },
  { state: 'learning', label: '學習中' },
  { state: 'relearning', label: '重新學習' },
  { state: 'review', label: '間隔複習' },
]

/** Every stage, zeros included, so the legend always reads the same four lines. */
export function stageDistribution(deck: readonly LearningCard[]): StageCount[] {
  return STAGES.map(({ state, label }) => ({ state, label, count: deck.filter((card) => card.state === state).length }))
}

/** The distribution in words, for the bar's `aria-label`. */
export function distributionLabel(stages: readonly StageCount[]): string {
  return stages.map(({ label, count }) => `${label} ${count} 張`).join('、')
}

export type BubbleKey = 'due' | 'fresh' | 'learning'

/** One bubble, placed: offsets are from the container's centre line and its top, in px. */
export interface Bubble {
  key: BubbleKey
  label: string
  count: number
  diameter: number
  /** The type token for the number, by how big the bubble is. */
  numberSize: 'text-display' | 'text-headline' | 'text-heading'
  left: number
  top: number
}

const BUBBLE_ORDER: { key: BubbleKey; label: string }[] = [
  { key: 'due', label: '到期' },
  { key: 'fresh', label: '新卡' },
  { key: 'learning', label: '學習中' },
]

const LARGEST = 136
/** Small enough to still hold its number. */
const SMALLEST = 64
/** The container's height when the bubbles keep to the usual layout. */
export const BUBBLES_HEIGHT = 178

// Slots by how many bubbles are drawn, largest first (page-design-spec 2.5).
const SLOTS: Record<number, { left: number; top: number }[]> = {
  1: [{ left: -LARGEST / 2, top: 21 }],
  2: [
    { left: -112, top: 20 },
    { left: 20, top: 40 },
  ],
  3: [
    { left: -124, top: 20 },
    { left: 18, top: 4 },
    { left: 48, top: 102 },
  ],
}

/**
 * The bubbles for what is waiting: area in proportion to the count, empty ones
 * left out, largest first (ties keep 到期, 新卡, 學習中 order). A single bubble
 * is centred on its own diameter rather than the largest's.
 */
export function bubbleLayout(counts: Waiting): Bubble[] {
  const drawn = BUBBLE_ORDER.map(({ key, label }) => ({ key, label, count: counts[key] }))
    .filter((bubble) => bubble.count > 0)
    .sort((a, b) => b.count - a.count)
  const most = drawn[0]?.count ?? 0
  const slots = SLOTS[drawn.length] ?? []
  return drawn.map((bubble, index) => {
    const diameter = Math.round(Math.max(SMALLEST, LARGEST * Math.sqrt(bubble.count / most)))
    const slot = slots[index]!
    return {
      ...bubble,
      diameter,
      numberSize: diameter >= 120 ? 'text-display' : diameter >= 84 ? 'text-headline' : 'text-heading',
      left: drawn.length === 1 ? -diameter / 2 : slot.left,
      top: slot.top,
    }
  })
}

/**
 * How tall the bubbles' container must be: the usual height, or more when
 * near-equal counts make a lower bubble reach past it.
 */
export function bubblesHeight(bubbles: readonly Bubble[]): number {
  return Math.max(BUBBLES_HEIGHT, ...bubbles.map((bubble) => bubble.top + bubble.diameter))
}

/** All three counts in words, for the bubbles' `aria-label` -- zeros too, since a bubble left out still means something. */
export function bubblesLabel(counts: Waiting): string {
  return BUBBLE_ORDER.map(({ key, label }) => `${label} ${counts[key]} 張`).join('、')
}
