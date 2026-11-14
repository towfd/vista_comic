<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'
import { groupCards, scheduleDue, scheduleState, type CardGroupKey } from '../practice/library'
import { isOverdue, stateChipClass } from '../deck/cardState'
import type { LearningCard } from '../api/types'
import AppIcon from '../components/AppIcon.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { primaryMd } from '../components/buttons'

const store = useDeckStore()
const { cards, settings, loading, error, loaded, loadedAt } = storeToRefs(store)

const search = ref('')

onMounted(() => store.load())

const groups = computed(() => groupCards(cards.value, search.value))
const found = computed(() => groups.value.reduce((sum, group) => sum + group.cards.length, 0))

const headings: Record<CardGroupKey, string> = { word: '單字', sentence: '句子', unsorted: '未分類' }

const now = () => loadedAt.value ?? new Date()
const state = (card: LearningCard) => scheduleState(card, settings.value?.learningSteps ?? [])
const due = (card: LearningCard) => scheduleDue(card, now())
</script>

<template>
  <main class="mx-auto max-w-page px-4 pt-6 md:px-6">
    <header class="flex items-center gap-3 pl-1">
      <h1 class="text-page text-ink">字卡庫</h1>
      <span v-if="loaded" class="rounded-full bg-blush px-2.5 text-meta text-brand tabular-nums">共 {{ cards.length }} 張</span>
    </header>

    <LoadingState v-if="loading && !loaded" />

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <template v-else-if="loaded">
      <EmptyState
        v-if="cards.length === 0"
        icon="cards"
        title="還沒有卡片。"
        hint="在手機上閱讀時把單字或句子加入，就會出現在這裡。"
      >
        <template #actions>
          <RouterLink :to="{ name: 'library' }" :class="primaryMd">到書庫</RouterLink>
        </template>
      </EmptyState>

      <template v-else>
        <label
          class="mt-4 flex h-12 items-center gap-2 rounded-full bg-blush px-4 text-body focus-within:inset-ring-3 focus-within:inset-ring-brand"
        >
          <AppIcon name="search" class="size-5 text-ink-faint" />
          <input
            v-model="search"
            type="search"
            aria-label="搜尋卡片"
            placeholder="搜尋原文或譯文"
            autocomplete="off"
            class="h-full min-w-0 flex-1 bg-transparent text-ink outline-none placeholder:text-ink-faint focus-visible:outline-none"
          />
        </label>

        <div v-if="found === 0" class="mt-12 flex flex-col items-center gap-2 text-center">
          <AppIcon name="search" class="size-8 text-ink-faint" />
          <p class="text-meta break-words text-ink-soft">沒有符合「{{ search.trim() }}」的卡片。</p>
        </div>

        <template v-else>
          <!-- Native details: folding works from the keyboard with nothing written for it. -->
          <details v-for="group in groups" :key="group.key" open class="group">
            <summary
              class="flex cursor-pointer list-none items-center gap-2.5 px-1 pt-5.5 pb-3 select-none [&::-webkit-details-marker]:hidden"
            >
              <span class="text-heading text-ink">{{ headings[group.key] }}</span>
              <span class="rounded-full bg-blush px-2.5 text-meta text-brand tabular-nums">{{ group.cards.length }}</span>
              <AppIcon
                name="down"
                class="ml-auto size-5 -rotate-90 text-ink-faint transition-transform duration-120 ease-standard group-open:rotate-0"
              />
            </summary>
            <p v-if="group.cards.length === 0" class="px-1 pb-2 text-meta text-ink-faint">沒有符合的卡片。</p>
            <ul v-else class="flex flex-col gap-2.5">
              <li v-for="card in group.cards" :key="card.id">
                <RouterLink
                  :to="{ name: 'deck-card', params: { cardId: card.id } }"
                  class="block rounded-card bg-paper px-4 pt-3 pb-3.5 inset-ring-2 inset-ring-line transition-colors duration-120 active:bg-blush"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span :class="stateChipClass(card.state)">{{ state(card) }}</span>
                    <span
                      v-if="due(card)"
                      class="text-caption"
                      :class="isOverdue(card, now()) ? 'text-st-relearn' : 'text-ink-faint'"
                      >{{ due(card) }}</span
                    >
                  </div>
                  <p
                    class="mt-1.5 font-extrabold leading-title break-words text-ink"
                    :class="card.kind === 'sentence' ? 'line-clamp-3 text-label' : 'line-clamp-2 text-heading'"
                    lang="vi"
                  >
                    {{ card.sourceText }}
                  </p>
                  <p class="mt-0.5 line-clamp-2 text-meta break-words text-ink-soft">{{ card.translation }}</p>
                </RouterLink>
              </li>
            </ul>
          </details>
        </template>
      </template>
    </template>
  </main>
</template>
