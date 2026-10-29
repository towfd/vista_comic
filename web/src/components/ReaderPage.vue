<script setup lang="ts">
import { computed, ref } from 'vue'
import type { OverlayRegion } from '../reader/overlay'

const props = withDefaults(
  defineProps<{
    src: string
    pageNumber: number
    // OCR boxes for this page (reader/overlay.ts) and the open one.
    regions?: OverlayRegion[]
    selectedId?: string | null
  }>(),
  { regions: () => [], selectedId: null },
)
const emit = defineEmits<{ select: [segmentId: string | null]; collect: [region: OverlayRegion] }>()

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
      :class="state === 'loaded' ? 'h-auto w-auto max-w-full' : 'aspect-[900/1549] w-full bg-neutral-900'"
      @load="state = 'loaded'"
      @error="state = 'error'"
    />
    <!-- Invisible OCR boxes over the loaded image, in percent of it. -->
    <template v-if="state === 'loaded'">
      <button
        v-for="r in regions"
        :key="r.segmentId + r.left + r.top"
        type="button"
        :aria-label="r.source"
        class="absolute cursor-pointer"
        :style="{ left: `${r.left}%`, top: `${r.top}%`, width: `${r.width}%`, height: `${r.height}%` }"
        @click.stop="emit('select', r.segmentId === selectedId ? null : r.segmentId)"
      />
      <template v-for="r in regions" :key="'pop' + r.segmentId + r.left + r.top">
        <div
          v-if="r.segmentId === selectedId"
          class="absolute z-10 my-2 w-72 max-w-[90%] rounded-lg bg-neutral-900/95 p-3 text-left shadow-xl ring-1 ring-neutral-700"
          :style="popoverStyle(r)"
          @click.stop
        >
          <p class="text-base leading-relaxed text-neutral-50">{{ r.text ?? '（這句還沒有翻譯）' }}</p>
          <p class="mt-2 border-t border-neutral-700 pt-2 text-xs leading-relaxed text-neutral-400">{{ r.source }}</p>
          <div class="mt-3 flex justify-end">
            <button
              type="button"
              class="rounded-md bg-sky-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-sky-500"
              @click="emit('collect', r)"
            >
              加入句子
            </button>
          </div>
        </div>
      </template>
    </template>
  </div>
  <div v-else class="flex aspect-[900/1549] w-full flex-col items-center justify-center gap-3 bg-neutral-900">
    <p class="text-sm text-neutral-400">第 {{ pageNumber }} 頁載入失敗</p>
    <button class="rounded-md bg-neutral-800 px-3 py-1.5 text-sm text-neutral-100 hover:bg-neutral-700" @click="retry">
      重試
    </button>
  </div>
</template>
