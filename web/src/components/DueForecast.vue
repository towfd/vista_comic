<script setup lang="ts">
// How many cards fall due on which of the coming days, as a row of tiles
// (DESIGN 7.20). The card library uses its tiles to narrow the list; the
// practice overview sends them to the library, narrowed. Which tiles to show,
// and what pressing one does, are the page's.
import type { RouteLocationRaw } from 'vue-router'
import type { DueBucketKey, DueCount } from '../practice/forecast'

defineProps<{
  title: string
  /** Says what a tile does when pressed. */
  hint: string
  counts: readonly DueCount[]
  /** The pressed tile, when the tiles narrow a list on the same page. */
  selected?: DueBucketKey | null
  /** Makes each tile a link; without it a tile is a button that emits `select`. */
  to?: (key: DueBucketKey) => RouteLocationRaw
  /** Under the tiles: what they leave out. */
  note?: string
}>()

const emit = defineEmits<{ select: [key: DueBucketKey] }>()

// Three a row on a phone; one row once the panel is wide enough for the
// longest range (8–21 天後) in every tile. Measured on the panel, not the
// window, because the two pages are not equally wide.
const columns: Record<number, string> = {
  5: 'grid-cols-3 @min-[24rem]:grid-cols-5',
  6: 'grid-cols-3 @min-[29rem]:grid-cols-6',
}

const tile =
  'flex flex-col items-center rounded-tile bg-paper px-1 pt-2 pb-2 text-center transition-[scale,box-shadow] duration-120 ease-standard active:scale-96 motion-reduce:active:scale-100'

function numberTone({ bucket, count }: DueCount): string {
  if (count === 0) return 'text-ink-faint'
  // Today's cards are the ones a session asks, drawn in the red of 已到期.
  return bucket.key === 'today' ? 'text-st-relearn' : 'text-ink'
}

const label = ({ bucket, count }: DueCount) => `${bucket.label}（${bucket.range}）${count} 張`
</script>

<template>
  <section class="@container rounded-panel bg-blush px-4 pt-4 pb-3.5">
    <div class="flex items-baseline justify-between gap-2 px-1">
      <h2 class="text-body font-extrabold text-ink">{{ title }}</h2>
      <span class="text-caption text-ink-soft">{{ hint }}</span>
    </div>
    <div class="mt-2.5 grid gap-2" :class="columns[counts.length] ?? 'grid-cols-3'">
      <template v-for="entry in counts" :key="entry.bucket.key">
        <RouterLink v-if="to" :to="to(entry.bucket.key)" :aria-label="label(entry)" :class="tile">
          <span class="text-headline leading-tight font-black tabular-nums" :class="numberTone(entry)">{{ entry.count }}</span>
          <span class="text-meta font-extrabold text-ink">{{ entry.bucket.label }}</span>
          <span class="text-caption leading-snug text-ink-faint">{{ entry.bucket.range }}</span>
        </RouterLink>
        <button
          v-else
          type="button"
          :aria-label="label(entry)"
          :aria-pressed="selected === entry.bucket.key"
          :class="[tile, selected === entry.bucket.key && 'inset-ring-3 inset-ring-brand']"
          @click="emit('select', entry.bucket.key)"
        >
          <span class="text-headline leading-tight font-black tabular-nums" :class="numberTone(entry)">{{ entry.count }}</span>
          <span class="text-meta font-extrabold text-ink">{{ entry.bucket.label }}</span>
          <span class="text-caption leading-snug text-ink-faint">{{ entry.bucket.range }}</span>
        </button>
      </template>
    </div>
    <p v-if="note" class="mx-1 mt-2.5 text-caption text-ink-soft">{{ note }}</p>
  </section>
</template>
