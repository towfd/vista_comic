import { defineStore } from 'pinia'
import { ref } from 'vue'
import {
  ApiError,
  fetchLineAnalysis,
  requestLineAnalysis,
  type AnalysisModel,
  type AnalysisWord,
  type ApiErrorKind,
  type LineAnalysis,
} from '../api/client'

export const ANALYSIS_MODELS: readonly { id: AnalysisModel; label: string }[] = [
  { id: 'sonnet', label: 'Sonnet 5.5' },
  { id: 'opus', label: 'Opus 5.5' },
  { id: 'fable', label: 'Fable 5.1' },
]

/** How often a pending analysis is asked after. */
export const POLL_MS = 2_000

const MODEL_KEY = 'vista.analysisModel'

/** The last model chosen in this browser, or Sonnet. Storage may be missing or refuse. */
function rememberedModel(): AnalysisModel {
  try {
    const stored = localStorage.getItem(MODEL_KEY)
    if (ANALYSIS_MODELS.some((m) => m.id === stored)) return stored as AnalysisModel
  } catch {
    // Private mode, blocked storage: the default will do.
  }
  return 'sonnet'
}

function remember(model: AnalysisModel) {
  try {
    localStorage.setItem(MODEL_KEY, model)
  } catch {
    // Not remembered, still used.
  }
}

/** The bubble being studied: its line, its reviewed translation, its page, and the names in it. */
export interface AnalysedBubble {
  sourceText: string
  translation: string
  page: number
  names: { source: string; target: string }[]
}

/** Why there is no analysis to show: the request itself failed, or the day's calls are spent. */
export type RequestProblem = ApiErrorKind | 'capped'

/**
 * What 收卡 is filled with for one word: its meaning, with the Sino-Vietnamese
 * characters in brackets when it has them -- `住院費（院費）`.
 */
export function wordTranslation(word: AnalysisWord): string {
  return word.hanViet ? `${word.meaning}（${word.hanViet}）` : word.meaning
}

/**
 * The line-analysis panel: which bubble it is for, the chosen model, the
 * analysis being shown, and the polling that brings a pending one in. The
 * panel renders this; the reader opens it. See .scratch/web-line-analysis/spec.md.
 */
export const useAnalysisStore = defineStore('analysis', () => {
  const open = ref(false)
  const bubble = ref<AnalysedBubble | null>(null)
  const model = ref<AnalysisModel>(rememberedModel())
  const analysis = ref<LineAnalysis | null>(null)
  const requesting = ref(false)
  const problem = ref<RequestProblem | null>(null)

  let timer: ReturnType<typeof setTimeout> | undefined
  // Moves on every new request and on close. An answer that set out under an
  // older one belongs to a panel that has since changed, and is dropped.
  let epoch = 0

  function stopPolling() {
    clearTimeout(timer)
    timer = undefined
  }

  function poll(id: number, mine: number) {
    timer = setTimeout(async () => {
      let next: LineAnalysis
      try {
        next = await fetchLineAnalysis(id)
      } catch (e) {
        if (mine !== epoch) return
        if (e instanceof ApiError && e.kind === 'notFound') {
          problem.value = 'notFound'
          analysis.value = null
          return
        }
        // A blip in the connection is not the analysis failing: ask again.
        console.warn('polling a line analysis failed:', e)
        poll(id, mine)
        return
      }
      if (mine !== epoch) return
      analysis.value = next
      if (next.status === 'pending') poll(id, mine)
    }, POLL_MS)
  }

  async function run(refresh: boolean) {
    const target = bubble.value
    if (!target) return
    stopPolling()
    const mine = ++epoch
    analysis.value = null
    problem.value = null
    requesting.value = true
    try {
      const requested = await requestLineAnalysis({
        sourceText: target.sourceText,
        translation: target.translation,
        model: model.value,
        names: target.names,
        ...(refresh ? { refresh: true } : {}),
      })
      if (mine !== epoch) return
      if (requested.capped) {
        problem.value = 'capped'
        return
      }
      analysis.value = requested.analysis
      if (requested.analysis.status === 'pending') poll(requested.analysis.id, mine)
    } catch (e) {
      console.warn('asking for a line analysis failed:', e)
      if (mine === epoch) problem.value = e instanceof ApiError ? e.kind : 'unexpected'
    } finally {
      if (mine === epoch) requesting.value = false
    }
  }

  /** Study this bubble: open the panel and show its stored analysis, or ask for one. */
  function openFor(target: AnalysedBubble) {
    bubble.value = target
    open.value = true
    void run(false)
  }

  /** Switch model: that model's stored analysis of the line, or a new one. Remembered for next time. */
  function setModel(next: AnalysisModel) {
    if (next === model.value) return
    model.value = next
    remember(next)
    if (open.value) void run(false)
  }

  /** Run the failed analysis again; the backend re-queues a failed one. */
  function retry() {
    void run(false)
  }

  /** Replace the shown result with a new call. The panel asks the reader first: it costs one. */
  function refresh() {
    void run(true)
  }

  /** Close the panel. A pending analysis carries on server-side; reopening the bubble finds it. */
  function close() {
    stopPolling()
    epoch++
    open.value = false
    bubble.value = null
    analysis.value = null
    problem.value = null
    requesting.value = false
  }

  return { open, bubble, model, analysis, requesting, problem, openFor, setModel, retry, refresh, close }
})
