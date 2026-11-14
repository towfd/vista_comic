<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import type { ChapterDetail } from '../api/types'
import { useAnalysisStore } from '../stores/analysis'
import { useChaptersStore } from '../stores/chapters'
import { useCollectStore } from '../stores/collect'
import { useComicsStore } from '../stores/comics'
import { currentPage, isScrollKey, resumeStartPage } from '../reader/progress'
import { createProgressSaver, type ProgressSaver } from '../reader/progressSaver'
import { nextChapter, START_AT_TOP_KEY, takeStartAtTopFlag } from '../reader/nextChapter'
import AnalysisPanel from '../components/AnalysisPanel.vue'
import AppIcon from '../components/AppIcon.vue'
import { iconButtonBlush, primaryLg, primaryMd, textButton } from '../components/buttons'
import CollectPanel from '../components/CollectPanel.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import ReaderPage from '../components/ReaderPage.vue'
import { loadNameTable, namesInLine, type NameEntry } from '../reader/names'
import { loadOverlay, type OverlayRegion } from '../reader/overlay'
import { initialHeader, trackHeader } from '../reader/headerReveal'

const props = defineProps<{ comicId: string; chapterId: string }>()
const chapters = useChaptersStore()
const comics = useComicsStore()
const collect = useCollectStore()
const analysis = useAnalysisStore()
const router = useRouter()

const state = computed(() => chapters.entry(props.comicId, props.chapterId))
// The comic's title, if the chapter list was visited first. Arriving straight
// on a reader URL it is simply absent; it is not worth a second request.
const comicTitle = computed(() => comics.entry(props.comicId).data?.title)
// What the top bar shows. Only for the eye: the folder name above stays the
// key for the OCR data and the name table.
const shownTitle = computed(() => {
  const comic = comics.entry(props.comicId).data
  return comic ? (comic.displayTitle ?? comic.title) : undefined
})

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
  // A line half typed belonged to the chapter being left, as does a line being studied.
  collect.enter(comicId, chapterId)
  analysis.close()
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
    const page = currentPage(visiblePages, endVisible, pageCount)
    saver?.update(page)
    // The page a card collected now would record.
    collect.setCurrentPage(page)
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
  // A space typed into the collecting panel is writing, not scrolling.
  if (event.target instanceof Element && event.target.closest('[data-collect-panel]')) return
  if (isScrollKey(event.key)) onScrollInput()
}
// The top bar slides away while reading down and back on a small scroll up
// (reader/headerReveal.ts): the way back out of a chapter, never far off.
const header = ref(initialHeader)
function onScroll() {
  header.value = trackHeader(header.value, window.scrollY)
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
  window.addEventListener('scroll', onScroll, { passive: true })
  document.addEventListener('visibilitychange', onVisibilityChange)
})

onBeforeRouteLeave(() => {
  flushProgress()
})

onUnmounted(() => {
  window.removeEventListener('wheel', onScrollInput)
  window.removeEventListener('touchmove', onScrollInput)
  window.removeEventListener('keydown', onKeydown)
  window.removeEventListener('scroll', onScroll)
  document.removeEventListener('visibilitychange', onVisibilityChange)
  stopObserving()
  saver?.dispose()
  saver = null
  collect.collapse()
  analysis.close()
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

// ---- Translation overlay ------------------------------------------------
// Tap a speech bubble to see its translation. One open at a time; a tap
// elsewhere or Esc closes it.
const overlay = ref(new Map<number, OverlayRegion[]>())
const selectedSegment = ref<string | null>(null)

// comic-ocr-data is keyed by the library folder name, which the API exposes as
// the comic's title; its episode is the chapter number.
watch(
  () => (state.value.data && comicTitle.value ? ([comicTitle.value, state.value.data.number] as const) : null),
  async (key) => {
    overlay.value = new Map()
    selectedSegment.value = null
    if (!key) return
    const result = await loadOverlay(key[0], key[1])
    if (state.value.data?.number === key[1] && comicTitle.value === key[0]) overlay.value = result
  },
  { immediate: true },
)

function closeOverlay() {
  selectedSegment.value = null
}

// Whether the boxes are outlined, remembered in this browser. Storage may be missing or refuse.
const HINTS_KEY = 'vista.overlayHints'
function rememberedHints(): boolean {
  try {
    return localStorage.getItem(HINTS_KEY) !== 'off'
  } catch {
    return true
  }
}
const showHints = ref(rememberedHints())
function toggleHints() {
  showHints.value = !showHints.value
  try {
    localStorage.setItem(HINTS_KEY, showHints.value ? 'on' : 'off')
  } catch {
    // Not remembered, still applied.
  }
}

/** The card's 加入句子: the card gives way to the collecting panel, filled from the bubble. */
function collectBubble(region: OverlayRegion, page: number) {
  closeOverlay()
  collect.fillFromBubble({ sourceText: region.source, translation: region.text, page })
}
/** The card's 深入查詢: the card gives way to the analysis panel, for the names in this line only. */
function analyseBubble(region: OverlayRegion, page: number) {
  if (region.text === null) return
  closeOverlay()
  analysis.openFor({
    sourceText: region.source,
    translation: region.text,
    page,
    names: namesInLine(nameTable.value, region.source),
  })
}

// The work's name table, for the analysis. Per work rather than per chapter.
const nameTable = ref<NameEntry[]>([])
watch(
  comicTitle,
  async (title) => {
    nameTable.value = []
    if (!title) return
    const table = await loadNameTable(title)
    if (comicTitle.value === title) nameTable.value = table
  },
  { immediate: true },
)

function onOverlayKey(event: KeyboardEvent) {
  if (event.key === 'Escape') closeOverlay()
}
onMounted(() => {
  window.addEventListener('click', closeOverlay)
  window.addEventListener('keydown', onOverlayKey)
})
onUnmounted(() => {
  window.removeEventListener('click', closeOverlay)
  window.removeEventListener('keydown', onOverlayKey)
})

const backTo = computed(() => ({ name: 'comic', params: { comicId: props.comicId } }))
</script>

<template>
  <!-- From 1024px the column stands on blush, so it has edges (DESIGN 7.17). -->
  <main class="min-h-dvh lg:bg-blush">
    <!--
      Held just under the status bar; hidden, it slides up behind the strip
      style.css lays under it -- 1rem past its own height, so its shadow goes
      too. Opaque: the manga never shows through. Below the collecting button,
      which stays.
    -->
    <div
      class="sticky top-[env(safe-area-inset-top)] z-10 rounded-b-panel bg-paper shadow-chrome-down transition-transform duration-200 ease-standard"
      :class="header.visible ? '' : '-translate-y-[calc(100%+1rem)]'"
    >
      <!-- Clear of the floating 標示 and ＋收卡, which sit over this corner until the window is wide. -->
      <header class="mx-auto flex h-14.5 max-w-reader items-center gap-2 pr-52 pl-2.5 lg:pr-3">
        <RouterLink :to="backTo" :class="iconButtonBlush" aria-label="回到章節列表">
          <AppIcon name="back" class="size-5.5" />
        </RouterLink>
        <div class="min-w-0 flex-1">
          <p class="truncate text-body leading-title font-extrabold text-ink" :lang="shownTitle ? 'vi' : undefined">
            {{ shownTitle ?? '章節列表' }}
          </p>
          <h1 v-if="state.data" class="text-caption text-ink-soft">第 {{ state.data.number }} 話</h1>
        </div>
      </header>
    </div>

    <!-- The page column: 800px at most, the full window below that. -->
    <div class="mx-auto min-h-dvh max-w-reader bg-paper pb-24">
      <LoadingState v-if="state.loading && !state.data" />

      <ErrorState
        v-else-if="state.error && !state.data"
        :kind="state.error"
        not-found-title="找不到這一話"
        @retry="chapters.load(comicId, chapterId)"
      >
        <template #actions="{ buttonClass }">
          <RouterLink :to="backTo" :class="buttonClass">回到章節列表</RouterLink>
        </template>
      </ErrorState>

      <template v-else-if="state.data">
        <EmptyState v-if="state.data.pages.length === 0" icon="book" title="這一話沒有頁面。">
          <template #actions>
            <RouterLink :to="backTo" :class="primaryMd">回到章節列表</RouterLink>
          </template>
        </EmptyState>

        <!--
          Each page sits in a wrapper that stays the same element whether its
          image is loading, loaded or failed -- the wrapper is what is observed
          and scrolled to.
        -->
        <div v-else ref="pagesEl">
          <div v-for="(src, index) in state.data.pages" :key="src" :data-page="index + 1">
            <ReaderPage
              :src="src"
              :page-number="index + 1"
              :regions="overlay.get(index + 1)"
              :selected-id="selectedSegment"
              :hints="showHints"
              @select="selectedSegment = $event"
              @collect="collectBubble($event, index + 1)"
              @analyse="analyseBubble($event, index + 1)"
            />
          </div>
        </div>

        <AnalysisPanel />
        <CollectPanel v-if="state.data.pages.length > 0">
          <!-- Only for a chapter that has boxes to outline. Floats over the manga, so shadow-float. -->
          <template v-if="overlay.size > 0" #controls>
            <button
              type="button"
              role="switch"
              :aria-checked="showHints"
              class="relative inline-flex h-9 shrink-0 items-center gap-2 rounded-full bg-paper px-3 text-meta text-ink-soft shadow-float before:absolute before:-inset-1 before:content-[''] hover:bg-blush"
              @click="toggleHints"
            >
              標示
              <span
                class="relative h-7 w-11 rounded-full transition-colors duration-120"
                :class="showHints ? 'bg-brand' : 'bg-line-strong'"
              >
                <span
                  class="absolute top-0.75 left-0.75 size-5.5 rounded-full bg-white transition-[translate] duration-120 ease-standard"
                  :class="showHints ? 'translate-x-4' : ''"
                />
              </span>
            </button>
          </template>
        </CollectPanel>

        <div ref="endEl" class="mt-12 flex flex-col items-center px-4 text-center">
          <p class="inline-block -rotate-3 rounded-full bg-sun px-3 py-0.5 text-caption text-ink">本話完</p>
          <button v-if="next" type="button" :class="[primaryLg, 'mt-6 max-w-90']" @click="openNext">
            下一話
            <span class="text-meta font-bold opacity-90">第 {{ next.number }} 話</span>
          </button>
          <RouterLink :to="backTo" :class="[textButton, next ? 'mt-2' : 'mt-4']">回到章節列表</RouterLink>
        </div>
      </template>
    </div>
  </main>
</template>
