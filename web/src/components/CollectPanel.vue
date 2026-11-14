<script setup lang="ts">
import { nextTick, onUnmounted, ref, watch } from 'vue'
import type { ApiErrorKind } from '../api/client'
import { useCollectStore, NOTE_LIMIT, SOURCE_TEXT_LIMIT } from '../stores/collect'
import AppIcon from './AppIcon.vue'
import { primaryLg } from './buttons'

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

/** DESIGN 15.4 input. */
const field =
  'mt-1.5 w-full resize-none rounded-card bg-paper px-4 py-3 text-body text-ink inset-ring-2 inset-ring-line-strong placeholder:text-ink-faint focus:inset-ring-3 focus:inset-ring-brand focus-visible:outline-none'
/** DESIGN 7.1 secondary at 36px, its touch area padded to 44. */
const secondarySm =
  "relative inline-flex h-9 shrink-0 items-center justify-center rounded-full bg-paper px-4 text-meta font-extrabold text-ink inset-ring-2 inset-ring-line before:absolute before:-inset-1 before:content-[''] hover:bg-blush active:bg-blush"
</script>

<template>
  <!--
    Floating over the manga, so each control carries shadow-float's white and
    ink rings (DESIGN 7.17). Placed to sit centred in the reader's 58px top
    bar while it shows; the bar slides away, these stay.
  -->
  <div
    v-if="!collect.open"
    class="fixed top-[calc(0.6875rem+env(safe-area-inset-top))] right-[calc(0.75rem+env(safe-area-inset-right))] z-20 flex items-center gap-3"
  >
    <p
      v-if="collect.added"
      class="inline-flex h-9 max-w-64 items-center gap-1.5 rounded-full bg-success-tint px-3.5 text-meta text-success shadow-float motion-safe:animate-[added-in_200ms_var(--ease-standard)]"
      role="status"
    >
      <AppIcon name="check" class="size-4" />
      <span class="truncate">已加入：<span lang="vi">{{ collect.added }}</span></span>
    </p>
    <!-- The reader's own controls, kept beside this button as the page scrolls. -->
    <slot name="controls" />
    <!--
      A primary sm, but its white ring would cover the thick lower edge, so
      pressing only darkens it (DESIGN 7.17).
    -->
    <button
      type="button"
      class="relative inline-flex h-9 shrink-0 items-center rounded-full bg-brand px-3.5 text-meta font-extrabold text-white shadow-float transition-colors duration-120 ease-standard before:absolute before:-inset-1 before:content-[''] hover:bg-brand-hover active:bg-brand-pressed"
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
    class="fixed inset-x-0 bottom-0 z-40 max-h-[70dvh] overflow-y-auto rounded-t-panel bg-paper px-4 pt-5 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-chrome-up max-dock:motion-safe:animate-[sheet-up_280ms_var(--ease-standard)] dock:inset-x-auto dock:top-3 dock:bottom-auto dock:left-[calc(50%+416px)] dock:max-h-[calc(100vh-1.5rem)] dock:w-[min(20rem,calc(50vw-432px))] dock:rounded-card dock:pb-4 dock:shadow-overlay dock:inset-ring-2 dock:inset-ring-line"
  >
    <!-- Along the bottom the contents keep to the page column's width. -->
    <div class="mx-auto max-w-reader">
      <!-- 收合 up here: a tall panel folds away without scrolling to its foot. -->
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="text-heading text-ink">收卡</h2>
          <p class="text-caption text-ink-soft">{{ collect.page === null ? '開始輸入後記下頁碼' : `第 ${collect.page} 頁` }}</p>
        </div>
        <button type="button" :class="secondarySm" @click="collect.collapse()">收合</button>
      </div>

      <!-- Side by side along the bottom, to stay short; stacked in the narrow column beside the page. -->
      <div class="mt-4 grid gap-3 sm:grid-cols-2 dock:grid-cols-1">
        <div>
          <label for="collect-source" class="block text-caption text-ink-soft">原文</label>
          <textarea
            id="collect-source"
            ref="sourceEl"
            lang="vi"
            rows="3"
            :maxlength="SOURCE_TEXT_LIMIT"
            :value="collect.sourceText"
            :class="[field, 'font-bold']"
            @input="collect.setSourceText(value($event))"
          />
          <p v-if="collect.sourceText.length >= COUNT_FROM" class="mt-1 text-right text-caption text-ink-faint tabular-nums">
            {{ collect.sourceText.length }} / {{ SOURCE_TEXT_LIMIT }}
          </p>
        </div>
        <div>
          <label for="collect-translation" class="block text-caption text-ink-soft">譯文</label>
          <textarea
            id="collect-translation"
            rows="3"
            :value="collect.translation"
            :class="field"
            @input="collect.setTranslation(value($event))"
          />
        </div>
      </div>

      <div class="mt-3">
        <label for="collect-note" class="block text-caption text-ink-soft">註解<span class="ml-1 text-ink-faint">選填</span></label>
        <textarea
          id="collect-note"
          rows="2"
          :maxlength="NOTE_LIMIT"
          :value="collect.note"
          :class="field"
          @input="collect.setNote(value($event))"
        />
      </div>

      <!--
        The card the deck already holds, in its own words: a line counts as the
        same whatever its case and spacing, so it may not look like what was
        typed -- and nothing typed here was saved onto it.
      -->
      <div
        v-if="collect.notice?.kind === 'exists'"
        class="mt-4 rounded-tile bg-warning-tint px-3.5 py-3 text-body text-warning"
        role="alert"
      >
        <p>已經收過了，沒有新增，也沒有改動原本的卡片。</p>
        <div class="mt-2 rounded-tile bg-paper p-3">
          <p class="text-body font-bold whitespace-pre-wrap text-ink" lang="vi">{{ collect.notice.card.sourceText }}</p>
          <p class="mt-1 text-meta whitespace-pre-wrap text-ink-soft">{{ collect.notice.card.translation }}</p>
          <p v-if="collect.notice.card.note" class="mt-2 text-meta break-words whitespace-pre-wrap text-ink-soft">
            <span class="text-caption text-ink-faint">註解：</span>{{ collect.notice.card.note }}
          </p>
        </div>
        <!-- Still in the field above, so it can be copied over on the card page. -->
        <p v-if="collect.notice.noteDropped" class="mt-2">註解沒有存進去，到字卡庫修改。</p>
        <p class="mt-2 flex items-center justify-between gap-2">
          <span class="text-caption text-ink-faint">{{ collect.notice.card.kind ? kinds[collect.notice.card.kind] : '未分類' }}</span>
          <!-- A new tab, as from a practice session: leaving the reader would discard what is typed here. -->
          <RouterLink
            :to="{ name: 'deck-card', params: { cardId: collect.notice.card.id } }"
            target="_blank"
            aria-label="到字卡庫修改（開新分頁）"
            class="inline-flex items-center gap-1 text-meta text-ink-soft underline decoration-line-strong decoration-2 underline-offset-4 hover:decoration-brand"
          >
            到字卡庫修改
            <AppIcon name="external" class="size-4" />
          </RouterLink>
        </p>
      </div>
      <p
        v-else-if="collect.notice?.kind === 'failed'"
        class="mt-4 rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger"
        role="alert"
      >
        {{ failed[collect.notice.error] }}
      </p>

      <div class="mt-4 flex gap-3">
        <button
          type="button"
          :disabled="!collect.canAdd"
          :aria-busy="collect.saving"
          :class="[primaryLg, 'flex-1']"
          @click="collect.add('word')"
        >
          加入單字
        </button>
        <button
          type="button"
          :disabled="!collect.canAdd"
          :aria-busy="collect.saving"
          :class="[primaryLg, 'flex-1']"
          @click="collect.add('sentence')"
        >
          加入句子
        </button>
      </div>

      <p class="mt-2 min-h-5 text-caption text-ink-faint" aria-live="polite">{{ collect.saving ? '儲存中…' : '' }}</p>
    </div>
  </aside>
</template>

<style>
@keyframes sheet-up {
  from {
    translate: 0 100%;
  }
}
@keyframes added-in {
  from {
    opacity: 0;
    translate: 0.5rem 0;
  }
}
</style>
