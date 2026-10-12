<script setup lang="ts">
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import type { ApiErrorKind } from '../api/client'
import { useSessionStore } from '../stores/session'

// Putting a card right from the question that exposed it. Shown under the
// verdict only: the source text is not editable here or anywhere -- the
// backend refuses it -- so a misread card is deleted and collected again.

const session = useSessionStore()
const { question, saveState, fixed, fixing, fixError } = storeToRefs(session)

const open = ref(false)
const translation = ref('')
const confirmingDelete = ref(false)

watch(
  () => question.value?.token,
  () => {
    open.value = false
    confirmingDelete.value = false
  },
)
watch(open, (isOpen) => {
  if (isOpen) translation.value = question.value?.card.translation ?? ''
  confirmingDelete.value = false
})

/** Enter saves the translation -- but not the Enter that ends an input method's composition. */
function onTranslationKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter') return
  if (event.isComposing || event.keyCode === 229) return
  event.preventDefault()
  if (!event.repeat) session.fixTranslation(translation.value)
}

function onDelete() {
  if (!confirmingDelete.value) {
    confirmingDelete.value = true
    return
  }
  confirmingDelete.value = false
  session.deleteCardOnScreen()
}

const done: Record<string, string> = {
  translation: '譯文已更新。',
  kind: '類型已更新。',
  reset: '這張卡片已重設為新卡，會依每天的新卡額度再出現。',
  deleted: '這張卡片已刪除。',
}

const failed: Record<ApiErrorKind, string> = {
  unavailable: '連不上伺服器，卡片沒有變動。',
  auth: '登入已經過期，卡片沒有變動。請重新整理頁面。',
  notFound: '找不到這張卡片。',
  unexpected: '伺服器拒絕了這個修改，卡片沒有變動。',
}

const ended = () => fixed.value === 'deleted' || fixed.value === 'reset'
</script>

<template>
  <div v-if="question && saveState !== 'gone'" class="mt-8 border-t border-neutral-800 pt-4">
    <p v-if="fixed" class="mb-3 text-sm text-emerald-400" role="status">{{ done[fixed] }}</p>

    <template v-if="!ended()">
      <!-- Disabled, not hidden, until the answer is saved: a reset must never race the review it wipes. -->
      <button
        type="button"
        :disabled="saveState !== 'saved'"
        :aria-expanded="open"
        class="text-sm text-neutral-400 hover:text-neutral-200 disabled:opacity-40"
        @click="open = !open"
      >
        {{ open ? '收起' : '修正這張卡片' }}
      </button>

      <div v-if="open && saveState === 'saved'" class="mt-4 space-y-5">
        <div>
          <label for="fix-translation" class="block text-xs text-neutral-500">譯文</label>
          <div class="mt-1 flex gap-2">
            <input
              id="fix-translation"
              v-model="translation"
              type="text"
              autocomplete="off"
              :disabled="fixing"
              class="min-w-0 flex-1 rounded-md border border-neutral-700 bg-neutral-900 px-3 py-2 text-neutral-100 outline-none focus:border-sky-500"
              @keydown="onTranslationKeydown"
            />
            <button
              type="button"
              :disabled="fixing || translation.trim() === '' || translation.trim() === question.card.translation"
              class="shrink-0 rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700 disabled:opacity-40"
              @click="session.fixTranslation(translation)"
            >
              儲存譯文
            </button>
          </div>
        </div>

        <div>
          <p class="text-xs text-neutral-500">類型</p>
          <div class="mt-1 flex gap-2" role="group" aria-label="類型">
            <button
              v-for="option in [
                { kind: 'word', label: '單字' },
                { kind: 'sentence', label: '句子' },
              ] as const"
              :key="option.kind"
              type="button"
              :disabled="fixing"
              :aria-pressed="question.card.kind === option.kind"
              class="rounded-md px-4 py-2 text-sm disabled:opacity-40"
              :class="
                question.card.kind === option.kind
                  ? 'bg-sky-600 text-white'
                  : 'bg-neutral-800 text-neutral-100 hover:bg-neutral-700'
              "
              @click="session.fixKind(option.kind)"
            >
              {{ option.label }}
            </button>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            type="button"
            :disabled="fixing"
            class="rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700 disabled:opacity-40"
            @click="session.resetCardOnScreen()"
          >
            重設為新卡
          </button>
          <button
            type="button"
            :disabled="fixing"
            class="rounded-md px-4 py-2 text-sm disabled:opacity-40"
            :class="confirmingDelete ? 'bg-rose-600 text-white hover:bg-rose-500' : 'bg-neutral-800 text-rose-300 hover:bg-neutral-700'"
            @click="onDelete"
          >
            {{ confirmingDelete ? '確定刪除？無法復原' : '刪除卡片' }}
          </button>
          <button
            v-if="confirmingDelete"
            type="button"
            class="px-2 py-2 text-sm text-neutral-400 hover:text-neutral-200"
            @click="confirmingDelete = false"
          >
            取消
          </button>
        </div>

        <p class="text-xs text-neutral-500">原文不能修改。原文辨識錯誤的卡片請刪除，再到手機上重新收集。剛才的作答不會撤銷。</p>
      </div>
    </template>

    <p v-if="fixError" class="mt-3 text-sm text-amber-400" role="alert">{{ failed[fixError] }}</p>
  </div>
</template>
