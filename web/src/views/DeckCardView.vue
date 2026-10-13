<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { ApiError, type ApiErrorKind, type CardCorrection } from '../api/client'
import { useDeckStore } from '../stores/deck'
import { scheduleSummary } from '../practice/library'
import ErrorState from '../components/ErrorState.vue'

const props = defineProps<{ cardId: string }>()

const router = useRouter()
const store = useDeckStore()
const { cards, settings, loading, error, loaded, loadedAt } = storeToRefs(store)

const id = computed(() => Number(props.cardId))
const card = computed(() => cards.value.find((held) => held.id === id.value) ?? null)

const translation = ref('')
const working = ref(false)
const done = ref<string | null>(null)
const failure = ref<ApiErrorKind | null>(null)
// Which of the two actions that cannot be taken back is waiting for a second press.
const confirming = ref<'reset' | 'delete' | null>(null)

// Fetched fresh on arrival: this page changes what the phone also holds, and
// should start from what is true now rather than from a copy kept for a count.
onMounted(() => store.load())

watch(
  () => card.value?.translation,
  (text) => {
    translation.value = text ?? ''
  },
  { immediate: true },
)

const summary = computed(() =>
  card.value ? scheduleSummary(card.value, settings.value?.learningSteps ?? [], loadedAt.value ?? new Date()) : '',
)

const unchanged = computed(() => translation.value.trim() === '' || translation.value.trim() === card.value?.translation)

const failed: Record<ApiErrorKind, string> = {
  unavailable: '連不上伺服器，卡片沒有變動。',
  auth: '登入已經過期，卡片沒有變動。請重新整理頁面。',
  notFound: '找不到這張卡片。',
  unexpected: '伺服器拒絕了這個修改，卡片沒有變動。',
}

/** Run one action, say what happened, and leave if the card is no longer there. */
async function run(action: () => Promise<'done' | 'gone'>, message: string, leaves = false) {
  if (working.value) return
  working.value = true
  done.value = null
  failure.value = null
  confirming.value = null
  try {
    const result = await action()
    if (leaves || result === 'gone') router.replace({ name: 'deck' })
    else done.value = message
  } catch (e) {
    failure.value = e instanceof ApiError ? e.kind : 'unexpected'
  } finally {
    working.value = false
  }
}

const correct = (correction: CardCorrection, message: string) => run(() => store.correctCard(id.value, correction), message)

function saveTranslation() {
  if (!unchanged.value) correct({ translation: translation.value.trim() }, '譯文已更新。')
}

/** Enter saves -- but not the Enter that picks a candidate from a Chinese input method. */
function onTranslationKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter') return
  if (event.isComposing || event.keyCode === 229) return
  event.preventDefault()
  if (!event.repeat) saveTranslation()
}

function setKind(kind: 'word' | 'sentence') {
  if (kind !== card.value?.kind) correct({ kind }, '類型已更新。')
}

/** The first press asks; the second, on the same button, acts. */
function reset() {
  if (confirming.value !== 'reset') return void (confirming.value = 'reset')
  run(() => store.resetCardToNew(id.value), '這張卡片已重設為新卡，會依每天的新卡額度再出現。')
}

function remove() {
  if (confirming.value !== 'delete') return void (confirming.value = 'delete')
  run(() => store.deleteCardForGood(id.value), '', true)
}
</script>

<template>
  <main class="mx-auto max-w-2xl px-4 py-8">
    <RouterLink :to="{ name: 'deck' }" class="-mx-2 inline-block px-2 py-2 text-sm text-neutral-400 hover:text-neutral-200">← 字卡庫</RouterLink>

    <p v-if="loading && !loaded" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <ErrorState v-else-if="loaded && !card" kind="notFound" not-found-title="找不到這張卡片">
      <template #actions>
        <RouterLink :to="{ name: 'deck' }" class="rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700">
          回到字卡庫
        </RouterLink>
      </template>
    </ErrorState>

    <template v-else-if="card">
      <section class="mt-4">
        <h1 class="text-xl leading-relaxed break-words whitespace-pre-wrap text-neutral-100 sm:text-2xl" lang="vi">{{ card.sourceText }}</h1>
        <p class="mt-3 text-sm text-neutral-400">{{ summary }}</p>
        <p class="mt-1 text-xs text-neutral-500">原文不能修改。打錯或辨識錯誤的卡片請刪除，再重新收集。</p>
      </section>

      <p v-if="done" class="mt-6 text-sm text-emerald-400" role="status">{{ done }}</p>
      <p v-if="failure" class="mt-6 text-sm text-amber-400" role="alert">{{ failed[failure] }}</p>

      <section class="mt-8 space-y-8">
        <div>
          <label for="card-translation" class="block text-sm font-medium text-neutral-100">譯文</label>
          <div class="mt-2 flex gap-2">
            <input
              id="card-translation"
              v-model="translation"
              type="text"
              autocomplete="off"
              :disabled="working"
              class="min-w-0 flex-1 rounded-md border border-neutral-700 bg-neutral-900 px-3 py-2 text-neutral-100 outline-none focus:border-sky-500"
              @keydown="onTranslationKeydown"
            />
            <button
              type="button"
              :disabled="working || unchanged"
              class="shrink-0 rounded-md bg-sky-600 px-4 py-2 text-sm font-medium text-white hover:bg-sky-500 disabled:opacity-40"
              @click="saveTranslation"
            >
              儲存
            </button>
          </div>
        </div>

        <div>
          <p class="text-sm font-medium text-neutral-100">類型</p>
          <p class="mt-1 text-xs text-neutral-500">句子才會被拿來出填空題；單字會被拿來當填空的答案。</p>
          <div class="mt-2 flex gap-2" role="group" aria-label="類型">
            <button
              v-for="option in [
                { kind: 'word', label: '單字' },
                { kind: 'sentence', label: '句子' },
              ] as const"
              :key="option.kind"
              type="button"
              :disabled="working"
              :aria-pressed="card.kind === option.kind"
              class="rounded-md px-4 py-2 text-sm disabled:opacity-40"
              :class="card.kind === option.kind ? 'bg-sky-600 text-white' : 'bg-neutral-800 text-neutral-100 hover:bg-neutral-700'"
              @click="setKind(option.kind)"
            >
              {{ option.label }}
            </button>
          </div>
        </div>

        <div class="border-t border-neutral-800 pt-6">
          <p class="text-sm font-medium text-neutral-100">無法復原的動作</p>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              :disabled="working || card.state === 'new'"
              class="rounded-md px-4 py-2 text-sm disabled:opacity-40"
              :class="confirming === 'reset' ? 'bg-amber-600 text-white hover:bg-amber-500' : 'bg-neutral-800 text-neutral-100 hover:bg-neutral-700'"
              @click="reset"
            >
              {{ confirming === 'reset' ? '確定重設？學習紀錄會歸零' : '重設為新卡' }}
            </button>
            <button
              type="button"
              :disabled="working"
              class="rounded-md px-4 py-2 text-sm disabled:opacity-40"
              :class="confirming === 'delete' ? 'bg-rose-600 text-white hover:bg-rose-500' : 'bg-neutral-800 text-rose-300 hover:bg-neutral-700'"
              @click="remove"
            >
              {{ confirming === 'delete' ? '確定刪除？無法復原' : '刪除卡片' }}
            </button>
            <button
              v-if="confirming"
              type="button"
              class="px-2 py-2 text-sm text-neutral-400 hover:text-neutral-200"
              @click="confirming = null"
            >
              取消
            </button>
          </div>
        </div>
      </section>
    </template>
  </main>
</template>
