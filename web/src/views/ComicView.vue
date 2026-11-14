<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { continueChapter, useComicsStore } from '../stores/comics'
import AppIcon from '../components/AppIcon.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { iconButton, iconButtonBlush, primaryLg, primaryMd } from '../components/buttons'
import { takeArrivedByHistory } from '../chapters/arrival'
import { cellAriaLabel, cellState, chapterLabel, isLongLabel, scrollTargetFor, type CellState } from '../chapters/grid'

const props = defineProps<{ comicId: string }>()
const store = useComicsStore()
const state = computed(() => store.entry(props.comicId))
const continueTo = computed(() => (state.value.data ? continueChapter(state.value.data) : null))
const continueId = computed(() => continueTo.value?.id ?? null)
const name = computed(() => (state.value.data ? (state.value.data.displayTitle ?? state.value.data.title) : ''))

// Every visit revalidates: a cached copy renders at once and the fresh one
// (with the read states and Continue of what was just read) replaces it.
watch(
  () => props.comicId,
  (comicId) => {
    void store.load(comicId)
  },
  { immediate: true },
)

// ---- The sticker cover: fades in once loaded; a book icon if it fails. ----
const coverLoaded = ref(false)
const coverFailed = ref(false)

// ---- The number grid ----
const cellLooks: Record<CellState, string> = {
  unread: 'bg-paper font-extrabold text-ink inset-ring-2 inset-ring-line motion-reduce:active:bg-blush',
  read: 'bg-mist font-bold text-ink-faint motion-reduce:active:bg-blush',
  current:
    "bg-brand font-extrabold text-white shadow-edge-sm after:absolute after:-top-1 after:-right-1 after:size-3.5 after:rounded-full after:bg-sun after:ring-2 after:ring-paper after:content-[''] motion-reduce:active:bg-brand-pressed",
}

// ---- Opening at the current chapter ----
// Opened from the library (or the reader's back button, also a push), the page
// jumps so the current chapter sits 35% down the screen -- instantly, as a
// smooth scroll through 1162 chapters would sway for seconds. Reached by the
// browser's back/forward, the router has restored where the reader was, so the
// page leaves it alone. Only the first data counts: a background refresh
// arriving while the reader scrolls must not pull them away.
const grid = ref<HTMLElement | null>(null)
let jumpPending = !takeArrivedByHistory()

watch(
  () => state.value.data,
  async (data) => {
    if (!data || !jumpPending) return
    jumpPending = false
    await nextTick()
    // After the router's own scroll (to the top, for a push), which it applies
    // a few microtasks after this page is rendered.
    requestAnimationFrame(() => {
      const cell = grid.value?.querySelector<HTMLElement>('[data-current]')
      if (!cell) return
      const top = scrollTargetFor(cell.getBoundingClientRect().top + window.scrollY, window.innerHeight)
      if (top !== null) window.scrollTo({ top, behavior: 'instant' })
    })
  },
  { immediate: true },
)

// ---- The compact top bar ----
// The jump above takes the header, and its back button, off screen at once,
// and the home-screen app has no browser back button. Once the header has
// scrolled away above the screen, a slim bar with the back button and the
// title slides in; it leaves when the header comes back.
const header = ref<HTMLElement | null>(null)
const headerGone = ref(false)

watch(
  header,
  (el, _previous, onCleanup) => {
    headerGone.value = false
    if (!el) return
    const observer = new IntersectionObserver(([entry]) => {
      if (entry) headerGone.value = !entry.isIntersecting && entry.boundingClientRect.top < 0
    })
    observer.observe(el)
    onCleanup(() => observer.disconnect())
  },
  { flush: 'post' },
)
</script>

<template>
  <main>
    <!-- Zero height, so it takes no room; the bar inside overflows it. -->
    <div class="sticky top-[env(safe-area-inset-top)] z-20 h-0">
      <Transition
        enter-active-class="transition-transform duration-200 ease-standard"
        leave-active-class="transition-transform duration-200 ease-standard"
        enter-from-class="-translate-y-[calc(100%+1rem)]"
        leave-to-class="-translate-y-[calc(100%+1rem)]"
      >
        <div v-if="headerGone && state.data" class="rounded-b-panel bg-paper shadow-chrome-down">
          <div class="mx-auto flex h-14 max-w-wide items-center gap-3 px-4">
            <RouterLink to="/" :class="iconButtonBlush" aria-label="回到書庫">
              <AppIcon name="back" />
            </RouterLink>
            <p class="min-w-0 truncate text-body font-extrabold text-ink" lang="vi">{{ name }}</p>
          </div>
        </div>
      </Transition>
    </div>

    <ErrorState
      v-if="state.error && !state.data"
      :kind="state.error"
      not-found-title="找不到這部漫畫"
      class="pb-8"
      @retry="store.load(comicId)"
    >
      <template #actions="{ buttonClass }">
        <RouterLink to="/" :class="buttonClass">回到書庫</RouterLink>
      </template>
    </ErrorState>

    <template v-else>
      <!-- While loading, the same header as a skeleton: the back button works,
           the cover is a blank sticker, no title. -->
      <header ref="header" class="rounded-b-panel bg-blush">
        <div
          class="relative mx-auto max-w-wide px-6 pt-4 pb-6.5 text-center lg:flex lg:items-end lg:gap-8 lg:pt-16 lg:text-left"
        >
          <RouterLink to="/" :class="iconButton" class="absolute top-2 left-4" aria-label="回到書庫">
            <AppIcon name="back" />
          </RouterLink>

          <div
            class="mx-auto mt-3.5 aspect-3/4 w-31 rotate-3 overflow-hidden rounded-tile border-4 border-paper shadow-raised backface-hidden lg:mx-0 lg:mt-0 lg:w-40 lg:shrink-0"
            :class="coverFailed ? 'bg-mist text-ink-faint' : 'bg-blush-strong'"
            :aria-hidden="!state.data || coverFailed ? 'true' : undefined"
          >
            <div v-if="coverFailed" class="grid size-full place-items-center">
              <AppIcon name="book" class="size-8" />
            </div>
            <img
              v-else-if="state.data"
              :src="state.data.coverUrl"
              :alt="name"
              loading="eager"
              class="block size-full object-cover object-top transition-opacity duration-200"
              :class="coverLoaded ? 'opacity-100' : 'opacity-0'"
              @load="coverLoaded = true"
              @error="coverFailed = true"
            />
          </div>

          <div v-if="state.data" class="min-w-0 lg:flex-1">
            <h1 class="mt-4 text-heading font-extrabold break-words text-ink lg:mt-0" lang="vi">{{ name }}</h1>
            <p class="mt-0.5 text-meta text-ink-soft tabular-nums">{{ state.data.chapters.length }} 話</p>
            <RouterLink
              v-if="continueTo"
              :to="{ name: 'reader', params: { comicId, chapterId: continueTo.id } }"
              :class="primaryLg"
              class="mt-4 max-w-90 lg:w-auto lg:min-w-70"
            >
              繼續閱讀
              <span class="text-meta font-bold tabular-nums opacity-90">第 {{ continueTo.number }} 話</span>
            </RouterLink>
          </div>
        </div>
      </header>

      <LoadingState v-if="!state.data" />

      <EmptyState v-else-if="state.data.chapters.length === 0" icon="book" title="這部漫畫還沒有章節。" class="pb-8">
        <template #actions>
          <!-- The screen's only action, so it is the primary one (DESIGN 7.15). -->
          <RouterLink to="/" :class="primaryMd">回到書庫</RouterLink>
        </template>
      </EmptyState>

      <section v-else class="mx-auto max-w-wide px-4 pt-4.5 pb-8" aria-labelledby="chapters-heading">
        <div class="flex items-center justify-between gap-3 px-1 pb-3">
          <h2 id="chapters-heading" class="text-heading text-ink">章節</h2>
          <ul class="flex gap-3 text-caption text-ink-soft">
            <li class="flex items-center gap-1.25">
              <span class="size-3 rounded-[4px] bg-mist" aria-hidden="true" />看過
            </li>
            <li class="flex items-center gap-1.25">
              <span class="size-3 rounded-[4px] bg-brand" aria-hidden="true" />正在看
            </li>
            <li class="flex items-center gap-1.25">
              <span class="size-3 rounded-[4px] bg-paper inset-ring-2 inset-ring-line" aria-hidden="true" />還沒看
            </li>
          </ul>
        </div>

        <!-- Every chapter at once, in reading order: 1162 cells is about 233
             rows, and iOS's status-bar tap takes the reader back to the top. -->
        <ol ref="grid" class="grid grid-cols-5 gap-2.5 sm:grid-cols-[repeat(auto-fill,minmax(4.5rem,1fr))]">
          <li v-for="chapter in state.data.chapters" :key="chapter.id">
            <RouterLink
              :to="{ name: 'reader', params: { comicId, chapterId: chapter.id } }"
              :aria-label="cellAriaLabel(chapter, continueId)"
              :data-current="cellState(chapter, continueId) === 'current' || undefined"
              class="relative grid h-13 place-items-center rounded-tile tabular-nums transition-transform duration-120 ease-standard hover:outline-2 hover:outline-brand-vivid active:scale-94 motion-reduce:active:scale-100"
              :class="[
                cellLooks[cellState(chapter, continueId)],
                isLongLabel(chapterLabel(chapter.number)) ? 'text-body' : 'text-label',
              ]"
            >
              {{ chapterLabel(chapter.number) }}
            </RouterLink>
          </li>
        </ol>
      </section>
    </template>
  </main>
</template>
