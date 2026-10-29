<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useSessionStore } from '../stores/session'
import { useDeckStore } from '../stores/deck'
import { scheduleState } from '../practice/library'
import ErrorState from '../components/ErrorState.vue'

const router = useRouter()
const session = useSessionStore()
const { phase, loadError, question, verdict, saveState, saveFailure, remaining, waitingToAdvance, outcome } = storeToRefs(session)

const field = ref<HTMLInputElement | null>(null)
const nextButton = ref<HTMLButtonElement | null>(null)
const doneLink = ref<{ $el: HTMLElement } | null>(null)

const { settings } = storeToRefs(useDeckStore())

// Where the card stood when it was asked, in the card library's own words.
// It stays put through feedback: the answer moves the card, not the question.
const standing = computed(() =>
  question.value && settings.value ? scheduleState(question.value.card, settings.value.learningSteps) : null,
)

const answered = () => outcome.value.correct + outcome.value.wrong

// The button a touch keyboard needs: its Enter can arrive as a composing key
// and never reach `onFieldKeydown` as one.
const submit = () => session.submit(field.value?.value ?? '')

const reload = () => window.location.reload()

onMounted(() => session.start())

// The keyboard never has to hunt for where it is: the field while a question
// is open, the way onward once it is answered.
watch(
  [phase, question],
  async () => {
    await nextTick()
    if (phase.value === 'asking') {
      if (field.value) field.value.value = ''
      field.value?.focus()
    } else if (phase.value === 'feedback') {
      nextButton.value?.focus()
    } else if (phase.value === 'finished') {
      // A session that asked nothing has nothing to report; the overview
      // already says why -- an empty deck, or a day that is done.
      if (answered() === 0) router.replace({ name: 'practice' })
      else doneLink.value?.$el.focus()
    }
  },
  { flush: 'post' },
)

/**
 * Enter submits -- unless an input method is still composing a syllable, when
 * Enter belongs to it. That keydown arrives with `isComposing` set (Chrome) or
 * with keyCode 229 (Safari, which ends the composition first); either way the
 * reader presses Enter again to submit, as with any input method.
 */
function onFieldKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter') return
  if (event.isComposing || event.keyCode === 229) return
  event.preventDefault()
  if (!event.repeat) submit()
}

/** 算我對 removes itself, so the keyboard goes back to the way onward. */
function countAsCorrect() {
  session.countAsCorrect()
  nextButton.value?.focus()
}

/**
 * Enter moves on. Handled here rather than left to the button's own click so
 * a held key cannot answer one question and skip its feedback in one press.
 */
function onNextKeydown(event: KeyboardEvent) {
  if (event.key !== 'Enter') return
  event.preventDefault()
  if (!event.repeat) session.advance()
}
</script>

<template>
  <main class="mx-auto max-w-2xl px-4 py-5 sm:py-8">
    <p v-if="phase === 'loading'" class="py-24 text-center text-neutral-400">載入中…</p>

    <ErrorState v-else-if="phase === 'unavailable' && loadError" :kind="loadError" @retry="session.start()" />

    <p v-else-if="phase === 'checking'" class="py-24 text-center text-neutral-400">確認還有沒有卡片…</p>

    <section v-else-if="phase === 'finished' && answered() > 0" class="py-16 text-center">
      <h1 class="text-2xl font-semibold text-neutral-100">這一輪做完了</h1>
      <dl class="mx-auto mt-8 grid max-w-md grid-cols-3 gap-3">
        <div class="rounded-md bg-neutral-900 px-2 py-5">
          <dd class="text-3xl font-semibold text-emerald-400">{{ outcome.correct }}</dd>
          <dt class="mt-1 text-sm text-neutral-400">答對</dt>
        </div>
        <div class="rounded-md bg-neutral-900 px-2 py-5">
          <dd class="text-3xl font-semibold text-rose-400">{{ outcome.wrong }}</dd>
          <dt class="mt-1 text-sm text-neutral-400">答錯</dt>
        </div>
        <div class="rounded-md bg-neutral-900 px-2 py-5">
          <dd class="text-3xl font-semibold text-neutral-100">{{ outcome.graduated }}</dd>
          <dt class="mt-1 text-sm text-neutral-400">畢業</dt>
        </div>
      </dl>
      <p class="mt-4 text-xs text-neutral-500">畢業：這一輪最後一次作答後，進入以天計算的複習階段的卡片。</p>
      <RouterLink
        ref="doneLink"
        :to="{ name: 'practice' }"
        class="mt-8 inline-block rounded-md bg-sky-600 px-5 py-2.5 font-medium text-white hover:bg-sky-500"
      >
        回到總覽
      </RouterLink>
    </section>

    <template v-else-if="question">
      <div class="mb-5 flex items-center justify-between gap-3 text-sm text-neutral-400 sm:mb-8">
        <p>
          還剩 {{ remaining }} 張<template v-if="standing"> · <span class="text-neutral-200">{{ standing }}</span></template>
        </p>
        <!-- Answers already saved stay saved; only the one on screen is given up. -->
        <RouterLink :to="{ name: 'practice' }" class="-m-2 shrink-0 p-2 hover:text-neutral-200">結束</RouterLink>
      </div>

      <template v-if="question.cloze">
        <p class="text-sm text-neutral-400">填入空格裡的字</p>
        <!-- pre-wrap: the sentence is shown exactly as collected, line breaks and all. -->
        <p class="mt-2 text-2xl leading-relaxed whitespace-pre-wrap text-neutral-100" lang="vi">
          {{ question.cloze.before }}<span class="mx-1 inline-block w-20 border-b-2 border-sky-500 align-baseline" aria-label="空格">&nbsp;</span
          >{{ question.cloze.after }}
        </p>
        <p class="mt-3 text-base text-neutral-400">{{ question.prompt }}</p>
      </template>
      <template v-else>
        <p class="text-sm text-neutral-400">把這句話寫成越南文</p>
        <p class="mt-2 text-2xl leading-relaxed text-neutral-100">{{ question.prompt }}</p>
      </template>

      <!-- Kept mounted through feedback, read-only, so what was typed stays where it was typed. -->
      <input
        ref="field"
        type="text"
        lang="vi"
        autocomplete="off"
        autocapitalize="off"
        autocorrect="off"
        spellcheck="false"
        enterkeyhint="send"
        aria-label="你的答案"
        :readonly="phase !== 'asking'"
        class="mt-6 w-full rounded-md border border-neutral-700 bg-neutral-900 px-4 py-3 text-xl text-neutral-100 outline-none focus:border-sky-500 read-only:text-neutral-400"
        @keydown="onFieldKeydown"
      />
      <div v-if="phase === 'asking'" class="mt-3 flex items-center justify-end gap-3">
        <p class="hidden text-xs text-neutral-500 pointer-fine:block">Enter 送出</p>
        <button
          type="button"
          class="w-full rounded-md bg-sky-600 px-5 py-2.5 font-medium text-white hover:bg-sky-500 sm:w-auto"
          @click="submit"
        >
          送出
        </button>
      </div>

      <section v-if="phase === 'feedback' && verdict" class="mt-6 sm:mt-8" aria-live="polite">
        <p class="text-lg font-semibold" :class="verdict.correct ? 'text-emerald-400' : 'text-rose-400'">
          {{ verdict.overridden ? '正確（已改判）' : verdict.correct ? '正確' : '不對' }}
        </p>

        <dl class="mt-4 space-y-3">
          <div v-if="!verdict.correct || verdict.overridden">
            <dt class="text-xs text-neutral-500">你的答案</dt>
            <dd class="mt-1 text-xl text-neutral-300" lang="vi">{{ verdict.given }}</dd>
          </div>
          <div>
            <dt class="text-xs text-neutral-500">{{ verdict.sentence ? '空格裡的字' : '卡片' }}</dt>
            <dd class="mt-1 text-xl text-neutral-100" lang="vi">{{ verdict.expected }}</dd>
          </div>
          <div v-if="verdict.sentence">
            <dt class="text-xs text-neutral-500">整句</dt>
            <dd class="mt-1 text-lg whitespace-pre-wrap text-neutral-300" lang="vi">{{ verdict.sentence }}</dd>
          </div>
        </dl>

        <p v-if="saveState === 'gone'" class="mt-6 text-sm text-neutral-400">這張卡片已經在別的裝置上刪除了。</p>

        <div v-if="saveState === 'failed'" class="mt-6 rounded-md border border-amber-500/40 bg-amber-500/10 px-4 py-3" role="alert">
          <template v-if="saveFailure === 'auth'">
            <p class="text-sm font-medium text-amber-300">登入已經過期，這個答案沒有存進去。</p>
            <p class="mt-1 text-sm text-amber-200/80">重新整理後登入，這一題會再出一次。</p>
            <button class="mt-3 rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700" @click="reload">
              重新整理
            </button>
          </template>
          <template v-else>
            <p class="text-sm font-medium text-amber-300">這個答案還沒有存進去。</p>
            <p class="mt-1 text-sm text-amber-200/80">存好之前不會出下一題。關掉這個分頁會遺失這一個答案。</p>
            <button
              class="mt-3 rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700"
              @click="session.retrySave()"
            >
              重試
            </button>
          </template>
        </div>

        <div class="mt-8 flex items-center justify-end gap-3">
          <!-- Only while a wrong answer is unsent: the judge is strict, and the reader may know better. -->
          <button
            v-if="!verdict.correct && saveState === null && !waitingToAdvance"
            class="w-full rounded-md bg-neutral-800 px-5 py-2.5 font-medium text-emerald-300 hover:bg-neutral-700 sm:w-auto"
            @click="countAsCorrect"
          >
            算我對
          </button>
          <button
            ref="nextButton"
            :disabled="saveState === 'failed'"
            class="w-full rounded-md bg-sky-600 px-5 py-2.5 font-medium text-white hover:bg-sky-500 disabled:opacity-50 sm:w-auto"
            @click="session.advance()"
            @keydown="onNextKeydown"
          >
            {{ waitingToAdvance ? '儲存中…' : '下一題' }}
          </button>
        </div>

        <!-- Fixing a card happens in the library. A new tab, so the session is
             not left: coming back to this one refetches the deck, and the fix
             applies from the next question. -->
        <p v-if="saveState === 'saved'" class="mt-8 border-t border-neutral-800 pt-4 text-sm">
          <RouterLink
            :to="{ name: 'deck-card', params: { cardId: question.card.id } }"
            target="_blank"
            class="text-neutral-400 underline decoration-neutral-600 underline-offset-4 hover:text-neutral-200"
          >
            這張卡片有問題？到字卡庫修改 ↗
          </RouterLink>
        </p>
      </section>
    </template>
  </main>
</template>
