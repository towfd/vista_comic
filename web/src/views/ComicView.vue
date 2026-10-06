<script setup lang="ts">
import { computed, watch } from 'vue'
import { useComicsStore } from '../stores/comics'
import ErrorState from '../components/ErrorState.vue'
import type { ChapterSummary } from '../api/types'

const props = defineProps<{ comicId: string }>()
const store = useComicsStore()
const state = computed(() => store.entry(props.comicId))

watch(
  () => props.comicId,
  (comicId) => {
    if (!store.entry(comicId).data) store.load(comicId)
  },
  { immediate: true },
)

// Every chapter title in the library is "Chapter N", which repeats the number
// in English. Shown only when it says something the number does not.
const extraTitle = (chapter: ChapterSummary) =>
  chapter.title && chapter.title !== `Chapter ${chapter.number}` ? chapter.title : null

// Only the states worth seeing are badged. Most chapters are unread (141 of
// 146 in one comic, all but 5 of 1162 in another), so an "unread" badge on
// every row would be noise; no badge means unread.
const badges: Record<string, { label: string; class: string }> = {
  reading: { label: '閱讀中', class: 'bg-sky-900/60 text-sky-200' },
  read: { label: '已讀', class: 'bg-neutral-800 text-neutral-400' },
}
</script>

<template>
  <main class="mx-auto max-w-3xl px-4 py-8">
    <RouterLink to="/" class="text-sm text-neutral-400 hover:text-neutral-200">← 書庫</RouterLink>

    <p v-if="state.loading && !state.data" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState
      v-else-if="state.error && !state.data"
      :kind="state.error"
      not-found-title="找不到這部漫畫"
      @retry="store.load(comicId)"
    >
      <template #actions>
        <RouterLink to="/" class="rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700">
          回到書庫
        </RouterLink>
      </template>
    </ErrorState>

    <template v-else-if="state.data">
      <header class="mt-4 mb-6 flex items-end gap-4">
        <img :src="state.data.coverUrl" :alt="state.data.title" class="h-32 w-24 rounded-md bg-neutral-800 object-cover" />
        <div>
          <h1 class="text-2xl font-semibold text-neutral-100">{{ state.data.title }}</h1>
          <p class="mt-1 text-sm text-neutral-400">{{ state.data.chapters.length }} 章</p>
        </div>
      </header>

      <p v-if="state.data.chapters.length === 0" class="py-24 text-center text-neutral-400">這部漫畫還沒有章節。</p>

      <ul v-else class="divide-y divide-neutral-800">
        <li v-for="chapter in state.data.chapters" :key="chapter.id">
          <RouterLink
            :to="{ name: 'reader', params: { comicId, chapterId: chapter.id } }"
            class="flex items-center gap-3 px-2 py-3 hover:bg-neutral-900"
          >
          <span class="text-neutral-100">第 {{ chapter.number }} 話</span>
          <span v-if="extraTitle(chapter)" class="truncate text-sm text-neutral-400">{{ extraTitle(chapter) }}</span>
          <span
            v-if="badges[chapter.readState]"
            class="rounded px-2 py-0.5 text-xs"
            :class="badges[chapter.readState]!.class"
          >
            {{ badges[chapter.readState]!.label }}
          </span>
            <span class="ml-auto shrink-0 text-xs text-neutral-500">{{ chapter.pageCount }} 頁</span>
          </RouterLink>
        </li>
      </ul>
    </template>
  </main>
</template>
