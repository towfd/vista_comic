<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from 'vue'
import type { AnalysisFailure, AnalysisWord } from '../api/client'
import { bubbleSourceText } from '../reader/overlay'
import { ANALYSIS_MODELS, useAnalysisStore, wordTranslation, type RequestProblem } from '../stores/analysis'
import { useCollectStore } from '../stores/collect'

// Everything this panel does is decided in the analysis store; this renders it
// and keeps what belongs to the screen: the waiting clock and the 重新查詢 check.
const analysis = useAnalysisStore()
const collect = useCollectStore()

/**
 * A word's 加入: 收卡 opens on top of this panel, filled as a bubble line is,
 * on the bubble's page. This panel stays mounted underneath, scroll and all.
 */
function collectWord(word: AnalysisWord) {
  if (!analysis.bubble) return
  collect.fillFromBubble({ sourceText: word.text, translation: wordTranslation(word), page: analysis.bubble.page })
}

const pending = computed(() => analysis.requesting || analysis.analysis?.status === 'pending')
const modelLabel = computed(() => ANALYSIS_MODELS.find((m) => m.id === analysis.model)?.label ?? analysis.model)

// Counted from when the analysis was queued, so reopening a bubble mid-run
// shows the whole wait, not just this visit's.
const now = ref(Date.now())
let ticker: ReturnType<typeof setInterval> | undefined
watch(
  pending,
  (waiting) => {
    clearInterval(ticker)
    now.value = Date.now()
    if (waiting) ticker = setInterval(() => (now.value = Date.now()), 1_000)
  },
  { immediate: true },
)
onUnmounted(() => clearInterval(ticker))
const waited = computed(() => {
  const since = analysis.analysis ? Date.parse(analysis.analysis.updatedAt) : now.value
  return Math.max(0, Math.floor((now.value - since) / 1_000))
})

const confirmingRefresh = ref(false)
watch(
  () => [analysis.bubble, analysis.model],
  () => (confirmingRefresh.value = false),
)
function refresh() {
  confirmingRefresh.value = false
  analysis.refresh()
}

const failed: Record<AnalysisFailure, string> = {
  error: '查詢失敗：呼叫模型時出錯了。',
  refused: '模型拒絕解析這一句。可以換一個模型試試。',
  invalid: '模型的回答不完整或對不上原句，沒辦法顯示。',
  interrupted: '伺服器在查詢途中重新啟動，這次查詢中斷了。',
}
const problems: Record<RequestProblem, string> = {
  capped: '今天的查詢次數已經用完了，明天再來。',
  unavailable: '連不上伺服器。',
  auth: '登入已經過期，請在另一個分頁重新整理後再試。',
  notFound: '伺服器找不到這次查詢。',
  unexpected: '伺服器拒絕了這次查詢。',
}
</script>

<template>
  <!--
    Where 收卡 sits -- along the bottom on a phone, beside the page column from
    the `dock` width up -- but one layer below it, so 收卡 opened from a word
    covers this and closing it reveals this untouched. Docked, it starts below
    the ＋收卡 button rather than under it.
  -->
  <aside
    v-if="analysis.open && analysis.bubble"
    data-analysis-panel
    aria-label="深入查詢"
    class="fixed inset-x-0 bottom-0 z-10 max-h-[70dvh] overflow-y-auto border-t border-neutral-800 bg-neutral-950/95 dock:inset-x-auto dock:top-16 dock:bottom-auto dock:left-[calc(50%+416px)] dock:max-h-[calc(100vh-5rem)] dock:w-[min(20rem,calc(50vw-432px))] dock:rounded-lg dock:border"
  >
    <div class="mx-auto max-w-[800px] p-4">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-sm font-medium text-neutral-100">深入查詢</h2>
        <button type="button" class="-m-2 p-2 text-xs text-neutral-400 hover:text-neutral-200" @click="analysis.close()">
          關閉
        </button>
      </div>

      <p class="mt-3 text-sm leading-relaxed text-neutral-300" lang="vi">{{ analysis.bubble.sourceText }}</p>
      <p class="mt-1 text-sm leading-relaxed text-neutral-100">{{ analysis.bubble.translation }}</p>

      <div class="mt-3 flex gap-1 rounded-md bg-neutral-900 p-1" role="radiogroup" aria-label="模型">
        <button
          v-for="m in ANALYSIS_MODELS"
          :key="m.id"
          type="button"
          role="radio"
          :aria-checked="analysis.model === m.id"
          class="flex-1 rounded px-2 py-1.5 text-xs"
          :class="analysis.model === m.id ? 'bg-sky-600 font-medium text-white' : 'text-neutral-400 hover:text-neutral-200'"
          @click="analysis.setModel(m.id)"
        >
          {{ m.label }}
        </button>
      </div>

      <div class="mt-4" aria-live="polite">
        <p v-if="pending" class="text-sm text-neutral-400">{{ modelLabel }} 解析中… {{ waited }} 秒</p>

        <div v-else-if="analysis.problem || analysis.analysis?.status === 'failed'" role="alert">
          <p class="text-sm text-amber-400">
            {{ analysis.problem ? problems[analysis.problem] : failed[analysis.analysis?.failure ?? 'error'] }}
          </p>
          <button
            type="button"
            class="mt-3 rounded-md bg-neutral-800 px-3 py-1.5 text-sm text-neutral-100 hover:bg-neutral-700"
            @click="analysis.retry()"
          >
            重試
          </button>
        </div>

        <template v-else-if="analysis.analysis?.result">
          <ol class="divide-y divide-neutral-800">
            <li v-for="(word, i) in analysis.analysis.result.words" :key="i" class="flex items-start gap-3 py-2.5">
              <div class="min-w-0 flex-1">
                <p class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                  <span class="font-medium text-neutral-50" lang="vi">{{ bubbleSourceText(word.text) }}</span>
                  <span v-if="word.hanViet" class="text-sm text-neutral-300">{{ word.hanViet }}</span>
                  <span class="rounded bg-neutral-800 px-1.5 py-0.5 text-[11px] text-neutral-400">{{ word.partOfSpeech }}</span>
                </p>
                <p class="mt-1 text-sm text-neutral-200">{{ word.meaning }}</p>
                <p v-if="word.note" class="mt-1 text-xs leading-relaxed text-neutral-400">{{ word.note }}</p>
              </div>
              <button
                type="button"
                class="shrink-0 rounded-md bg-sky-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-sky-500"
                :aria-label="`加入 ${word.text}`"
                @click="collectWord(word)"
              >
                加入
              </button>
            </li>
          </ol>

          <h3 class="mt-4 text-xs text-neutral-500">文法</h3>
          <p class="mt-1 text-sm leading-relaxed text-neutral-200">{{ analysis.analysis.result.grammar }}</p>
          <h3 class="mt-3 text-xs text-neutral-500">語氣</h3>
          <p class="mt-1 text-sm leading-relaxed text-neutral-200">{{ analysis.analysis.result.tone }}</p>

          <div class="mt-4 border-t border-neutral-800 pt-3">
            <button
              v-if="!confirmingRefresh"
              type="button"
              class="-m-2 p-2 text-xs text-neutral-400 hover:text-neutral-200"
              @click="confirmingRefresh = true"
            >
              重新查詢
            </button>
            <div v-else class="flex flex-wrap items-center gap-2">
              <p class="text-xs text-amber-400">會再呼叫一次 {{ modelLabel }}，取代目前的結果。</p>
              <button
                type="button"
                class="rounded-md bg-sky-600 px-3 py-1 text-xs font-medium text-white hover:bg-sky-500"
                @click="refresh"
              >
                確定
              </button>
              <button type="button" class="px-2 py-1 text-xs text-neutral-400 hover:text-neutral-200" @click="confirmingRefresh = false">
                取消
              </button>
            </div>
          </div>
        </template>
      </div>
    </div>
  </aside>
</template>
