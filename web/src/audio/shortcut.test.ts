import { describe, expect, it } from 'vitest'
import { createAudioShortcut, isAudioShortcut, type ShortcutKeydown } from './shortcut'

/** A keydown for the 3 on the number row with ⌘ held, plus whatever `over` changes. */
function keydown(over: Partial<ShortcutKeydown> = {}) {
  const event = {
    code: 'Digit3',
    metaKey: true,
    ctrlKey: false,
    altKey: false,
    shiftKey: false,
    repeat: false,
    prevented: false,
    preventDefault() {
      event.prevented = true
    },
    ...over,
  }
  return event
}

describe('isAudioShortcut', () => {
  it('is ⌘3', () => {
    expect(isAudioShortcut(keydown())).toBe(true)
  })

  it('is not 3 alone, or 3 with Control instead of ⌘', () => {
    expect(isAudioShortcut(keydown({ metaKey: false }))).toBe(false)
    expect(isAudioShortcut(keydown({ metaKey: false, ctrlKey: true }))).toBe(false)
  })

  it('is not ⌘3 with another modifier held', () => {
    expect(isAudioShortcut(keydown({ shiftKey: true }))).toBe(false)
    expect(isAudioShortcut(keydown({ altKey: true }))).toBe(false)
    expect(isAudioShortcut(keydown({ ctrlKey: true }))).toBe(false)
  })

  it('is not ⌘ with another key, nor the keypad 3', () => {
    expect(isAudioShortcut(keydown({ code: 'Digit2' }))).toBe(false)
    expect(isAudioShortcut(keydown({ code: 'Numpad3' }))).toBe(false)
  })
})

describe('createAudioShortcut', () => {
  it('presses what a button offered, and keeps ⌘3 from the browser', () => {
    const shortcut = createAudioShortcut()
    let presses = 0
    shortcut.offer(() => presses++)

    const event = keydown()
    shortcut.onKeydown(event)

    expect(presses).toBe(1)
    expect(event.prevented).toBe(true)
  })

  it('keeps ⌘3 from the browser even with nothing offered, as while a question is asked', () => {
    const shortcut = createAudioShortcut()
    const event = keydown()

    shortcut.onKeydown(event)

    expect(event.prevented).toBe(true)
  })

  it('leaves every other key alone', () => {
    const shortcut = createAudioShortcut()
    let presses = 0
    shortcut.offer(() => presses++)

    const event = keydown({ shiftKey: true })
    shortcut.onKeydown(event)

    expect(presses).toBe(0)
    expect(event.prevented).toBe(false)
  })

  it('presses once for a held key', () => {
    const shortcut = createAudioShortcut()
    let presses = 0
    shortcut.offer(() => presses++)

    shortcut.onKeydown(keydown())
    const repeat = keydown({ repeat: true })
    shortcut.onKeydown(repeat)

    expect(presses).toBe(1)
    expect(repeat.prevented).toBe(true)
  })

  it('presses nothing once the button has withdrawn', () => {
    const shortcut = createAudioShortcut()
    let presses = 0
    const press = () => presses++
    shortcut.offer(press)
    shortcut.withdraw(press)

    shortcut.onKeydown(keydown())

    expect(presses).toBe(0)
  })

  it('keeps the newer offer when an older button withdraws after it', () => {
    // The next question's button can mount before the last one's unmounts.
    const shortcut = createAudioShortcut()
    const pressed: string[] = []
    const older = () => pressed.push('older')
    const newer = () => pressed.push('newer')
    shortcut.offer(older)
    shortcut.offer(newer)
    shortcut.withdraw(older)

    shortcut.onKeydown(keydown())

    expect(pressed).toEqual(['newer'])
  })
})
