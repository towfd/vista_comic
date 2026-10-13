<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { ApiError, type ApiErrorKind } from '../api/client'
import { useDeckStore } from '../stores/deck'
import { formatLearningSteps, parseLearningSteps, parseNewCardsPerDay } from '../practice/settings'
import ErrorState from '../components/ErrorState.vue'

const store = useDeckStore()
const { settings, loading, error } = storeToRefs(store)

// The fields hold text, not numbers: what was typed stays on screen exactly
// as typed while it is wrong, instead of being coerced into something else.
const steps = ref('')
const allowance = ref('')
const stepsProblem = ref<string | null>(null)
const allowanceProblem = ref<string | null>(null)
const saving = ref(false)
const saveError = ref<ApiErrorKind | null>(null)
const saved = ref(false)

function fill() {
  if (!settings.value) return
  steps.value = formatLearningSteps(settings.value.learningSteps)
  allowance.value = String(settings.value.newCardsPerDay)
}

// Always fetched fresh on arrival: the phone may have changed them, and this
// page would otherwise save an old value back over a new one.
const fetched = ref(false)
onMounted(async () => {
  await store.load()
  fetched.value = true
  fill()
})

watch([steps, allowance], () => {
  saved.value = false
})

async function save() {
  const learningSteps = parseLearningSteps(steps.value)
  const newCardsPerDay = parseNewCardsPerDay(allowance.value)
  stepsProblem.value = learningSteps ? null : '請輸入至少一個大於 0 的整數分鐘數，用逗號或空格分開，例如 5, 7, 10。'
  allowanceProblem.value = newCardsPerDay === null ? '請輸入 0 或以上的整數。' : null
  saveError.value = null
  saved.value = false
  if (!learningSteps || newCardsPerDay === null) return

  saving.value = true
  try {
    await store.saveSettings({ learningSteps, newCardsPerDay })
    fill()
    saved.value = true
  } catch (e) {
    saveError.value = e instanceof ApiError ? e.kind : 'unexpected'
  } finally {
    saving.value = false
  }
}

const saveErrorText: Record<ApiErrorKind, string> = {
  unavailable: '連不上伺服器，設定沒有存進去。',
  auth: '登入已經過期，設定沒有存進去。請重新整理頁面。',
  notFound: '伺服器沒有這個設定，沒有存進去。',
  unexpected: '伺服器拒絕了這組設定，沒有存進去。',
}
</script>

<template>
  <main class="mx-auto max-w-xl px-4 py-8">
    <RouterLink :to="{ name: 'practice' }" class="-mx-2 inline-block px-2 py-2 text-sm text-neutral-400 hover:text-neutral-200">← 總覽</RouterLink>
    <h1 class="mt-2 mb-8 text-2xl font-semibold text-neutral-100">設定</h1>

    <p v-if="!fetched || (loading && !settings)" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="error || !settings" :kind="error ?? 'unexpected'" @retry="store.load().then(fill)" />

    <form v-else class="space-y-8" novalidate @submit.prevent="save">
      <div>
        <label for="learning-steps" class="block font-medium text-neutral-100">學習步驟（分鐘）</label>
        <p class="mt-1 text-sm text-neutral-400">
          新卡片和答錯的卡片，要依序隔這些分鐘各答對一次，才會進入以天計算的複習。
        </p>
        <input
          id="learning-steps"
          v-model="steps"
          type="text"
          inputmode="numeric"
          autocomplete="off"
          :aria-invalid="stepsProblem ? 'true' : undefined"
          aria-describedby="learning-steps-problem"
          class="mt-3 w-full rounded-md border border-neutral-700 bg-neutral-900 px-4 py-2.5 text-neutral-100 outline-none focus:border-sky-500 aria-[invalid=true]:border-rose-500"
        />
        <p v-if="stepsProblem" id="learning-steps-problem" class="mt-2 text-sm text-rose-400">{{ stepsProblem }}</p>
      </div>

      <div>
        <label for="new-cards" class="block font-medium text-neutral-100">每天的新卡片數</label>
        <p class="mt-1 text-sm text-neutral-400">一天最多第一次遇到幾張卡片。手機和網頁共用這個額度，設成 0 就不出新卡。</p>
        <input
          id="new-cards"
          v-model="allowance"
          type="text"
          inputmode="numeric"
          autocomplete="off"
          :aria-invalid="allowanceProblem ? 'true' : undefined"
          aria-describedby="new-cards-problem"
          class="mt-3 w-32 rounded-md border border-neutral-700 bg-neutral-900 px-4 py-2.5 text-neutral-100 outline-none focus:border-sky-500 aria-[invalid=true]:border-rose-500"
        />
        <p v-if="allowanceProblem" id="new-cards-problem" class="mt-2 text-sm text-rose-400">{{ allowanceProblem }}</p>
      </div>

      <div class="flex items-center gap-4">
        <button
          type="submit"
          :disabled="saving"
          class="rounded-md bg-sky-600 px-5 py-2.5 font-medium text-white hover:bg-sky-500 disabled:opacity-50"
        >
          {{ saving ? '儲存中…' : '儲存' }}
        </button>
        <p v-if="saved" class="text-sm text-emerald-400" role="status">已儲存</p>
        <p v-else-if="saveError" class="text-sm text-amber-400" role="alert">{{ saveErrorText[saveError] }}</p>
      </div>
    </form>
  </main>
</template>
