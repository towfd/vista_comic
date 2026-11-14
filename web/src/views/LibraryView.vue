<script setup lang="ts">
import { computed, onMounted, reactive, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useLibraryStore } from '../stores/library'
import { useComicsStore } from '../stores/comics'
import type { ComicSummary } from '../api/types'
import { continueTarget, mostRecentlyRead, progressPercent } from '../library/continueReading'
import AppIcon from '../components/AppIcon.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { iconButton, primaryMd } from '../components/buttons'

const store = useLibraryStore()
const { comics, loading, error, loaded, refreshing, refreshFailed } = storeToRefs(store)
const comicsStore = useComicsStore()

onMounted(() => {
  if (!loaded.value) store.load()
})

const titleOf = (comic: { title: string; displayTitle: string | null }) => comic.displayTitle ?? comic.title

// 繼續看: the comic read last. The list does not say which chapter number
// that is or how far along it sits, so the comic's detail is fetched (and
// revalidated on each visit); until it arrives the card shows no numbers.
const continueComic = computed(() => mostRecentlyRead(comics.value))
watch(
  () => continueComic.value?.id,
  (comicId) => {
    if (comicId) comicsStore.load(comicId)
  },
  { immediate: true },
)
const continueTo = computed(() => {
  const comic = continueComic.value
  return comic ? continueTarget(comic, comicsStore.entry(comic.id).data) : null
})

function chapterLine(comic: ComicSummary): { text: string; reading: boolean } {
  const progress = comic.id === continueComic.value?.id ? continueTo.value?.progress : null
  if (progress) return { text: `看到第 ${progress.number} / ${progress.total} 話`, reading: true }
  return { text: `${comic.chapterCount} 話`, reading: false }
}

// Covers fade in once loaded and fall back to a book on a failed load
// (page-design-spec 5.2, 5.3). Keyed by URL: the sticker and the shelf cell
// of the same comic load the same image.
const covers = reactive<Record<string, 'loaded' | 'failed'>>({})
</script>

<template>
  <main>
    <!-- The blush header runs the full width; its content stays on the shelf's column. -->
    <header class="rounded-b-panel bg-blush pb-5">
      <div class="mx-auto max-w-shelf">
        <div class="flex items-center justify-between pt-2 pr-4 pb-3 pl-5 md:pr-6 md:pl-7">
          <h1 class="text-page text-ink">書庫</h1>
          <button
            v-if="loaded"
            type="button"
            :class="iconButton"
            :disabled="refreshing"
            :aria-label="refreshing ? '重新整理中…' : '重新整理'"
            :aria-busy="refreshing"
            @click="store.refresh()"
          >
            <AppIcon name="refresh" :class="refreshing && 'motion-safe:animate-spin motion-reduce:opacity-50'" />
          </button>
        </div>

        <p
          v-if="loaded && refreshFailed && !refreshing"
          role="alert"
          class="mx-4 mb-3 rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger md:mx-6"
        >
          重新整理失敗，顯示的是先前的書庫。
        </p>

        <article
          v-if="loaded && continueComic && continueTo"
          class="mx-4 grid grid-cols-[6rem_1fr] gap-4 rounded-card bg-paper p-4 sm:max-w-narrow md:mx-6"
        >
          <RouterLink
            :to="{ name: 'comic', params: { comicId: continueComic.id } }"
            class="mt-1 block self-start rounded-tile"
            tabindex="-1"
            aria-hidden="true"
          >
            <div
              class="relative grid aspect-3/4 -rotate-4 place-items-center overflow-hidden rounded-tile border-4 border-paper bg-blush-strong shadow-raised backface-hidden"
              :class="covers[continueComic.coverUrl] === 'failed' && 'bg-mist text-ink-faint'"
            >
              <AppIcon v-if="covers[continueComic.coverUrl] === 'failed'" name="book" class="size-8" />
              <img
                v-else
                :src="continueComic.coverUrl"
                :alt="titleOf(continueComic)"
                loading="eager"
                class="absolute inset-0 size-full object-cover object-top transition-opacity duration-200 motion-reduce:transition-none"
                :class="covers[continueComic.coverUrl] === 'loaded' ? 'opacity-100' : 'opacity-0'"
                @load="covers[continueComic.coverUrl] = 'loaded'"
                @error="covers[continueComic.coverUrl] = 'failed'"
              />
            </div>
          </RouterLink>
          <div class="min-w-0">
            <span class="inline-block rounded-full bg-sun px-2.5 text-caption text-ink">繼續看</span>
            <RouterLink
              :to="{ name: 'comic', params: { comicId: continueComic.id } }"
              class="mt-1.5 line-clamp-3 rounded-tile text-body leading-title font-extrabold text-ink"
            >
              {{ titleOf(continueComic) }}
            </RouterLink>
          </div>

          <div class="col-span-full flex items-center gap-3.5">
            <div v-if="continueTo.progress" class="min-w-0 flex-1">
              <div
                class="h-2.5 overflow-hidden rounded-full bg-paper inset-ring-2 inset-ring-line"
                role="progressbar"
                aria-label="閱讀進度"
                aria-valuemin="0"
                :aria-valuenow="continueTo.progress.position"
                :aria-valuemax="continueTo.progress.total"
              >
                <div
                  class="h-full rounded-full bg-brand-vivid transition-[width] duration-200 ease-standard"
                  :style="{ width: `${progressPercent(continueTo.progress)}%` }"
                />
              </div>
              <p class="mt-1.5 flex justify-between gap-2 text-caption text-ink-soft tabular-nums">
                <span>看到第 {{ continueTo.progress.number }} 話</span>
                <span>{{ continueTo.progress.position }} / {{ continueTo.progress.total }}</span>
              </p>
            </div>
            <RouterLink
              :to="{ name: 'reader', params: { comicId: continueComic.id, chapterId: continueTo.chapterId } }"
              :aria-label="continueTo.progress ? `繼續閱讀第 ${continueTo.progress.number} 話` : '繼續閱讀'"
              class="ml-auto grid size-13 shrink-0 place-items-center rounded-full bg-brand text-white shadow-edge-sm transition-[translate,box-shadow,background-color] duration-120 ease-standard hover:bg-brand-hover active:translate-y-0.5 active:bg-brand-pressed active:shadow-edge-pressed motion-reduce:active:translate-y-0"
            >
              <!-- Filled, unlike the line icons: the preview's play button. -->
              <svg viewBox="0 0 24 24" class="ml-0.75 size-5" fill="currentColor" aria-hidden="true">
                <path d="M7 4.5v15l13-7.5z" />
              </svg>
            </RouterLink>
          </div>
        </article>
      </div>
    </header>

    <div class="mx-auto max-w-shelf">
      <LoadingState v-if="loading && !loaded" />

      <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

      <EmptyState v-else-if="loaded && comics.length === 0" icon="book" title="書庫裡還沒有漫畫。">
        <template #actions>
          <button type="button" :class="primaryMd" :aria-busy="refreshing" @click="store.refresh()">
            {{ refreshing ? '重新整理中…' : '重新整理' }}
          </button>
        </template>
      </EmptyState>

      <section v-else-if="loaded" aria-labelledby="library-all">
        <div class="flex items-center gap-2.5 px-5 pt-5.5 pb-3 md:px-7">
          <h2 id="library-all" class="text-heading text-ink">全部漫畫</h2>
          <span class="rounded-full bg-blush px-2.5 text-meta text-brand tabular-nums">{{ comics.length }} 部</span>
        </div>

        <ul class="grid grid-cols-2 gap-x-3.5 gap-y-5 px-4 sm:grid-cols-3 md:px-6 lg:grid-cols-4 xl:grid-cols-5">
          <li v-for="comic in comics" :key="comic.id" class="min-w-0">
            <RouterLink
              :to="{ name: 'comic', params: { comicId: comic.id } }"
              class="group block rounded-card focus-visible:outline-none"
            >
              <!-- Shelf cover: no tilt, no white edge, no shadow; a faint inner line keeps white covers off the page. -->
              <div
                class="relative grid aspect-3/4 place-items-center overflow-hidden rounded-card bg-blush-strong transition-[scale] duration-120 ease-standard group-hover:outline-2 group-hover:outline-brand-vivid group-focus-visible:outline-3 group-focus-visible:outline-offset-2 group-focus-visible:outline-brand group-active:scale-97 motion-reduce:group-active:scale-100 after:absolute after:inset-0 after:rounded-card after:inset-ring-1 after:inset-ring-ink/8"
                :class="covers[comic.coverUrl] === 'failed' && 'bg-mist text-ink-faint'"
              >
                <AppIcon v-if="covers[comic.coverUrl] === 'failed'" name="book" class="size-8" />
                <img
                  v-else
                  :src="comic.coverUrl"
                  :alt="titleOf(comic)"
                  loading="lazy"
                  class="absolute inset-0 size-full object-cover object-top transition-opacity duration-200 motion-reduce:transition-none"
                  :class="covers[comic.coverUrl] === 'loaded' ? 'opacity-100' : 'opacity-0'"
                  @load="covers[comic.coverUrl] = 'loaded'"
                  @error="covers[comic.coverUrl] = 'failed'"
                />
              </div>
              <p class="mt-2.5 line-clamp-2 text-body leading-title font-extrabold break-words text-ink">
                {{ titleOf(comic) }}
              </p>
              <p
                class="mt-0.5 text-meta tabular-nums"
                :class="chapterLine(comic).reading ? 'text-brand' : 'text-ink-soft'"
              >
                {{ chapterLine(comic).text }}
              </p>
            </RouterLink>
          </li>
        </ul>
      </section>
    </div>
  </main>
</template>
