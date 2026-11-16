import { describe, expect, it } from 'vitest'
import { createTheme, type ThemeEnvironment } from './theme'

type ChangeListener = (event: { matches: boolean }) => void

/** A browser in miniature: storage, the phone's light/dark setting, <html> and theme-color. */
function browser({ remembered = null as string | null, phoneDark = false } = {}) {
  const held = new Map<string, string>()
  if (remembered !== null) held.set('vista-theme', remembered)
  const listeners = new Set<ChangeListener>()
  const phone = {
    matches: phoneDark,
    addEventListener: (_: 'change', listener: ChangeListener) => void listeners.add(listener),
    removeEventListener: (_: 'change', listener: ChangeListener) => void listeners.delete(listener),
  }
  const attributes = new Map<string, string>()
  let themeColor = '#FFFFFF'
  const env: ThemeEnvironment = {
    storage: {
      getItem: (key) => held.get(key) ?? null,
      setItem: (key, value) => void held.set(key, value),
    },
    phone,
    root: {
      setAttribute: (name, value) => void attributes.set(name, value),
      removeAttribute: (name) => void attributes.delete(name),
    },
    themeColor: { setAttribute: (_, value) => void (themeColor = value) },
  }
  return {
    env,
    /** The phone or computer switching between light and dark. */
    flipPhone(dark: boolean) {
      phone.matches = dark
      for (const listener of listeners) listener({ matches: dark })
    },
    remembered: () => held.get('vista-theme') ?? null,
    /** What the page shows: <html data-theme> and theme-color. */
    painted: () => ({ dataTheme: attributes.get('data-theme') ?? null, themeColor }),
  }
}

const refuse = () => {
  throw new Error('blocked')
}

describe('the theme on opening', () => {
  it('follows the phone when nothing is remembered', () => {
    const light = browser({ phoneDark: false })
    expect(createTheme(light.env).theme.value).toBe('light')
    expect(light.painted()).toEqual({ dataTheme: null, themeColor: '#FFFFFF' })

    const dark = browser({ phoneDark: true })
    expect(createTheme(dark.env).theme.value).toBe('dark')
    expect(dark.painted()).toEqual({ dataTheme: 'dark', themeColor: '#1E1F45' })
  })

  it('takes the remembered choice over the phone', () => {
    const dark = browser({ remembered: 'dark', phoneDark: false })
    expect(createTheme(dark.env).theme.value).toBe('dark')
    expect(dark.painted()).toEqual({ dataTheme: 'dark', themeColor: '#1E1F45' })

    const light = browser({ remembered: 'light', phoneDark: true })
    expect(createTheme(light.env).theme.value).toBe('light')
    expect(light.painted()).toEqual({ dataTheme: null, themeColor: '#FFFFFF' })
  })

  it('treats a remembered value it does not know as nothing remembered', () => {
    const b = browser({ remembered: 'blue', phoneDark: true })
    expect(createTheme(b.env).theme.value).toBe('dark')
  })
})

describe('following the phone', () => {
  it('switches with the phone, live, before any press', () => {
    const b = browser({ phoneDark: false })
    const { theme } = createTheme(b.env)

    b.flipPhone(true)
    expect(theme.value).toBe('dark')
    expect(b.painted()).toEqual({ dataTheme: 'dark', themeColor: '#1E1F45' })

    b.flipPhone(false)
    expect(theme.value).toBe('light')
    expect(b.painted()).toEqual({ dataTheme: null, themeColor: '#FFFFFF' })
    expect(b.remembered()).toBeNull()
  })

  it('ignores the phone once a choice is remembered', () => {
    const b = browser({ remembered: 'light', phoneDark: false })
    const { theme } = createTheme(b.env)
    b.flipPhone(true)
    expect(theme.value).toBe('light')
    expect(b.painted().dataTheme).toBeNull()
  })
})

describe('pressing the toggle', () => {
  it('switches at once and remembers the choice', () => {
    const b = browser({ phoneDark: false })
    const control = createTheme(b.env)

    control.toggle()
    expect(control.theme.value).toBe('dark')
    expect(b.painted()).toEqual({ dataTheme: 'dark', themeColor: '#1E1F45' })
    expect(b.remembered()).toBe('dark')

    control.toggle()
    expect(control.theme.value).toBe('light')
    expect(b.painted()).toEqual({ dataTheme: null, themeColor: '#FFFFFF' })
    expect(b.remembered()).toBe('light')
  })

  it('stops following the phone', () => {
    const b = browser({ phoneDark: false })
    const control = createTheme(b.env)
    control.toggle()

    b.flipPhone(false)
    b.flipPhone(true)
    b.flipPhone(false)
    expect(control.theme.value).toBe('dark')
    expect(b.painted().dataTheme).toBe('dark')
  })

  it('is what the next opening shows', () => {
    const first = browser({ phoneDark: true })
    createTheme(first.env).toggle()

    const next = browser({ remembered: first.remembered(), phoneDark: true })
    expect(createTheme(next.env).theme.value).toBe('light')
  })
})

describe('when storage refuses', () => {
  it('follows the phone if reading throws', () => {
    const b = browser({ phoneDark: true })
    b.env.storage.getItem = refuse
    const { theme } = createTheme(b.env)
    expect(theme.value).toBe('dark')

    b.flipPhone(false)
    expect(theme.value).toBe('light')
  })

  it('still switches for this visit if writing throws', () => {
    const b = browser({ phoneDark: false })
    b.env.storage.setItem = refuse
    const control = createTheme(b.env)

    expect(() => control.toggle()).not.toThrow()
    expect(control.theme.value).toBe('dark')
    expect(b.painted()).toEqual({ dataTheme: 'dark', themeColor: '#1E1F45' })
    expect(b.remembered()).toBeNull()

    b.flipPhone(false)
    expect(control.theme.value).toBe('dark')
  })
})

it('works on a page with no theme-color tag', () => {
  const b = browser({ phoneDark: true })
  const control = createTheme({ ...b.env, themeColor: null })
  expect(() => control.toggle()).not.toThrow()
  expect(control.theme.value).toBe('light')
})
