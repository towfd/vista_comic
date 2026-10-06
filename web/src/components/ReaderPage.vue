<script setup lang="ts">
import { computed, ref } from 'vue'

const props = defineProps<{ src: string; pageNumber: number }>()

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
  <img
    v-if="state !== 'error'"
    :src="url"
    :alt="`第 ${pageNumber} 頁`"
    loading="lazy"
    decoding="async"
    class="mx-auto block"
    :class="state === 'loaded' ? 'h-auto w-auto max-w-full' : 'aspect-[900/1549] w-full bg-neutral-900'"
    @load="state = 'loaded'"
    @error="state = 'error'"
  />
  <div v-else class="flex aspect-[900/1549] w-full flex-col items-center justify-center gap-3 bg-neutral-900">
    <p class="text-sm text-neutral-400">第 {{ pageNumber }} 頁載入失敗</p>
    <button class="rounded-md bg-neutral-800 px-3 py-1.5 text-sm text-neutral-100 hover:bg-neutral-700" @click="retry">
      重試
    </button>
  </div>
</template>
