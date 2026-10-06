<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useLibraryStore } from '../stores/library'
import ErrorState from '../components/ErrorState.vue'

const store = useLibraryStore()
const { comics, loading, error, loaded } = storeToRefs(store)

onMounted(() => {
  if (!loaded.value) store.load()
})
</script>

<template>
  <main class="mx-auto max-w-6xl px-4 py-8">
    <h1 class="mb-6 text-2xl font-semibold text-neutral-100">書庫</h1>

    <p v-if="loading && !loaded" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <p v-else-if="loaded && comics.length === 0" class="py-24 text-center text-neutral-400">
      書庫裡還沒有漫畫。
    </p>

    <ul v-else class="grid grid-cols-2 gap-6 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
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
