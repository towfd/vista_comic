<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useLibraryStore } from '../stores/library'
import ErrorState from '../components/ErrorState.vue'

const store = useLibraryStore()
const { comics, loading, error, loaded, refreshing, refreshFailed } = storeToRefs(store)

onMounted(() => {
  if (!loaded.value) store.load()
})
</script>

<template>
  <main class="mx-auto max-w-6xl px-4 py-8">
    <div v-if="loaded" class="mb-4 flex items-center justify-end gap-3">
      <p v-if="refreshFailed && !refreshing" class="text-sm text-amber-400">重新整理失敗，顯示的是先前的書庫。</p>
      <button
        type="button"
        class="rounded-md border border-neutral-700 px-4 py-2 text-sm text-neutral-200 hover:bg-neutral-800 disabled:opacity-50"
        :disabled="refreshing"
        @click="store.refresh()"
      >
        {{ refreshing ? '重新整理中…' : '重新整理' }}
      </button>
    </div>

    <p v-if="loading && !loaded" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <p v-else-if="loaded && comics.length === 0" class="py-24 text-center text-neutral-400">
      書庫裡還沒有漫畫。
    </p>

    <ul v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 sm:gap-6 md:grid-cols-4 lg:grid-cols-5">
      <li v-for="comic in comics" :key="comic.id">
        <RouterLink :to="{ name: 'comic', params: { comicId: comic.id } }" class="group block">
          <div class="aspect-[3/4] overflow-hidden rounded-md bg-neutral-800">
            <img
              :src="comic.coverUrl"
              :alt="comic.title"
              loading="lazy"
              class="h-full w-full object-cover transition group-hover:opacity-80"
            />
          </div>
          <p class="mt-2 line-clamp-2 text-sm text-neutral-100">{{ comic.title }}</p>
          <p class="text-xs text-neutral-400">{{ comic.chapterCount }} 章</p>
        </RouterLink>
      </li>
    </ul>
  </main>
</template>
