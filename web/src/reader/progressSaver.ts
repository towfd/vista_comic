import { shouldWrite } from './progress'

/**
 * Sends one save. Resolves `true` when it was stored, `false` when it failed;
 * never rejects -- failures are the sender's to log.
 */
export type SaveFn = (page: number, options: { keepalive: boolean }) => Promise<boolean>

export interface ProgressSaver {
  /** The reader's current page changed (from visibility). `null` = nothing seen. */
  update(page: number | null): void
  /** A real user input arrived after the chapter was positioned. */
  openGate(): void
  /**
   * Send the current page now, cancelling any pending debounce -- on leaving
   * the reader and on the tab going hidden (`keepalive`). Does nothing when the
   * gate is closed or the page was already sent.
   */
  flush(options?: { keepalive?: boolean }): void
  /** Cancel any pending debounce without sending. */
  dispose(): void
}

/**
 * The timing half of progress writing, one per opened chapter: gate,
 * ~1 s debounce, immediate flush, and "skip if already sent". Holds no
 * network code; the caller injects `save` (the chapters store's
 * `saveProgress`, which is also where the in-flight promise is tracked).
 */
export function createProgressSaver(save: SaveFn, delayMs = 1000): ProgressSaver {
  let gateOpen = false
  let current: number | null = null
  let lastSent: number | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  function cancel() {
    if (timer !== null) clearTimeout(timer)
    timer = null
  }

  function send(keepalive: boolean) {
    const page = current
    if (page === null || !shouldWrite({ gateOpen, page, lastSent })) return
    lastSent = page
    void save(page, { keepalive }).then((ok) => {
      // A failed save must not count as sent, so the next debounce or flush is
      // the natural retry even if the reader has not moved since.
      if (!ok && lastSent === page) lastSent = null
    })
  }

  function schedule() {
    cancel()
    if (!shouldWrite({ gateOpen, page: current, lastSent })) return
    // Reads `current` when it fires, so a burst of changes sends the latest.
    timer = setTimeout(() => {
      timer = null
      send(false)
    }, delayMs)
  }

  return {
    update(page) {
      current = page
      if (gateOpen) schedule()
    },
    openGate() {
      if (gateOpen) return
      gateOpen = true
      schedule()
    },
    flush(options = {}) {
      cancel()
      send(options.keepalive ?? false)
    },
    dispose() {
      cancel()
    },
  }
}
