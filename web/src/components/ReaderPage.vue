<script setup lang="ts">
import { computed, ref } from 'vue'
import type { OverlayRegion } from '../reader/overlay'
import { primarySm, secondaryMd } from './buttons'

/** DESIGN 7.1 secondary at 36px, beside a primary sm; touch area padded to 44. */
const secondarySm =
  "relative inline-flex h-9 items-center justify-center rounded-full bg-paper px-4 text-meta font-extrabold text-ink inset-ring-2 inset-ring-line before:absolute before:-inset-1 before:content-[''] hover:bg-blush active:bg-blush"

const props = withDefaults(
  defineProps<{
    src: string
    pageNumber: number
    // OCR boxes for this page (reader/overlay.ts) and the open one.
    regions?: OverlayRegion[]
    selectedId?: string | null
    // Outline every box, or only the open one.
    hints?: boolean
  }>(),
  { regions: () => [], selectedId: null, hints: true },
)
const emit = defineEmits<{
  select: [segmentId: string | null]
  collect: [region: OverlayRegion]
  analyse: [region: OverlayRegion]
}>()

type State = 'loading' | 'loaded' | 'error'
const state = ref<State>('loading')
const attempt = ref(0)

// A retry needs a URL the browser has not already failed on. The backend
// ignores the query string; the browser's cache does not.
const url = computed(() =>
  attempt.value === 0 ? props.src : `${props.src}${props.src.includes('?') ? '&' : '?'}retry=${attempt.value}`,
)

function retry() {
  attempt.value += 1
  state.value = 'loading'
}

/** Keep the popover inside the page: anchor it to whichever edge of the box is nearer the middle. */
function popoverStyle(r: OverlayRegion) {
  const center = r.left + r.width / 2
  const below = r.top + r.height < 70
  const vertical = below ? { top: `${r.top + r.height}%` } : { bottom: `${100 - r.top}%` }
  if (center < 30) return { ...vertical, left: `${r.left}%` }
  if (center > 70) return { ...vertical, right: `${100 - r.left - r.width}%` }
  return { ...vertical, left: `${center}%`, transform: 'translateX(-50%)' }
}
</script>

<template>
  <!--
    Before it loads, the image reserves a page-shaped box. The API gives no
    dimensions, and an unloaded image is zero pixels tall -- so without this,
    every page of the chapter would sit at the same spot, all of them "near the
    viewport", and loading="lazy" would fetch the whole chapter at once.

    The box is 900:1549, the page shape measured across the library (iOS's
    defaultPageHeightRatio), not a guess: a page that loads above a resumed
    position then barely changes height, and Chrome's scroll anchoring absorbs
    the rest, so the page being read stays put.

    Once loaded it takes its natural size, capped at the column's 800px and
    never upscaled: a narrow page stays narrow and centred.
  -->
  <div v-if="state !== 'error'" class="relative mx-auto w-fit max-w-full" :class="state === 'loaded' ? '' : 'w-full'">
    <img
      :src="url"
      :alt="`第 ${pageNumber} 頁`"
      loading="lazy"
      decoding="async"
      class="mx-auto block"
      :class="state === 'loaded' ? 'h-auto w-auto max-w-full' : 'aspect-[900/1549] w-full bg-mist'"
      @load="state = 'loaded'"
      @error="state = 'error'"
    />
    <!--
      OCR boxes over the loaded image, in percent of it. Each carries an outline
      so a box that missed its bubble can still be found. The outlines are three
      stacked rings (DESIGN 7.17): no single colour stays visible on every
      manga, but one of pink, white and ink always does. A translated line has
      the pink ring, a line with only the original has none -- a difference in
      shape, not only in colour. The open one is twice as thick and filled.
      With hints off, only the open one is outlined.
    -->
    <template v-if="state === 'loaded'">
      <button
        v-for="r in regions"
        :key="r.segmentId + r.left + r.top"
        type="button"
        :aria-label="r.source"
        class="absolute cursor-pointer rounded-tile transition-[background-color,box-shadow] duration-120 ease-standard hover:bg-brand-wash focus-visible:bg-brand-wash focus-visible:shadow-ring-selected focus-visible:outline-none"
        :class="r.segmentId === selectedId ? 'bg-brand-wash shadow-ring-selected' : !hints ? '' : r.text === null ? 'shadow-ring-hint-plain' : 'shadow-ring-hint'"
        :style="{ left: `${r.left}%`, top: `${r.top}%`, width: `${r.width}%`, height: `${r.height}%` }"
        @click.stop="emit('select', r.segmentId === selectedId ? null : r.segmentId)"
      />
      <template v-for="r in regions" :key="'pop' + r.segmentId + r.left + r.top">
        <!-- White with an ink frame, like a speech balloon. Grows in with `scale`, which leaves popoverStyle's transform alone. -->
        <div
          v-if="r.segmentId === selectedId"
          class="absolute z-10 my-3 w-72 max-w-[90%] rounded-card border-2 border-ink bg-paper p-3.5 text-left shadow-overlay motion-safe:animate-[popover-in_120ms_var(--ease-standard)]"
          :style="popoverStyle(r)"
          @click.stop
        >
          <p class="text-body" :class="r.text === null ? 'text-ink-faint' : 'text-ink'">{{ r.text ?? '（這句還沒有翻譯）' }}</p>
          <p class="mt-2 border-t border-line pt-2 text-meta font-bold text-ink-soft" lang="vi">{{ r.source }}</p>
          <div class="mt-3 flex justify-end gap-2">
            <!-- Only a line with a reviewed translation: the analysis explains that translation. -->
            <button v-if="r.text !== null" type="button" :class="secondarySm" @click="emit('analyse', r)">深入查詢</button>
            <button type="button" :class="primarySm" @click="emit('collect', r)">加入句子</button>
          </div>
        </div>
      </template>
    </template>
  </div>
  <div v-else class="flex aspect-[900/1549] w-full flex-col items-center justify-center gap-3 bg-mist">
    <p class="text-meta text-ink-soft">第 {{ pageNumber }} 頁載入失敗</p>
    <button type="button" :class="secondaryMd" @click="retry">重試</button>
  </div>
</template>

<style>
@keyframes popover-in {
  from {
    opacity: 0;
    scale: 0.96;
  }
}
</style>
