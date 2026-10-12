<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'

const route = useRoute()
const store = useDeckStore()
const { standing } = storeToRefs(store)

// The count is fetched behind whatever page is showing. A failure is never
// surfaced: the bar simply reads 練習 with no number, and the page under it
// is neither delayed nor told. Practice pages load the deck themselves.
onMounted(() => {
  if (route.meta.section !== 'practice') store.load()
})

const waitingCount = computed(() => standing.value?.remaining || null)

const linkClass = (section: string) =>
  route.meta.section === section ? 'text-neutral-100' : 'text-neutral-400 hover:text-neutral-200'
</script>

<template>
  <nav class="border-b border-neutral-800">
    <div class="mx-auto flex max-w-6xl items-center gap-6 px-4 py-3">
      <RouterLink to="/" class="font-semibold tracking-tight text-neutral-100">vista</RouterLink>
      <RouterLink to="/" :class="linkClass('library')" :aria-current="route.meta.section === 'library' ? 'page' : undefined">
        書庫
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
