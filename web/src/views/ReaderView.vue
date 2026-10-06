<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import type { ChapterDetail } from '../api/types'
import { useChaptersStore } from '../stores/chapters'
import { useComicsStore } from '../stores/comics'
import { currentPage, isScrollKey, resumeStartPage } from '../reader/progress'
import { createProgressSaver, type ProgressSaver } from '../reader/progressSaver'
import { nextChapter, START_AT_TOP_KEY, takeStartAtTopFlag } from '../reader/nextChapter'
import ErrorState from '../components/ErrorState.vue'
import ReaderPage from '../components/ReaderPage.vue'

const props = defineProps<{ comicId: string; chapterId: string }>()
const chapters = useChaptersStore()
const comics = useComicsStore()
const router = useRouter()

const state = computed(() => chapters.entry(props.comicId, props.chapterId))
// The comic's title, if the chapter list was visited first. Arriving straight
// on a reader URL it is simply absent; it is not worth a second request.
const comicTitle = computed(() => comics.entry(props.comicId).data?.title)

const pagesEl = ref<HTMLElement | null>(null)
const endEl = ref<HTMLElement | null>(null)

// ---- Progress -------------------------------------------------------------
// The rules live in reader/progress.ts and the timing in reader/progressSaver.ts;
// this component only feeds them DOM facts: which pages are visible, whether
// the reader has really scrolled, and when the reader is being left.

/** One per opened chapter; replaced (after a flush) when the chapter changes. */
let saver: ProgressSaver | null = null
let observer: IntersectionObserver | null = null
/** Inputs before the resume scroll are not the reader reading. */
let positioned = false
const visiblePages = new Set<number>()
let endVisible = false

/**
 * Whether this open should ignore the saved position and start at the top:
 * the next-chapter button leaves a flag in `history.state`. Read when the new
 * chapter's data is positioned, then removed (vue-router's own keys kept), so
 * reloading mid-chapter resumes from the saved position instead.
 */
function takeStartAtTop(): boolean {
  const { startAtTop, rest } = takeStartAtTopFlag(window.history.state)
  if (rest) window.history.replaceState(rest, '')
  return startAtTop
}

/**
 * Send the current position now. Called on every way out of the chapter; the
 * next-chapter button (ticket 03) calls it before navigating. The request is
 * tracked by the chapters store, so `chapters.savesSettled()` awaits it.
 */
function flushProgress(options: { keepalive?: boolean } = {}) {
  saver?.flush(options)
}

function stopObserving() {
  observer?.disconnect()
  observer = null
  visiblePages.clear()
  endVisible = false
}

function openChapter(comicId: string, chapterId: string) {
  // Leaving the previous chapter in place (a replace to another chapter
  // reuses this component) is a leave like any other.
  flushProgress()
  saver?.dispose()
  stopObserving()
  positioned = false
  saver = createProgressSaver((page, options) => chapters.saveProgress(comicId, chapterId, page, options))
  // Always a fresh fetch: a cached lastReadPage would resume at a stale page.
  chapters.load(comicId, chapterId)
}

function observe(pageCount: number) {
  observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const target = entry.target as HTMLElement
      if (target === endEl.value) {
        endVisible = entry.isIntersecting
      } else {
        const page = Number(target.dataset.page)
        if (entry.isIntersecting) visiblePages.add(page)
        else visiblePages.delete(page)
      }
    }
    saver?.update(currentPage(visiblePages, endVisible, pageCount))
  })
  pagesEl.value?.querySelectorAll<HTMLElement>('[data-page]').forEach((el) => observer?.observe(el))
  if (endEl.value) observer.observe(endEl.value)
}

function position(data: ChapterDetail) {
  const start = resumeStartPage({
    pageCount: data.pages.length,
    lastReadPage: data.lastReadPage,
    startAtTop: takeStartAtTop(),
  })
  const target = start === null ? null : pagesEl.value?.querySelector<HTMLElement>(`[data-page="${start}"]`)
  if (target) target.scrollIntoView({ block: 'start', behavior: 'instant' })
  else window.scrollTo({ top: 0, behavior: 'instant' })
  positioned = true
  observe(data.pages.length)
}

watch(
  () => [props.comicId, props.chapterId] as const,
  ([comicId, chapterId]) => openChapter(comicId, chapterId),
  { immediate: true },
)

// 'post': position once the pages are in the DOM, each holding its reserved
// box, so the target page's offset is already where it will stay.
watch(
  () => state.value.data,
  (data) => {
    stopObserving()
    positioned = false
    if (data) position(data)
  },
  { flush: 'post' },
)

// The gate: only a real input after positioning lets a position be written.
function onScrollInput() {
  if (positioned) saver?.openGate()
}
function onKeydown(event: KeyboardEvent) {
  if (isScrollKey(event.key)) onScrollInput()
}
function onVisibilityChange() {
  // Also what Chrome fires on closing the tab or reloading; keepalive lets the
  // request outlive the page.
  if (document.visibilityState === 'hidden') flushProgress({ keepalive: true })
}

onMounted(() => {
  window.addEventListener('wheel', onScrollInput, { passive: true })
  window.addEventListener('touchmove', onScrollInput, { passive: true })
  window.addEventListener('keydown', onKeydown)
  document.addEventListener('visibilitychange', onVisibilityChange)
})

onBeforeRouteLeave(() => {
  flushProgress()
})

onUnmounted(() => {
  window.removeEventListener('wheel', onScrollInput)
  window.removeEventListener('touchmove', onScrollInput)
  window.removeEventListener('keydown', onKeydown)
  document.removeEventListener('visibilitychange', onVisibilityChange)
  stopObserving()
  saver?.dispose()
  saver = null
})

// ---- Next chapter ---------------------------------------------------------
// The neighbour comes from the comic's chapter list; ChapterDetail has none.
// Arriving straight on a reader URL, the list is fetched in the background --
// the pages never wait for it, and the button simply appears once it lands.
watch(
  () => props.comicId,
  (comicId) => {
    const entry = comics.entry(comicId)
    if (!entry.data && !entry.loading) void comics.load(comicId)
  },
  { immediate: true },
)

const next = computed(() => nextChapter(comics.entry(props.comicId).data?.chapters, props.chapterId))

function openNext() {
  const target = next.value
  if (!target) return
  // With 「本話完」 visible this sends pageCount, marking the chapter read.
  flushProgress()
  // replace: after 5 -> 6 -> 7, browser back returns to the chapter list.
  router.replace({
    name: 'reader',
    params: { comicId: props.comicId, chapterId: target.id },
    state: { [START_AT_TOP_KEY]: true },
  })
}

const backTo = computed(() => ({ name: 'comic', params: { comicId: props.comicId } }))
</script>

<template>
  <main class="pb-24">
    <header class="mx-auto flex max-w-[800px] items-baseline gap-3 px-4 py-4">
      <RouterLink :to="backTo" class="text-sm text-neutral-400 hover:text-neutral-200">
        ← {{ comicTitle ?? '章節列表' }}
      </RouterLink>
      <h1 v-if="state.data" class="text-sm text-neutral-200">第 {{ state.data.number }} 話</h1>
    </header>

    <p v-if="state.loading && !state.data" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState
      v-else-if="state.error && !state.data"
      :kind="state.error"
      not-found-title="找不到這一話"
      @retry="chapters.load(comicId, chapterId)"
    >
      <template #actions>
        <RouterLink :to="backTo" class="rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700">
          回到章節列表
        </RouterLink>
      </template>
    </ErrorState>

    <template v-else-if="state.data">
      <p v-if="state.data.pages.length === 0" class="py-24 text-center text-neutral-400">這一話沒有頁面。</p>

      <!--
        The column: 800px at most, the full window below that. Each page sits in
        a wrapper that stays the same element whether its image is loading,
        loaded or failed -- the wrapper is what is observed and scrolled to.
      -->
      <div v-else ref="pagesEl" class="mx-auto max-w-[800px]">
        <div v-for="(src, index) in state.data.pages" :key="src" :data-page="index + 1">
          <ReaderPage :src="src" :page-number="index + 1" />
        </div>
      </div>

      <div ref="endEl" class="mt-12 flex flex-col items-center text-center">
        <p class="text-sm text-neutral-500">本話完</p>
        <button
          v-if="next"
          type="button"
          class="mt-4 rounded-md bg-sky-600 px-5 py-2.5 text-sm font-medium text-white hover:bg-sky-500"
          @click="openNext"
        >
          下一話 · 第 {{ next.number }} 話
        </button>
        <RouterLink :to="backTo" class="mt-3 text-sm text-neutral-300 hover:text-neutral-100">
          回到章節列表
        </RouterLink>
      </div>
    </template>
  </main>
</template>
