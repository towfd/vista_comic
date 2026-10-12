<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'
import { groupCards, scheduleSummary, type CardGroupKey } from '../practice/library'
import ErrorState from '../components/ErrorState.vue'

const store = useDeckStore()
const { cards, settings, loading, error, loaded, loadedAt } = storeToRefs(store)

const search = ref('')

onMounted(() => store.load())

const groups = computed(() => groupCards(cards.value, search.value))
const found = computed(() => groups.value.reduce((sum, group) => sum + group.cards.length, 0))

const headings: Record<CardGroupKey, string> = { word: '單字', sentence: '句子', unsorted: '未分類' }

const summary = (card: (typeof cards.value)[number]) =>
  scheduleSummary(card, settings.value?.learningSteps ?? [], loadedAt.value ?? new Date())
</script>

<template>
  <main class="mx-auto max-w-3xl px-4 py-8">
    <header class="mb-6 flex items-baseline justify-between gap-4">
      <h1 class="text-2xl font-semibold text-neutral-100">字卡庫</h1>
      <p v-if="loaded" class="text-sm text-neutral-400">共 {{ cards.length }} 張</p>
    </header>

    <p v-if="loading && !loaded" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <template v-else-if="loaded">
      <p v-if="cards.length === 0" class="py-24 text-center text-neutral-400">
        還沒有卡片。在手機上閱讀時把單字或句子加入，就會出現在這裡。
      </p>

      <template v-else>
        <input
          v-model="search"
          type="search"
          aria-label="搜尋卡片"
          placeholder="搜尋原文或譯文"
          autocomplete="off"
          class="mb-6 w-full rounded-md border border-neutral-700 bg-neutral-900 px-4 py-2.5 text-neutral-100 outline-none placeholder:text-neutral-500 focus:border-sky-500"
        />

        <p v-if="found === 0" class="py-16 text-center text-neutral-400">沒有符合「{{ search.trim() }}」的卡片。</p>

        <template v-else>
          <!-- Native details: folding works from the keyboard with nothing written for it. -->
          <details v-for="group in groups" :key="group.key" open class="mb-6">
            <summary class="cursor-pointer py-2 text-sm font-medium text-neutral-300 select-none">
              {{ headings[group.key] }}
              <span class="ml-1 text-neutral-500">{{ group.cards.length }}</span>
            </summary>
            <p v-if="group.cards.length === 0" class="py-3 text-sm text-neutral-500">沒有符合的卡片。</p>
            <ul v-else class="divide-y divide-neutral-800">
              <li v-for="card in group.cards" :key="card.id">
                <RouterLink
                  :to="{ name: 'deck-card', params: { cardId: card.id } }"
                  class="-mx-2 block rounded-md px-2 py-3 hover:bg-neutral-900"
                >
                  <p class="line-clamp-2 text-neutral-100" lang="vi">{{ card.sourceText }}</p>
                  <p class="mt-0.5 line-clamp-2 text-sm text-neutral-400">{{ card.translation }}</p>
                  <p class="mt-1 text-xs text-neutral-500">{{ summary(card) }}</p>
                </RouterLink>
              </li>
            </ul>
          </details>
        </template>
      </template>
    </template>
  </main>
</template>
