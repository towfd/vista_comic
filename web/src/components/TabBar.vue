<script lang="ts">
// The count last on screen, kept across mounts: the bar is gone on sub-pages,
// and coming back to it with a different number -- a session answered, a
// deck refreshed meanwhile -- is exactly the change worth a bump.
let lastShown: number | null = null
</script>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'
import AppIcon, { type IconName } from './AppIcon.vue'

const route = useRoute()
const { standing } = storeToRefs(useDeckStore())

const tabs: { section: 'library' | 'deck' | 'practice'; to: string; label: string; icon: IconName }[] = [
  { section: 'library', to: '/', label: '書庫', icon: 'library' },
  { section: 'deck', to: '/deck', label: '字卡', icon: 'cards' },
  { section: 'practice', to: '/practice', label: '練習', icon: 'practice' },
]

// What a session started now would ask. Loading it is App.vue's job; a deck
// not fetched, or failed, simply shows no badge.
const waitingCount = computed(() => standing.value?.remaining || null)

const bumping = ref(false)
watch(
  waitingCount,
  (now) => {
    // Only a number replacing a number: the badge appearing or going is its
    // own motion, and the first count of a visit has nothing to differ from.
    if (now && lastShown && now !== lastShown) bumping.value = true
    lastShown = now
  },
  { immediate: true },
)

// The badge is drawn for the eye; a screen reader hears the count in the
// tab's own name.
const tabLabel = (section: string, label: string) =>
  section === 'practice' && waitingCount.value ? `${label}，${waitingCount.value} 張等待複習` : undefined
</script>

<template>
  <!-- Fixed, so it ignores the body's safe-area padding: it clears the Home bar itself. -->
  <nav
    aria-label="主要分頁"
    class="fixed inset-x-0 bottom-0 z-30 rounded-t-panel bg-paper pb-[env(safe-area-inset-bottom)] shadow-chrome-up"
  >
    <div class="mx-auto grid max-w-tabs grid-cols-3">
      <RouterLink
        v-for="tab in tabs"
        :key="tab.section"
        :to="tab.to"
        :aria-current="route.meta.section === tab.section ? 'page' : undefined"
        :aria-label="tabLabel(tab.section, tab.label)"
        class="group relative flex h-13 flex-col items-center justify-center gap-0.5 text-caption"
        :class="route.meta.section === tab.section ? 'text-brand' : 'text-ink-faint'"
      >
        <!-- The current tab differs by this block as well as by colour. -->
        <span
          class="grid h-7 w-14 place-items-center rounded-full transition-[scale,background-color] duration-120 ease-standard group-active:scale-92 motion-reduce:group-active:scale-100"
          :class="route.meta.section === tab.section ? 'bg-blush-strong' : 'group-active:bg-blush'"
        >
          <AppIcon :name="tab.icon" />
        </span>
        {{ tab.label }}
        <Transition leave-active-class="transition-[scale,opacity] duration-120 ease-standard" leave-to-class="scale-60 opacity-0">
          <span
            v-if="tab.section === 'practice' && waitingCount"
            aria-hidden="true"
            class="absolute -top-1 left-[calc(50%+10px)] h-5 min-w-5.5 rounded-full bg-sun px-1.5 text-center text-caption leading-5 font-black text-ink tabular-nums ring-2 ring-paper"
            :class="bumping && 'motion-safe:animate-bump'"
            @animationend="bumping = false"
          >
            {{ waitingCount }}
          </span>
        </Transition>
      </RouterLink>
    </div>
  </nav>
</template>
