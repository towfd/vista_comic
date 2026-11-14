<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import { useSessionStore } from '../stores/session'
import { useDeckStore } from '../stores/deck'
import { scheduleState } from '../practice/library'
import type { CardState } from '../api/types'
import AppIcon from '../components/AppIcon.vue'
import ErrorState from '../components/ErrorState.vue'
import LoadingState from '../components/LoadingState.vue'
import { iconButtonBlush, primaryLg, secondaryLg, secondaryMd } from '../components/buttons'

const router = useRouter()
const session = useSessionStore()
const { phase, loadError, question, verdict, saveState, saveFailure, remaining, waitingToAdvance, outcome } = storeToRefs(session)

const field = ref<HTMLTextAreaElement | null>(null)
const nextButton = ref<HTMLButtonElement | null>(null)
const doneLink = ref<{ $el: HTMLElement } | null>(null)

const { settings } = storeToRefs(useDeckStore())

// Where the card stood when it was asked, in the card library's own words.
// It stays put through feedback: the answer moves the card, not the question.
const standing = computed(() =>
  question.value && settings.value ? scheduleState(question.value.card, settings.value.learningSteps) : null,
)

const answered = () => outcome.value.correct + outcome.value.wrong

// How far through the round, as far as is known: a card answered wrong comes
// back to the queue, so the bar can step back a little. That is the truth.
const progress = computed(() => {
  const done = answered()
  const total = done + remaining.value
  return { done, total, percent: total === 0 ? 0 : (done / total) * 100 }
})

const chipTone: Record<CardState, string> = {
  new: 'bg-st-new-tint text-st-new',
  learning: 'bg-st-learn-tint text-st-learn',
  relearning: 'bg-st-relearn-tint text-st-relearn',
  review: 'bg-st-review-tint text-st-review',
}

/** The answer field: pink while asking; read-only on the verdict's colour after. */
const fieldTone = computed(() => {
  if (phase.value === 'asking' || !verdict.value) return 'bg-paper text-ink inset-ring-3 inset-ring-brand'
  return verdict.value.correct
    ? 'bg-blush text-ink-soft inset-ring-3 inset-ring-st-review-graphic'
    : 'bg-blush text-ink-soft inset-ring-3 inset-ring-st-relearn-graphic'
})

// The button a touch keyboard needs: its Enter can arrive as a composing key
// and never reach `onFieldKeydown` as one.
const submit = () => session.submit(field.value?.value ?? '')

const reload = () => window.location.reload()

/** As tall as what is typed, so nothing is ever cut off. `auto` first, or it could only grow. */
function fitField() {
  const el = field.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${el.scrollHeight + el.offsetHeight - el.clientHeight}px`
}

onMounted(() => {
  session.start()
  // A narrower window wraps the same text onto more lines.
  window.addEventListener('resize', fitField)
})
onUnmounted(() => window.removeEventListener('resize', fitField))

// The keyboard never has to hunt for where it is: the field while a question
// is open, the way onward once it is answered.
watch(
  [phase, question],
  async () => {
    await nextTick()
    if (phase.value === 'asking') {
      if (field.value) field.value.value = ''
      fitField()
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

/** An answer is one line that wraps: an Enter `onFieldKeydown` left alone must not start a second. */
function refuseLineBreak(event: Event) {
  const { inputType } = event as InputEvent
  if (inputType === 'insertLineBreak' || inputType === 'insertParagraph') event.preventDefault()
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
  <main class="mx-auto max-w-page px-4 pt-3 pb-10 sm:pt-6">
    <LoadingState v-if="phase === 'loading'" />

    <ErrorState v-else-if="phase === 'unavailable' && loadError" :kind="loadError" @retry="session.start()" />

    <LoadingState v-else-if="phase === 'checking'" text="確認還有沒有卡片…" />

    <section v-else-if="phase === 'finished' && answered() > 0" class="pt-8 text-center">
      <div
        class="mx-auto grid size-21 -rotate-8 place-items-center rounded-full bg-sun text-ink ring-5 ring-paper outline-2 outline-offset-5 outline-blush-strong"
      >
        <AppIcon name="check" class="size-11 stroke-3" />
      </div>
      <h1 class="mt-4 text-headline text-ink">這一輪做完了</h1>
      <div class="mt-4.5 rounded-panel bg-blush px-4.5 py-4 text-left">
        <dl class="flex flex-wrap gap-2">
          <div class="inline-flex h-9 items-center gap-1.5 rounded-full bg-st-review-tint px-3.5 text-meta text-st-review">
            <dt>答對</dt>
            <dd class="text-label font-black tabular-nums">{{ outcome.correct }}</dd>
          </div>
          <div class="inline-flex h-9 items-center gap-1.5 rounded-full bg-st-relearn-tint px-3.5 text-meta text-st-relearn">
            <dt>答錯</dt>
            <dd class="text-label font-black tabular-nums">{{ outcome.wrong }}</dd>
          </div>
          <div class="inline-flex h-9 items-center gap-1.5 rounded-full bg-blush-strong px-3.5 text-meta text-brand">
            <dt>畢業</dt>
            <dd class="text-label font-black tabular-nums">{{ outcome.graduated }}</dd>
          </div>
        </dl>
        <p class="mt-3 text-caption text-ink-soft">畢業：這一輪最後一次作答後，進入以天計算的複習階段的卡片。</p>
      </div>
      <RouterLink ref="doneLink" :to="{ name: 'practice' }" :class="[primaryLg, 'mt-6']">回到總覽</RouterLink>
    </section>

    <template v-else-if="question">
      <div class="flex items-center gap-3">
        <!-- Answers already saved stay saved; only the one on screen is given up. -->
        <RouterLink :to="{ name: 'practice' }" :class="iconButtonBlush" aria-label="結束">
          <AppIcon name="close" />
        </RouterLink>
        <div
          class="h-3 flex-1 overflow-hidden rounded-full bg-paper inset-ring-2 inset-ring-line"
          role="progressbar"
          aria-label="這一輪的進度"
          :aria-valuenow="progress.done"
          aria-valuemin="0"
          :aria-valuemax="progress.total"
        >
          <div
            class="h-full rounded-full bg-brand-vivid transition-[width] duration-200 ease-standard"
            :style="{ width: `${progress.percent}%` }"
          />
        </div>
        <p class="shrink-0 text-meta font-extrabold text-ink-soft tabular-nums">還剩 {{ remaining }} 張</p>
      </div>

      <section class="mt-7 rounded-panel bg-blush px-5 pt-5.5 pb-5">
        <div class="flex items-center justify-between gap-3">
          <p class="text-meta text-ink-soft">{{ question.cloze ? '填入空格裡的字' : '把這句話寫成越南文' }}</p>
          <span
            v-if="standing"
            class="inline-flex h-6.5 shrink-0 items-center rounded-full px-2.5 text-caption"
            :class="chipTone[question.card.state]"
          >
            {{ standing }}
          </span>
        </div>

        <template v-if="question.cloze">
          <!-- pre-wrap: the sentence is shown exactly as collected, line breaks and all.
               The blank has one width for every word, so it gives no length away. -->
          <p class="mt-2.5 text-headline leading-relaxed font-extrabold break-words whitespace-pre-wrap text-ink" lang="vi">
            {{ question.cloze.before }}<span
              class="inline-block h-[1.2em] w-30 max-w-[40%] rounded-full bg-paper align-[-0.22em] inset-ring-2 inset-ring-brand-vivid"
              aria-label="空格"
            ></span
            >{{ question.cloze.after }}
          </p>
          <div class="mt-4 rounded-tile bg-paper px-3.5 py-2.5">
            <p class="text-caption text-ink-faint">中文提示</p>
            <p class="text-label leading-relaxed text-ink">{{ question.prompt }}</p>
          </div>
        </template>
        <p v-else class="mt-2.5 text-headline leading-relaxed break-words text-ink">{{ question.prompt }}</p>
      </section>

      <!-- Kept mounted through feedback, read-only, so what was typed stays where it was typed.
           A textarea so a long sentence wraps into view instead of scrolling out of it. -->
      <textarea
        ref="field"
        :rows="question.cloze ? 1 : 2"
        lang="vi"
        autocomplete="off"
        autocapitalize="off"
        autocorrect="off"
        spellcheck="false"
        enterkeyhint="send"
        aria-label="你的答案"
        :readonly="phase !== 'asking'"
        class="mt-5.5 block w-full resize-none overflow-hidden rounded-card px-4.5 py-3.5 text-heading font-extrabold focus-visible:outline-none"
        :class="fieldTone"
        @keydown="onFieldKeydown"
        @beforeinput="refuseLineBreak"
        @input="fitField"
      />
      <!-- In the flow under the field, never pinned to the bottom: the phone's
           keyboard would cover a bottom bar. -->
      <div v-if="phase === 'asking'" class="mt-3 flex items-center justify-end gap-3">
        <p class="hidden shrink-0 text-caption text-ink-faint pointer-fine:block">Enter 送出</p>
        <button type="button" :class="[primaryLg, 'sm:w-auto sm:min-w-40']" @click="submit">送出</button>
      </div>

      <section v-if="phase === 'feedback' && verdict" class="mt-5" aria-live="polite">
        <div class="flex items-center gap-3">
          <span
            class="grid size-10 -rotate-6 place-items-center rounded-full"
            :class="verdict.correct ? 'bg-sun text-ink' : 'bg-st-relearn-tint text-st-relearn'"
            aria-hidden="true"
          >
            <AppIcon :name="verdict.correct ? 'check' : 'close'" class="size-6 stroke-3" />
          </span>
          <p class="text-heading" :class="verdict.correct ? 'text-st-review' : 'text-st-relearn'">
            {{ verdict.overridden ? '正確（已改判）' : verdict.correct ? '正確' : '不對' }}
          </p>
        </div>

        <dl class="mt-4 space-y-3">
          <div v-if="!verdict.correct || verdict.overridden">
            <dt class="text-caption text-ink-faint">你的答案</dt>
            <dd class="mt-0.5 text-heading font-bold break-words text-ink-soft" lang="vi">{{ verdict.given }}</dd>
          </div>
          <div>
            <dt class="text-caption text-ink-faint">{{ verdict.sentence ? '空格裡的字' : '卡片' }}</dt>
            <dd class="mt-0.5 text-headline font-extrabold break-words text-ink" lang="vi">{{ verdict.expected }}</dd>
          </div>
          <div v-if="verdict.sentence">
            <dt class="text-caption text-ink-faint">整句</dt>
            <!-- The word that was blanked is underlined where it stands. -->
            <dd class="mt-0.5 text-label font-bold break-words whitespace-pre-wrap text-ink-soft" lang="vi">
              <template v-if="question.cloze"
                >{{ question.cloze.before
                }}<span class="underline decoration-brand-vivid decoration-3 underline-offset-4">{{ question.cloze.removed }}</span
                >{{ question.cloze.after }}</template
              ><template v-else>{{ verdict.sentence }}</template>
            </dd>
          </div>
        </dl>

        <p v-if="saveState === 'gone'" class="mt-5 text-meta text-ink-soft">這張卡片已經在別的裝置上刪除了。</p>

        <div v-if="saveState === 'failed'" class="mt-5 rounded-tile bg-danger-tint px-3.5 py-3 text-danger" role="alert">
          <template v-if="saveFailure === 'auth'">
            <p class="text-body font-bold">登入已經過期，這個答案沒有存進去。</p>
            <p class="mt-1 text-meta">重新整理後登入，這一題會再出一次。</p>
            <button type="button" :class="[secondaryMd, 'mt-3']" @click="reload">重新整理</button>
          </template>
          <template v-else>
            <p class="text-body font-bold">這個答案還沒有存進去。</p>
            <p class="mt-1 text-meta">存好之前不會出下一題。關掉這個分頁會遺失這一個答案。</p>
            <button type="button" :class="[secondaryMd, 'mt-3']" @click="session.retrySave()">重試</button>
          </template>
        </div>

        <div class="mt-6 flex items-center gap-3 sm:justify-end">
          <!-- Only while a wrong answer is unsent: the judge is strict, and the reader may know better. -->
          <button
            v-if="!verdict.correct && saveState === null && !waitingToAdvance"
            type="button"
            :class="[secondaryLg, 'min-w-0 flex-1 text-st-review sm:min-w-40 sm:flex-none']"
            @click="countAsCorrect"
          >
            算我對
          </button>
          <button
            ref="nextButton"
            type="button"
            :disabled="saveState === 'failed'"
            :aria-busy="waitingToAdvance"
            :class="[primaryLg, 'min-w-0 flex-1 sm:w-auto sm:min-w-40 sm:flex-none']"
            @click="session.advance()"
            @keydown="onNextKeydown"
          >
            {{ waitingToAdvance ? '儲存中…' : '下一題' }}
          </button>
        </div>

        <!-- Only after an answer: a note often gives the answer away. -->
        <section v-if="question.card.note" class="mt-6 rounded-card bg-blush px-4 py-3.5" aria-labelledby="card-note-heading">
          <h2 id="card-note-heading" class="text-caption text-ink-faint">註解</h2>
          <p class="mt-1 text-body break-words whitespace-pre-wrap text-ink">{{ question.card.note }}</p>
        </section>

        <!-- Fixing a card happens in the library. A new tab, so the session is
             not left: coming back to this one refetches the deck, and the fix
             applies from the next question. -->
        <p v-if="saveState !== 'gone'" class="mt-8 border-t border-line pt-4 text-meta">
          <RouterLink
            :to="{ name: 'deck-card', params: { cardId: question.card.id } }"
            target="_blank"
            class="text-ink-soft underline decoration-line-strong underline-offset-4 hover:text-ink"
          >
            這張卡片有問題？到字卡庫修改 ↗
          </RouterLink>
        </p>
      </section>
    </template>
  </main>
</template>
