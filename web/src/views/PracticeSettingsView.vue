<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { ApiError, type ApiErrorKind } from '../api/client'
import { useDeckStore } from '../stores/deck'
import { rememberQuestionMix, rememberedQuestionMix, type QuestionMix } from '../practice/questionMix'
import { formatLearningSteps, parseLearningSteps, parseNewCardsPerDay } from '../practice/settings'
import AppIcon from '../components/AppIcon.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { iconButton, primaryLg } from '../components/buttons'

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
  // The button keeps its colour while saving (DESIGN 7.1), so a second press
  // is turned away here rather than by disabling it.
  if (saving.value) return
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

// DESIGN 7.8: the field, its focus, and its error.
const fieldClass =
  'mt-3 block rounded-card bg-paper px-4 py-3 text-body text-ink inset-ring-2 inset-ring-line-strong focus:inset-ring-3 focus:inset-ring-brand focus-visible:outline-none aria-[invalid=true]:inset-ring-3 aria-[invalid=true]:inset-ring-danger'
</script>

<template>
  <main class="mx-auto max-w-narrow px-4 pt-6 pb-10">
    <header class="mb-5 flex items-center gap-3">
      <RouterLink :to="{ name: 'practice' }" :class="iconButton" aria-label="回到總覽">
        <AppIcon name="back" />
      </RouterLink>
      <h1 class="text-page text-ink">設定</h1>
    </header>

    <section class="rounded-panel bg-blush px-4.5 pt-4 pb-1.5" aria-labelledby="mix-heading">
      <h2 id="mix-heading" class="text-heading text-ink">玩法</h2>
      <p class="mt-1 text-caption text-ink-soft">
        至少要開一個。不能填空的卡片（例如單字）一律考整句，只開填空時也一樣。這個選擇只記在這個瀏覽器，按下就生效。
      </p>
      <div class="mt-2 divide-y divide-line">
        <!-- The whole row is the switch. The one still on cannot be turned off:
             its track stays pink, a lighter pink, so it still reads as on. -->
        <button
          v-for="item in mixSwitches"
          :key="item.label"
          type="button"
          role="switch"
          :aria-checked="item.on"
          :disabled="item.on && mix !== 'both'"
          class="flex min-h-13 w-full items-center justify-between gap-3 py-2.5 text-left text-body text-ink disabled:cursor-not-allowed disabled:text-ink-faint"
          @click="toggleMix(item.only, item.other)"
        >
          {{ item.label }}
          <span
            class="relative h-7 w-11 shrink-0 rounded-full transition-colors duration-120"
            :class="!item.on ? 'bg-line-strong' : item.on && mix !== 'both' ? 'bg-brand-vivid' : 'bg-brand'"
            aria-hidden="true"
          >
            <span
              class="absolute top-0.75 left-0.75 size-5.5 rounded-full bg-white transition-[translate] duration-120 ease-standard"
              :class="item.on && 'translate-x-4'"
            />
          </span>
        </button>
      </div>
    </section>

    <LoadingState v-if="!fetched || (loading && !settings)" />

    <ErrorState v-else-if="error || !settings" :kind="error ?? 'unexpected'" @retry="store.load().then(fill)" />

    <form v-else class="mt-7 space-y-7" novalidate @submit.prevent="save">
      <div>
        <label for="learning-steps" class="block text-label text-ink">學習步驟（分鐘）</label>
        <p class="mt-1 text-caption text-ink-soft">
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
          :class="[fieldClass, 'w-full']"
        />
        <p v-if="stepsProblem" id="learning-steps-problem" class="mt-2 text-meta text-danger">{{ stepsProblem }}</p>
      </div>

      <div>
        <label for="new-cards" class="block text-label text-ink">每天的新卡片數</label>
        <p class="mt-1 text-caption text-ink-soft">一天最多第一次遇到幾張卡片。手機和網頁共用這個額度，設成 0 就不出新卡。</p>
        <input
          id="new-cards"
          v-model="allowance"
          type="text"
          inputmode="numeric"
          autocomplete="off"
          :aria-invalid="allowanceProblem ? 'true' : undefined"
          aria-describedby="new-cards-problem"
          :class="[fieldClass, 'w-30']"
        />
        <p v-if="allowanceProblem" id="new-cards-problem" class="mt-2 text-meta text-danger">{{ allowanceProblem }}</p>
      </div>

      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <button type="submit" :aria-busy="saving" :class="[primaryLg, 'sm:w-auto sm:min-w-40']">
          {{ saving ? '儲存中…' : '儲存' }}
        </button>
        <p
          v-if="saved"
          class="inline-flex h-9 items-center gap-1.5 self-start rounded-full bg-success-tint px-3.5 text-meta text-success sm:self-auto"
          role="status"
        >
          <AppIcon name="check" class="size-4" />
          已儲存
        </p>
        <p v-else-if="saveError" class="rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger" role="alert">
          {{ saveErrorText[saveError] }}
        </p>
      </div>
    </form>
  </main>
</template>
