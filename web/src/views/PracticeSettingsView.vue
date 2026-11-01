<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { ApiError, type ApiErrorKind } from '../api/client'
import { useDeckStore } from '../stores/deck'
import { rememberQuestionMix, rememberedQuestionMix, type QuestionMix } from '../practice/questionMix'
import { formatLearningSteps, parseLearningSteps, parseNewCardsPerDay } from '../practice/settings'
import ErrorState from '../components/ErrorState.vue'

const store = useDeckStore()
const { settings, loading, error } = storeToRefs(store)

// Held in this browser rather than saved with the form below, so it takes
// effect on the tap and needs no server.
const mix = ref(rememberedQuestionMix())
const mixSwitches = computed(() => [
  { label: '填空', on: mix.value !== 'sentence', only: 'cloze', other: 'sentence' },
  { label: '整句', on: mix.value !== 'cloze', only: 'sentence', other: 'cloze' },
] as const)

function toggleMix(only: QuestionMix, other: QuestionMix) {
  // Turning off the one still on is refused by the disabled switch.
  mix.value = mix.value === 'both' ? other : mix.value === other ? 'both' : only
  rememberQuestionMix(mix.value)
}

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

    <section class="mb-8">
      <h2 class="font-medium text-neutral-100">玩法</h2>
      <p class="mt-1 text-sm text-neutral-400">
        至少要開一個。不能填空的卡片（例如單字）一律考整句，只開填空時也一樣。這個選擇只記在這個瀏覽器，按下就生效。
      </p>
      <div class="mt-3 flex flex-wrap gap-3">
        <button
          v-for="item in mixSwitches"
          :key="item.label"
          type="button"
          role="switch"
          :aria-checked="item.on"
          :disabled="item.on && mix !== 'both'"
          class="flex items-center gap-3 rounded-md bg-neutral-900 px-4 py-2.5 text-neutral-100 hover:bg-neutral-800 disabled:opacity-50 disabled:hover:bg-neutral-900"
          @click="toggleMix(item.only, item.other)"
        >
          {{ item.label }}
          <span class="relative h-4 w-7 rounded-full transition-colors" :class="item.on ? 'bg-sky-600' : 'bg-neutral-600'">
            <span
              class="absolute top-0.5 left-0.5 h-3 w-3 rounded-full bg-white transition-transform"
              :class="item.on ? 'translate-x-3' : ''"
            />
          </span>
        </button>
      </div>
    </section>

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
