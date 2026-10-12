<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useDeckStore } from '../stores/deck'
import ErrorState from '../components/ErrorState.vue'

const store = useDeckStore()
const { loading, error, loaded, standing } = storeToRefs(store)

onMounted(() => store.load())
</script>

<template>
  <main class="mx-auto max-w-3xl px-4 py-8">
    <header class="mb-8 flex items-center justify-between">
      <h1 class="text-2xl font-semibold text-neutral-100">今天</h1>
      <!-- Leads nowhere until the settings page exists. -->
      <button disabled class="rounded-md px-3 py-1.5 text-sm text-neutral-500">⚙ 設定</button>
    </header>

    <p v-if="loading && !loaded" class="py-24 text-center text-neutral-400">載入中…</p>

    <!-- Even over a deck fetched earlier for the bar's count: this page states
         what is waiting now, and old numbers shown as current would be a guess. -->
    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <template v-else-if="standing">
      <div v-if="standing.empty === 'deckIsEmpty'" class="py-24 text-center">
        <p class="text-lg font-medium text-neutral-100">還沒有卡片</p>
        <p class="mt-2 text-sm text-neutral-400">在手機上閱讀時把單字或句子加入，就會出現在這裡。</p>
      </div>

      <div v-else-if="standing.empty === 'dayIsDone'" class="py-24 text-center">
        <p class="text-lg font-medium text-neutral-100">今天做完了</p>
        <p class="mt-2 text-sm text-neutral-400">到期的卡片都複習過了，今天的新卡也用完了。明天再來。</p>
      </div>

      <template v-else>
        <dl class="grid grid-cols-3 gap-3 text-center">
          <div class="rounded-md bg-neutral-900 px-2 py-5">
            <dd class="text-3xl font-semibold text-neutral-100">{{ standing.counts.due }}</dd>
            <dt class="mt-1 text-sm text-neutral-400">到期</dt>
          </div>
          <div class="rounded-md bg-neutral-900 px-2 py-5">
            <dd class="text-3xl font-semibold text-neutral-100">{{ standing.counts.fresh }}</dd>
            <dt class="mt-1 text-sm text-neutral-400">新卡</dt>
          </div>
          <div class="rounded-md bg-neutral-900 px-2 py-5">
            <dd class="text-3xl font-semibold text-neutral-100">{{ standing.counts.learning }}</dd>
            <dt class="mt-1 text-sm text-neutral-400">學習中</dt>
          </div>
        </dl>

        <!-- Starts nothing until the session exists. -->
        <button
          disabled
          class="mt-8 block w-full rounded-md bg-sky-600 px-4 py-3 text-center font-medium text-white opacity-50"
        >
          開始複習
        </button>
      </template>
    </template>
  </main>
</template>
