<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'
import { bubbleLayout, bubblesHeight, bubblesLabel, distributionLabel, dueTomorrow, stageDistribution } from '../practice/overview'
import type { CardState } from '../api/types'
import AppIcon from '../components/AppIcon.vue'
import EmptyState from '../components/EmptyState.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { primaryLg, primaryMd } from '../components/buttons'

const store = useDeckStore()
const { loading, error, loaded, standing, cards, loadedAt } = storeToRefs(store)

onMounted(() => store.load())

const bubbles = computed(() => (standing.value ? bubbleLayout(standing.value.counts) : []))

// Bubble colours say what each count is: due in the relearning red, new in
// the new-card blue, learning in amber -- the card library's own colours.
const bubbleTone = {
  due: 'bg-st-relearn-tint text-st-relearn inset-ring-3 inset-ring-st-relearn',
  fresh: 'bg-st-new-tint text-st-new inset-ring-3 inset-ring-st-new',
  learning: 'bg-st-learn-tint text-st-learn inset-ring-3 inset-ring-st-learn',
} as const

// Counted from the moment the held deck is true for, the same moment the
// counts above come from, so the two never disagree about which day it is.
const tomorrow = computed(() => (loadedAt.value ? dueTomorrow(cards.value, loadedAt.value) : 0))
const stages = computed(() => stageDistribution(cards.value))

const stageGraphic: Record<CardState, string> = {
  new: 'bg-st-new-graphic',
  learning: 'bg-st-learn-graphic',
  relearning: 'bg-st-relearn-graphic',
  review: 'bg-st-review-graphic',
}

const settingsButton =
  'inline-flex h-11 shrink-0 items-center gap-1.5 rounded-full bg-paper pr-3.5 pl-3 text-meta text-ink-soft inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush'
</script>

<template>
  <main class="mx-auto max-w-narrow px-4 pt-6">
    <header class="mb-4 flex items-center justify-between gap-3">
      <h1 class="text-page text-ink">今天</h1>
      <RouterLink :to="{ name: 'practice-settings' }" :class="settingsButton">
        <AppIcon name="settings" class="size-5" />
        設定
      </RouterLink>
    </header>

    <LoadingState v-if="loading && !loaded" />

    <!-- Even over a deck fetched earlier for the bar's count: this page states
         what is waiting now, and old numbers shown as current would be a guess. -->
    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <template v-else-if="standing">
      <EmptyState
        v-if="standing.empty === 'deckIsEmpty'"
        icon="cards"
        title="還沒有卡片"
        hint="在手機上閱讀時把單字或句子加入，就會出現在這裡。"
      >
        <template #actions>
          <RouterLink :to="{ name: 'library' }" :class="primaryMd">到書庫</RouterLink>
        </template>
      </EmptyState>

      <template v-else-if="standing.empty === 'dayIsDone'">
        <div class="px-4 pt-2 text-center">
          <div
            class="mx-auto grid size-21 -rotate-8 place-items-center rounded-full bg-sun text-ink ring-5 ring-paper outline-2 outline-offset-5 outline-blush-strong"
          >
            <AppIcon name="check" class="size-11 stroke-3" />
          </div>
          <p class="mt-4 text-headline text-ink">今天做完了</p>
          <p class="mt-1 text-meta text-ink-soft">到期的卡片都複習過了，今天的新卡也用完了。明天再來。</p>
        </div>

        <section class="mt-4.5 rounded-panel bg-blush px-4.5 py-4">
          <p class="flex items-center gap-2 rounded-tile bg-paper px-3.5 py-2 text-body text-ink-soft">
            <AppIcon name="calendar" class="size-5 text-brand" />
            明天到期
            <span class="ml-auto text-label font-black text-ink tabular-nums">{{ tomorrow }}</span>
            張
          </p>
        </section>

        <section class="mt-4.5 rounded-card bg-paper px-4.5 py-4 inset-ring-2 inset-ring-line" aria-labelledby="deck-stages-heading">
          <div class="flex items-center justify-between gap-3">
            <h2 id="deck-stages-heading" class="text-body text-ink">所有字卡</h2>
            <span class="text-meta text-ink-soft tabular-nums">{{ cards.length }} 張</span>
          </div>
          <div class="mt-3 flex h-4 gap-0.75" role="img" :aria-label="distributionLabel(stages)">
            <!-- An empty stage gets no segment: the smallest width would draw a zero as something. -->
            <span
              v-for="stage in stages.filter((s) => s.count > 0)"
              :key="stage.state"
              class="min-w-2 rounded-full"
              :class="stageGraphic[stage.state]"
              :style="{ flexGrow: stage.count, flexBasis: 0 }"
            />
          </div>
          <ul class="mt-3 grid grid-cols-2 gap-x-4.5 gap-y-1.5 text-meta text-ink-soft">
            <li v-for="stage in stages" :key="stage.state" class="flex items-center gap-2">
              <span class="size-2.5 shrink-0 rounded-full" :class="stageGraphic[stage.state]" aria-hidden="true" />
              {{ stage.label }}
              <span class="ml-auto text-body font-extrabold text-ink tabular-nums">{{ stage.count }}</span>
            </li>
          </ul>
        </section>
      </template>

      <section v-else class="mt-1 rounded-panel bg-blush px-5 pt-5.5 pb-6">
        <h2 class="text-headline text-ink">
          今天有 <span class="text-page font-black text-brand tabular-nums">{{ standing.remaining }}</span> 張要複習
        </h2>
        <div
          class="relative mt-2.5"
          :style="{ height: `${bubblesHeight(bubbles)}px` }"
          role="img"
          :aria-label="bubblesLabel(standing.counts)"
        >
          <div
            v-for="bubble in bubbles"
            :key="bubble.key"
            class="absolute flex flex-col items-center justify-center rounded-full text-caption"
            :class="bubbleTone[bubble.key]"
            :style="{
              left: `calc(50% + ${bubble.left}px)`,
              top: `${bubble.top}px`,
              width: `${bubble.diameter}px`,
              height: `${bubble.diameter}px`,
            }"
          >
            <span class="leading-none font-black tabular-nums" :class="bubble.numberSize">{{ bubble.count }}</span>
            <span class="mt-0.75">{{ bubble.label }}</span>
          </div>
        </div>
        <RouterLink :to="{ name: 'practice-session' }" :class="[primaryLg, 'mt-3.5']">開始複習</RouterLink>
      </section>
    </template>
  </main>
</template>
