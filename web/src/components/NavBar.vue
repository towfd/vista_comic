<script setup lang="ts">
import { computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'

const route = useRoute()
const store = useDeckStore()
const { standing } = storeToRefs(store)

// The count is fetched behind whatever page is showing. A failure is never
// surfaced: the bar simply reads 練習 with no number, and the page under it
// is neither delayed nor told. Pages about cards load the deck themselves.
onMounted(() => {
  if (route.meta.section === 'library') store.load()
  document.addEventListener('visibilitychange', onVisibilityChange)
})
onUnmounted(() => document.removeEventListener('visibilitychange', onVisibilityChange))

// Coming back to the tab is the ordinary way a deck goes stale: the reader
// was on the phone. Listened for here because the bar is on every page that
// shows anything about cards, and absent from the reader, which shows nothing.
function onVisibilityChange() {
  if (document.visibilityState === 'visible') store.refresh()
}

const waitingCount = computed(() => standing.value?.remaining || null)

const linkClass = (section: string) =>
  `px-2 py-2 ${route.meta.section === section ? 'text-neutral-100' : 'text-neutral-400 hover:text-neutral-200'}`
</script>

<template>
  <nav class="border-b border-neutral-800">
    <div class="mx-auto flex max-w-6xl items-center gap-1 px-2 py-1 whitespace-nowrap sm:gap-3">
      <RouterLink to="/" class="px-2 py-2 font-semibold tracking-tight text-neutral-100">vista</RouterLink>
      <RouterLink to="/" :class="linkClass('library')" :aria-current="route.meta.section === 'library' ? 'page' : undefined">
        書庫
      </RouterLink>
      <RouterLink to="/deck" :class="linkClass('deck')" :aria-current="route.meta.section === 'deck' ? 'page' : undefined">
        字卡庫
      </RouterLink>
      <RouterLink
        to="/practice"
        :class="linkClass('practice')"
        :aria-current="route.meta.section === 'practice' ? 'page' : undefined"
      >
        練習
        <span
          v-if="waitingCount"
          class="ml-1 rounded-full bg-sky-600 px-2 py-0.5 text-xs font-medium text-white"
          :aria-label="`${waitingCount} 張等待複習`"
        >
          {{ waitingCount }}
        </span>
      </RouterLink>
    </div>
  </nav>
</template>
