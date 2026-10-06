<script setup lang="ts">
import { computed, watch } from 'vue'
import { useChaptersStore } from '../stores/chapters'
import { useComicsStore } from '../stores/comics'
import ErrorState from '../components/ErrorState.vue'
import ReaderPage from '../components/ReaderPage.vue'

const props = defineProps<{ comicId: string; chapterId: string }>()
const chapters = useChaptersStore()
const comics = useComicsStore()

const state = computed(() => chapters.entry(props.comicId, props.chapterId))
// The comic's title, if the chapter list was visited first. Arriving straight
// on a reader URL it is simply absent; it is not worth a second request.
const comicTitle = computed(() => comics.entry(props.comicId).data?.title)

watch(
  () => [props.comicId, props.chapterId] as const,
  ([comicId, chapterId]) => {
    if (!chapters.entry(comicId, chapterId).data) chapters.load(comicId, chapterId)
  },
  { immediate: true },
)

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

      <!-- The column: 800px at most, the full window below that. -->
      <div v-else class="mx-auto max-w-[800px]">
        <ReaderPage v-for="(src, index) in state.data.pages" :key="src" :src="src" :page-number="index + 1" />
      </div>

      <div class="mt-12 text-center">
        <p class="text-sm text-neutral-500">本話完</p>
        <RouterLink :to="backTo" class="mt-3 inline-block text-sm text-neutral-300 hover:text-neutral-100">
          回到章節列表
        </RouterLink>
      </div>
    </template>
  </main>
</template>
