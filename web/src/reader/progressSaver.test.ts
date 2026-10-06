import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createProgressSaver, type SaveFn } from './progressSaver'

function recorder(result = true) {
  const calls: { page: number; keepalive: boolean }[] = []
  const save: SaveFn = async (page, { keepalive }) => {
    calls.push({ page, keepalive })
    return result
  }
  return { calls, save }
}

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

describe('createProgressSaver', () => {
  it('sends nothing for open-and-leave: page changes and a flush with the gate closed', () => {
    const { calls, save } = recorder()
    const saver = createProgressSaver(save)
    saver.update(1)
    saver.update(12)
    vi.advanceTimersByTime(5000)
    saver.flush({ keepalive: true })
    expect(calls).toEqual([])
  })

  it('sends the latest page once, about a second after it stops changing', () => {
    const { calls, save } = recorder()
    const saver = createProgressSaver(save)
    saver.openGate()
    saver.update(12)
    vi.advanceTimersByTime(500)
    saver.update(13)
    vi.advanceTimersByTime(999)
    expect(calls).toEqual([])
    vi.advanceTimersByTime(1)
    expect(calls).toEqual([{ page: 13, keepalive: false }])
  })

  it('flushes immediately with keepalive and cancels the pending debounce', () => {
    const { calls, save } = recorder()
    const saver = createProgressSaver(save)
    saver.openGate()
    saver.update(20)
    saver.flush({ keepalive: true })
    vi.advanceTimersByTime(5000)
    expect(calls).toEqual([{ page: 20, keepalive: true }])
  })

  it('does not resend the page last sent', () => {
    const { calls, save } = recorder()
    const saver = createProgressSaver(save)
    saver.openGate()
    saver.update(20)
    vi.advanceTimersByTime(1000)
    saver.flush()
    saver.update(20)
    vi.advanceTimersByTime(1000)
    expect(calls).toHaveLength(1)
  })

  it('treats a failed save as unsent, so the next flush retries it', async () => {
    const { calls, save } = recorder(false)
    const saver = createProgressSaver(save)
    saver.openGate()
    saver.update(20)
    saver.flush()
    await vi.runAllTimersAsync()
    saver.flush()
    expect(calls.map((c) => c.page)).toEqual([20, 20])
  })

  it('sends nothing after dispose', () => {
    const { calls, save } = recorder()
    const saver = createProgressSaver(save)
    saver.openGate()
    saver.update(20)
    saver.dispose()
    vi.advanceTimersByTime(5000)
    expect(calls).toEqual([])
  })
})
