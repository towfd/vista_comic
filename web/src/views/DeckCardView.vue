<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { ApiError, type ApiErrorKind, type CardCorrection } from '../api/client'
import { useDeckStore } from '../stores/deck'
import { NOTE_LIMIT, SOURCE_TEXT_LIMIT } from '../stores/collect'
import type { LearningCard } from '../api/types'
import { scheduleDue, scheduleState } from '../practice/library'
import { isOverdue, stateChipClass } from '../deck/cardState'
import AppIcon from '../components/AppIcon.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import {
  dangerMd,
  iconButton,
  primaryMd,
  secondaryDangerMd,
  secondaryMd,
  textButton,
  warningMd,
} from '../components/buttons'

const props = defineProps<{ cardId: string }>()

const router = useRouter()
const store = useDeckStore()
const { cards, settings, loading, error, loaded, loadedAt } = storeToRefs(store)

const id = computed(() => Number(props.cardId))
const card = computed(() => cards.value.find((held) => held.id === id.value) ?? null)

const sourceText = ref('')
const translation = ref('')
const working = ref(false)
const done = ref<string | null>(null)
const failure = ref<ApiErrorKind | null>(null)
// The card that already holds the source text the reader tried to give this one.
const taken = ref<LearningCard | null>(null)
// Which of the two actions that cannot be taken back is waiting for a second press.
const confirming = ref<'reset' | 'delete' | null>(null)

// Fetched fresh on arrival: this page changes what the phone also holds, and
// should start from what is true now rather than from a copy kept for a count.
onMounted(() => store.load())

watch(
  () => card.value?.sourceText,
  (text) => {
    sourceText.value = text ?? ''
  },
  { immediate: true },
)

// Going to the card that holds the text is the same page with another id:
// what was said about the last card is not about this one.
watch(id, () => {
  done.value = null
  failure.value = null
  taken.value = null
  confirming.value = null
})

watch(
  () => card.value?.translation,
  (text) => {
    translation.value = text ?? ''
  },
  { immediate: true },
)

// The state and the due time are two things on screen (a chip, then the time), not one line.
const now = () => loadedAt.value ?? new Date()
const state = computed(() => (card.value ? scheduleState(card.value, settings.value?.learningSteps ?? []) : ''))
const due = computed(() => (card.value ? scheduleDue(card.value, now()) : null))
const overdue = computed(() => (card.value ? isOverdue(card.value, now()) : false))

/**
 * A field's 儲存 lights up only when there is something to save: three solid
 * pink buttons at once would shout, so the quiet ones wait as secondary.
 */
const saveClass = (blocked: boolean) => `shrink-0 ${blocked ? secondaryMd : primaryMd}`

const inputClass =
  'min-w-0 flex-1 rounded-card bg-paper px-4 py-3 text-body text-ink inset-ring-2 inset-ring-line-strong outline-none placeholder:text-ink-faint focus:inset-ring-3 focus:inset-ring-brand focus-visible:outline-none disabled:bg-mist disabled:text-ink-faint disabled:inset-ring-line'

/** The segmented control's option: selected is solid pink; while working the whole group rests. */
const kindClass = (selected: boolean) =>
  `h-9 rounded-full px-5 text-meta transition-colors duration-120 ${
    working.value
      ? selected
        ? 'bg-blush-strong text-ink-faint'
        : 'text-ink-faint'
      : selected
        ? 'bg-brand text-white'
        : 'text-ink-soft hover:bg-blush-strong active:bg-blush-strong'
  }`

const sourceUnchanged = computed(
  () =>
    sourceText.value.trim() === '' ||
    sourceText.value.trim().length > SOURCE_TEXT_LIMIT ||
    sourceText.value.trim() === card.value?.sourceText,
)

const unchanged = computed(() => translation.value.trim() === '' || translation.value.trim() === card.value?.translation)

// Unlike the translation, an empty note is a value: saving it clears the note.
const note = ref('')
watch(
  () => card.value?.note,
  (text) => {
    note.value = text ?? ''
  },
  { immediate: true },
)
const noteUnchanged = computed(() => note.value.trim() === (card.value?.note ?? ''))

const failed: Record<ApiErrorKind, string> = {
  unavailable: '連不上伺服器，卡片沒有變動。',
  auth: '登入已經過期，卡片沒有變動。請重新整理頁面。',
  notFound: '找不到這張卡片。',
  unexpected: '伺服器拒絕了這個修改，卡片沒有變動。',
}

/**
 * Run one action, say what happened, and leave if the card is no longer there.
 * `'kept'`: the server refused without changing anything, and the action has
 * already said why.
 */
async function run(action: () => Promise<'done' | 'gone' | 'kept'>, message: string, leaves = false) {
  if (working.value) return
  working.value = true
  done.value = null
  failure.value = null
  taken.value = null
  confirming.value = null
  try {
    const result = await action()
    if (leaves || result === 'gone') router.replace({ name: 'deck' })
    else if (result === 'done') done.value = message
  } catch (e) {
    failure.value = e instanceof ApiError ? e.kind : 'unexpected'
  } finally {
    working.value = false
  }
}

const correct = (correction: CardCorrection, message: string) => run(() => store.correctCard(id.value, correction), message)

function saveSourceText() {
  if (sourceUnchanged.value) return
  run(async () => {
    const result = await store.correctSourceText(id.value, sourceText.value.trim())
    if (typeof result === 'string') return result
    taken.value = result.taken
    return 'kept'
  }, '原文已更新。')
}

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

function saveNote() {
  if (noteUnchanged.value) return
  const text = note.value.trim()
  correct({ note: text || null }, text ? '註解已更新。' : '註解已清除。')
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
  <main class="mx-auto max-w-page px-4 pt-2 pb-12 md:px-6">
    <RouterLink :to="{ name: 'deck' }" aria-label="回到字卡庫" :class="iconButton">
      <AppIcon name="back" />
    </RouterLink>

    <LoadingState v-if="loading && !loaded" />

    <ErrorState v-else-if="error" :kind="error" @retry="store.load()" />

    <ErrorState v-else-if="loaded && !card" kind="notFound" not-found-title="找不到這張卡片">
      <template #actions="{ buttonClass }">
        <RouterLink :to="{ name: 'deck' }" :class="buttonClass">回到字卡庫</RouterLink>
      </template>
    </ErrorState>

    <template v-else-if="card">
      <section class="mt-3">
        <h1 class="text-headline font-extrabold leading-title break-words whitespace-pre-wrap text-ink" lang="vi">{{ card.sourceText }}</h1>
        <div class="mt-2.5 flex flex-wrap items-center gap-x-2.5 gap-y-1">
          <span :class="stateChipClass(card.state)">{{ state }}</span>
          <span v-if="due" class="text-caption" :class="overdue ? 'text-st-relearn' : 'text-ink-faint'">{{ due }}</span>
        </div>
      </section>

      <p v-if="done" class="mt-4 rounded-tile bg-success-tint px-3.5 py-3 text-body text-success" role="status">{{ done }}</p>
      <p v-if="failure" class="mt-4 rounded-tile bg-danger-tint px-3.5 py-3 text-body text-danger" role="alert">{{ failed[failure] }}</p>

      <section class="mt-7 space-y-7">
        <div>
          <label for="card-source" class="block text-label text-ink">原文</label>
          <p class="mt-1 text-caption text-ink-soft">修正收卡時打錯的字。學習進度和作答紀錄都會保留。</p>
          <!-- A textarea: a sentence can be collected with its line breaks, and keeps them. -->
          <div class="mt-2 flex items-start gap-2">
            <textarea
              id="card-source"
              v-model="sourceText"
              lang="vi"
              rows="2"
              :maxlength="SOURCE_TEXT_LIMIT"
              autocomplete="off"
              autocapitalize="off"
              autocorrect="off"
              spellcheck="false"
              :disabled="working"
              :class="[inputClass, 'resize-y']"
            />
            <button
              type="button"
              :disabled="working || sourceUnchanged"
              :class="saveClass(working || sourceUnchanged)"
              @click="saveSourceText"
            >
              儲存
            </button>
          </div>

          <!-- Nothing is merged: which card to keep is the reader's to decide, as when collecting a line twice. -->
          <div v-if="taken" class="mt-3 rounded-tile bg-warning-tint px-3.5 py-3 text-body text-warning" role="alert">
            <p>字卡庫已經有這張卡片，原文沒有修改。</p>
            <div class="mt-2 rounded-tile bg-paper p-3">
              <p class="text-body font-bold break-words whitespace-pre-wrap text-ink" lang="vi">{{ taken.sourceText }}</p>
              <p class="mt-0.5 text-meta break-words whitespace-pre-wrap text-ink-soft">{{ taken.translation }}</p>
            </div>
            <RouterLink
              :to="{ name: 'deck-card', params: { cardId: taken.id } }"
              class="mt-1 inline-block py-2 text-meta text-ink-soft underline decoration-line-strong decoration-2 underline-offset-4 hover:decoration-brand"
            >
              到那張卡片 →
            </RouterLink>
          </div>
        </div>

        <div>
          <label for="card-translation" class="block text-label text-ink">譯文</label>
          <div class="mt-2 flex items-start gap-2">
            <input
              id="card-translation"
              v-model="translation"
              type="text"
              autocomplete="off"
              :disabled="working"
              :class="inputClass"
              @keydown="onTranslationKeydown"
            />
            <button
              type="button"
              :disabled="working || unchanged"
              :class="saveClass(working || unchanged)"
              @click="saveTranslation"
            >
              儲存
            </button>
          </div>
        </div>

        <div>
          <label for="card-note" class="block text-label text-ink">註解</label>
          <p class="mt-1 text-caption text-ink-soft">選填。練習答完後會顯示在最下面。清空後儲存就是刪除。</p>
          <!-- Enter is a line break here, not a save: a note is often more than one line. -->
          <div class="mt-2 flex items-start gap-2">
            <textarea
              id="card-note"
              v-model="note"
              rows="3"
              :maxlength="NOTE_LIMIT"
              autocomplete="off"
              :disabled="working"
              :class="[inputClass, 'resize-y']"
            />
            <button
              type="button"
              :disabled="working || noteUnchanged"
              :class="saveClass(working || noteUnchanged)"
              @click="saveNote"
            >
              儲存
            </button>
          </div>
        </div>

        <div>
          <p class="text-label text-ink">類型</p>
          <p class="mt-1 text-caption text-ink-soft">句子才會被拿來出填空題；單字會被拿來當填空的答案。</p>
          <div class="mt-2 inline-flex rounded-full bg-blush p-1" role="group" aria-label="類型">
            <button
              v-for="option in [
                { kind: 'word', label: '單字' },
                { kind: 'sentence', label: '句子' },
              ] as const"
              :key="option.kind"
              type="button"
              :disabled="working"
              :aria-pressed="card.kind === option.kind"
              :class="kindClass(card.kind === option.kind)"
              @click="setKind(option.kind)"
            >
              {{ option.label }}
            </button>
          </div>
        </div>

        <div class="border-t-2 border-dashed border-line pt-6">
          <p class="text-label text-ink">無法復原的動作</p>
          <!-- Stacked on a phone: 確定重設？學習紀錄會歸零 is too long to share a row. -->
          <div class="mt-3 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center">
            <button
              type="button"
              :disabled="working || card.state === 'new'"
              :class="confirming === 'reset' ? warningMd : secondaryMd"
              @click="reset"
            >
              {{ confirming === 'reset' ? '確定重設？學習紀錄會歸零' : '重設為新卡' }}
            </button>
            <button
              type="button"
              :disabled="working"
              :class="confirming === 'delete' ? dangerMd : secondaryDangerMd"
              @click="remove"
            >
              <AppIcon v-if="confirming !== 'delete'" name="trash" class="size-5" />
              {{ confirming === 'delete' ? '確定刪除？無法復原' : '刪除卡片' }}
            </button>
            <button v-if="confirming" type="button" :class="textButton" class="self-center" @click="confirming = null">
              取消
            </button>
          </div>
        </div>
      </section>
    </template>
  </main>
</template>
