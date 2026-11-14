<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from 'vue'
import type { AnalysisFailure, AnalysisWord } from '../api/client'
import { bubbleSourceText } from '../reader/overlay'
import { ANALYSIS_MODELS, useAnalysisStore, wordTranslation, type RequestProblem } from '../stores/analysis'
import { useCollectStore } from '../stores/collect'
import { primaryLg, primarySm, secondaryMd, soft, textButton } from './buttons'

/** DESIGN 7.1 secondary at 36px, its touch area padded to 44. */
const secondarySm =
  "relative inline-flex h-9 shrink-0 items-center justify-center rounded-full bg-paper px-4 text-meta font-extrabold text-ink inset-ring-2 inset-ring-line before:absolute before:-inset-1 before:content-[''] hover:bg-blush active:bg-blush"

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
    the `dock` width up -- but one layer below it (z-39 against 收卡's z-40), so
    收卡 opened from a word covers this and closing it reveals this untouched.
    Docked, it starts below the ＋收卡 button rather than under it.
  -->
  <aside
    v-if="analysis.open && analysis.bubble"
    data-analysis-panel
    aria-label="深入查詢"
    class="fixed inset-x-0 bottom-0 z-39 max-h-[70dvh] overflow-y-auto rounded-t-panel bg-paper px-4 pt-5 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-chrome-up max-dock:motion-safe:animate-[sheet-up_280ms_var(--ease-standard)] dock:inset-x-auto dock:top-16 dock:bottom-auto dock:left-[calc(50%+416px)] dock:max-h-[calc(100vh-5rem)] dock:w-[min(20rem,calc(50vw-432px))] dock:rounded-card dock:pb-4 dock:shadow-overlay dock:inset-ring-2 dock:inset-ring-line"
  >
    <div class="mx-auto max-w-reader">
      <div class="flex items-start justify-between gap-3">
        <h2 class="text-heading text-ink">深入查詢</h2>
        <button type="button" :class="secondarySm" @click="analysis.close()">關閉</button>
      </div>

      <p class="mt-3 text-meta font-bold text-ink-soft" lang="vi">{{ analysis.bubble.sourceText }}</p>
      <p class="mt-1 text-body text-ink">{{ analysis.bubble.translation }}</p>

      <div class="mt-4 inline-flex max-w-full rounded-full bg-blush p-1" role="radiogroup" aria-label="模型">
        <button
          v-for="m in ANALYSIS_MODELS"
          :key="m.id"
          type="button"
          role="radio"
          :aria-checked="analysis.model === m.id"
          class="h-9 rounded-full px-3 text-meta text-ink-soft transition-colors duration-120 ease-standard hover:text-ink aria-checked:bg-brand aria-checked:text-white"
          @click="analysis.setModel(m.id)"
        >
          {{ m.label }}
        </button>
      </div>

      <div class="mt-4" aria-live="polite">
        <p v-if="analysis.looking" class="text-caption text-ink-faint">查詢中…</p>

        <div v-else-if="pending">
          <p class="text-meta text-ink-soft">{{ modelLabel }} 解析中… {{ waited }} 秒</p>
          <!-- How long it takes is unknown: the words above carry the wait, the bar only shows it is moving. -->
          <div class="mt-2 h-1 overflow-hidden rounded-full bg-blush-strong" aria-hidden="true">
            <div class="h-full w-[30%] rounded-full bg-brand motion-safe:animate-[analysis-slide_1.4s_ease-in-out_infinite]" />
          </div>
        </div>

        <!-- Nothing stored for this model: a call costs money, so it waits for the reader. -->
        <button v-else-if="!analysis.analysis && !analysis.problem" type="button" :class="primaryLg" @click="analysis.start()">
          用 {{ modelLabel }} 開始解析
        </button>

        <div v-else-if="analysis.problem || analysis.analysis?.status === 'failed'" role="alert">
          <p class="rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger">
            {{ analysis.problem ? problems[analysis.problem] : failed[analysis.analysis?.failure ?? 'error'] }}
          </p>
          <button type="button" :class="[secondaryMd, 'mt-3']" @click="analysis.retry()">重試</button>
        </div>

        <template v-else-if="analysis.analysis?.result">
          <ol class="divide-y divide-line">
            <li v-for="(word, i) in analysis.analysis.result.words" :key="i" class="flex items-start gap-3 py-2.5">
              <div class="min-w-0 flex-1">
                <p class="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span class="text-label font-extrabold text-ink" lang="vi">{{ bubbleSourceText(word.text) }}</span>
                  <span v-if="word.hanViet" class="text-meta text-ink-soft">{{ word.hanViet }}</span>
                  <span class="inline-flex h-6.5 items-center rounded-full bg-blush px-2.5 text-caption text-ink-soft">
                    {{ word.partOfSpeech }}
                  </span>
                </p>
                <p class="mt-1 text-body text-ink">{{ word.meaning }}</p>
                <p v-if="word.note" class="mt-1 text-caption text-ink-soft">{{ word.note }}</p>
              </div>
              <button type="button" :class="[soft, 'mt-0.5 shrink-0']" :aria-label="`加入 ${word.text}`" @click="collectWord(word)">
                加入
              </button>
            </li>
          </ol>

          <h3 class="mt-4 text-caption text-ink-faint">文法</h3>
          <p class="mt-1 text-body text-ink">{{ analysis.analysis.result.grammar }}</p>
          <h3 class="mt-3 text-caption text-ink-faint">語氣</h3>
          <p class="mt-1 text-body text-ink">{{ analysis.analysis.result.tone }}</p>

          <div class="mt-4 border-t border-line pt-3">
            <button v-if="!confirmingRefresh" type="button" :class="[textButton, '-ml-2']" @click="confirmingRefresh = true">
              重新查詢
            </button>
            <div v-else>
              <p class="rounded-tile bg-warning-tint px-3.5 py-3 text-body text-warning">會再呼叫一次 {{ modelLabel }}，取代目前的結果。</p>
              <div class="mt-3 flex items-center gap-2">
                <button type="button" :class="primarySm" @click="refresh">確定</button>
                <button type="button" :class="textButton" @click="confirmingRefresh = false">取消</button>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>
  </aside>
</template>

<style>
@keyframes sheet-up {
  from {
    translate: 0 100%;
  }
}
/* There and back across the track: the 30% slider travels 70% of the track, 233% of itself. */
@keyframes analysis-slide {
  50% {
    translate: 233% 0;
  }
}
</style>
