<script setup lang="ts">
import { nextTick, onUnmounted, ref, watch } from 'vue'
import type { ApiErrorKind } from '../api/client'
import { useCollectStore, SOURCE_TEXT_LIMIT } from '../stores/collect'

// Everything this panel does is decided in the collect store; this only
// renders it and handles what belongs to the DOM: focus and a timer.
const collect = useCollectStore()

const sourceEl = ref<HTMLTextAreaElement | null>(null)

/** How close to the limit the count starts showing. */
const COUNT_FROM = SOURCE_TEXT_LIMIT - 40
/** How long the confirmation stays once the panel has gone. */
const ADDED_SHOWN_MS = 4_000

watch(
  () => collect.open,
  async (open) => {
    if (!open) return
    await nextTick()
    sourceEl.value?.focus()
  },
)

let addedTimer: ReturnType<typeof setTimeout> | undefined
watch(
  () => collect.added,
  (added) => {
    clearTimeout(addedTimer)
    if (added) addedTimer = setTimeout(() => collect.dismissAdded(), ADDED_SHOWN_MS)
  },
)
onUnmounted(() => clearTimeout(addedTimer))

// Each ends by saying what to do, because the same two buttons are the retry.
const failed: Record<ApiErrorKind, string> = {
  unavailable: '連不上伺服器，卡片沒有存進去。內容還在，請再按一次。',
  auth: '登入已經過期，卡片沒有存進去。請在另一個分頁重新整理後，回來再按一次。',
  notFound: '伺服器找不到收卡的位置，卡片沒有存進去。',
  unexpected: '伺服器拒絕了這張卡片，沒有存進去。',
}

const kinds = { word: '單字', sentence: '句子' } as const

const value = (event: Event) => (event.target as HTMLTextAreaElement).value
</script>

<template>
  <div v-if="!collect.open" class="fixed top-3 right-4 z-20 flex items-center gap-3">
    <p
      v-if="collect.added"
      class="max-w-[16rem] truncate rounded-md bg-neutral-900/95 px-3 py-2 text-sm text-emerald-400"
      role="status"
    >
      已加入：<span lang="vi">{{ collect.added }}</span>
    </p>
    <!-- The reader's own controls, kept beside this button as the page scrolls. -->
    <slot name="controls" />
    <button
      type="button"
      class="rounded-md bg-neutral-800/95 px-3 py-2 text-sm text-neutral-100 hover:bg-neutral-700"
      @click="collect.openPanel()"
    >
      ＋收卡
    </button>
  </div>

  <!--
    Fixed to the window, so the manga scrolls behind it and the page column
    never moves or resizes -- shifting it would move the scroll position and
    with it the page the reader is taken to be on. Beside the column from the
    `dock` width up; along the bottom below that, where it covers the foot of
    the manga only for as long as a card is being typed. One element for both,
    so resizing across the width keeps what is typed.
  -->
  <aside
    v-else
    data-collect-panel
    aria-label="收卡"
    class="fixed inset-x-0 bottom-0 z-20 max-h-[70dvh] overflow-y-auto border-t border-neutral-800 bg-neutral-950/95 dock:inset-x-auto dock:top-3 dock:bottom-auto dock:left-[calc(50%+416px)] dock:max-h-[calc(100vh-1.5rem)] dock:w-[min(20rem,calc(50vw-432px))] dock:rounded-lg dock:border"
  >
    <!-- Along the bottom the contents keep to the page column's width. -->
    <div class="mx-auto max-w-[800px] p-4">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="text-sm font-medium text-neutral-100">收卡</h2>
        <p class="text-xs text-neutral-500">{{ collect.page === null ? '開始輸入後記下頁碼' : `第 ${collect.page} 頁` }}</p>
      </div>

      <!-- Side by side along the bottom, to stay short; stacked in the narrow column beside the page. -->
      <div class="mt-4 grid gap-3 sm:grid-cols-2 dock:grid-cols-1">
        <div>
          <label for="collect-source" class="block text-xs text-neutral-400">原文</label>
          <textarea
            id="collect-source"
            ref="sourceEl"
            lang="vi"
            rows="3"
            :maxlength="SOURCE_TEXT_LIMIT"
            :value="collect.sourceText"
            class="mt-1 w-full resize-none rounded-md border border-neutral-700 bg-neutral-900 px-3 py-2 text-neutral-100 outline-none focus:border-sky-500"
            @input="collect.setSourceText(value($event))"
          />
          <p v-if="collect.sourceText.length >= COUNT_FROM" class="mt-1 text-right text-xs text-neutral-500">
            {{ collect.sourceText.length }} / {{ SOURCE_TEXT_LIMIT }}
          </p>
        </div>
        <div>
          <label for="collect-translation" class="block text-xs text-neutral-400">譯文</label>
          <textarea
            id="collect-translation"
            rows="3"
            :value="collect.translation"
            class="mt-1 w-full resize-none rounded-md border border-neutral-700 bg-neutral-900 px-3 py-2 text-neutral-100 outline-none focus:border-sky-500"
            @input="collect.setTranslation(value($event))"
          />
        </div>
      </div>

      <!--
        The card the deck already holds, in its own words: a line counts as the
        same whatever its case and spacing, so it may not look like what was
        typed -- and nothing typed here was saved onto it.
      -->
      <div v-if="collect.notice?.kind === 'exists'" class="mt-3 rounded-md border border-amber-900/60 p-3" role="alert">
        <p class="text-sm text-amber-400">已經收過了，沒有新增，也沒有改動原本的卡片。</p>
        <p class="mt-2 text-sm whitespace-pre-wrap text-neutral-100" lang="vi">{{ collect.notice.card.sourceText }}</p>
        <p class="mt-1 text-sm whitespace-pre-wrap text-neutral-400">{{ collect.notice.card.translation }}</p>
        <p class="mt-2 flex items-baseline justify-between gap-2 text-xs">
          <span class="text-neutral-500">{{ collect.notice.card.kind ? kinds[collect.notice.card.kind] : '未分類' }}</span>
          <!-- A new tab, as from a practice session: leaving the reader would discard what is typed here. -->
          <RouterLink
            :to="{ name: 'deck-card', params: { cardId: collect.notice.card.id } }"
            target="_blank"
            class="text-neutral-400 underline decoration-neutral-600 underline-offset-4 hover:text-neutral-200"
          >
            到字卡庫修改 ↗
          </RouterLink>
        </p>
      </div>
      <p v-else-if="collect.notice?.kind === 'failed'" class="mt-3 text-sm text-amber-400" role="alert">
        {{ failed[collect.notice.error] }}
      </p>

      <div class="mt-4 flex gap-2">
        <button
          type="button"
          :disabled="!collect.canAdd"
          class="flex-1 rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
          @click="collect.add('word')"
        >
          加入單字
        </button>
        <button
          type="button"
          :disabled="!collect.canAdd"
          class="flex-1 rounded-md bg-sky-600 px-3 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
          @click="collect.add('sentence')"
        >
          加入句子
        </button>
      </div>

      <div class="mt-3 flex items-center justify-between">
        <p class="text-xs text-neutral-500" aria-live="polite">{{ collect.saving ? '儲存中…' : '' }}</p>
        <button type="button" class="-m-2 p-2 text-xs text-neutral-400 hover:text-neutral-200" @click="collect.collapse()">收合</button>
      </div>
    </div>
  </aside>
</template>
