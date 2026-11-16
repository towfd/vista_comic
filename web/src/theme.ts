// Light or dark (DESIGN.md 7.18): the phone's or computer's setting until the
// reader presses the theme toggle, then the reader's choice, remembered in this
// browser. index.html picks the first theme before anything is drawn; this
// carries on from there for as long as the page is open.

import { readonly, ref, type Ref } from 'vue'

export type Theme = 'light' | 'dark'

/** Must match the pre-paint script in index.html. */
const THEME_KEY = 'vista-theme'

/** theme-color is the page colour of each theme (DESIGN.md 15.2). */
const PAGE_COLOUR: Record<Theme, string> = { light: '#FFFFFF', dark: '#1E1F45' }

/** What the theme reads and writes; the browser's own in the app, stand-ins in tests. */
export interface ThemeEnvironment {
  /** Called inside try/catch: storage may be missing or refuse (private mode). */
  storage: { getItem(key: string): string | null; setItem(key: string, value: string): void }
  /** matchMedia('(prefers-color-scheme: dark)'). */
  phone: {
    readonly matches: boolean
    addEventListener(type: 'change', listener: (event: { matches: boolean }) => void): void
    removeEventListener(type: 'change', listener: (event: { matches: boolean }) => void): void
  }
  /** <html>, which carries data-theme="dark". */
  root: { setAttribute(name: string, value: string): void; removeAttribute(name: string): void }
  /** <meta name="theme-color">, if the page has one. */
  themeColor: { setAttribute(name: string, value: string): void } | null
}

export interface ThemeControl {
  /** The theme on screen. */
  theme: Readonly<Ref<Theme>>
  /** The toggle's press: switch now, remember it, stop following the phone. */
  toggle(): void
}

export function createTheme(env: ThemeEnvironment): ThemeControl {
  const remembered = rememberedTheme(env.storage)
  const theme = ref<Theme>(remembered ?? phoneTheme(env.phone.matches))
  apply(env, theme.value)

  // Until the first press the app follows the phone, live: flipping the phone
  // to dark while the app is open flips the app too.
  const followPhone = (event: { matches: boolean }) => {
    theme.value = phoneTheme(event.matches)
    apply(env, theme.value)
  }
  if (!remembered) env.phone.addEventListener('change', followPhone)

  return {
    theme: readonly(theme),
    toggle() {
      theme.value = theme.value === 'dark' ? 'light' : 'dark'
      apply(env, theme.value)
      // Even where storage refuses, the press holds for this visit: the phone
      // no longer overrides it, though the next visit follows the phone again.
      env.phone.removeEventListener('change', followPhone)
      rememberTheme(env.storage, theme.value)
    },
  }
}

let site: ThemeControl | undefined

/** The site's theme, wired to this browser's storage, setting and <html> on first use. */
export function useTheme(): ThemeControl {
  site ??= createTheme({
    storage: {
      // Through the global on every call, so a storage that throws on mere
      // access is caught where the call is.
      getItem: (key) => localStorage.getItem(key),
      setItem: (key, value) => localStorage.setItem(key, value),
    },
    phone: matchMedia('(prefers-color-scheme: dark)'),
    root: instantly(document.documentElement),
    themeColor: document.querySelector('meta[name="theme-color"]'),
  })
  return site
}

/**
 * <html>, with every transition held while its theme changes. Buttons and
 * switches ease their colours over 120ms for a press; without the hold they
 * would fade into the new theme a beat behind the page, and a switch is meant
 * to be instant (DESIGN.md 7.18).
 */
function instantly(html: HTMLElement): ThemeEnvironment['root'] {
  const held = (change: () => void) => {
    const hold = document.createElement('style')
    hold.textContent = '*,*::before,*::after{transition:none!important}'
    document.head.append(hold)
    change()
    // Restyle now, with transitions off, so the new colours are already
    // settled when the hold is lifted and nothing is left to animate.
    void document.body.offsetHeight
    hold.remove()
  }
  return {
    setAttribute: (name, value) => held(() => html.setAttribute(name, value)),
    removeAttribute: (name) => held(() => html.removeAttribute(name)),
  }
}

const phoneTheme = (dark: boolean): Theme => (dark ? 'dark' : 'light')

/** The choice remembered in this browser, if any. A value it does not know counts as none, as in index.html. */
function rememberedTheme(storage: ThemeEnvironment['storage']): Theme | null {
  try {
    const stored = storage.getItem(THEME_KEY)
    if (stored === 'light' || stored === 'dark') return stored
  } catch {
    // Private mode, blocked storage: follow the phone.
  }
  return null
}

function rememberTheme(storage: ThemeEnvironment['storage'], theme: Theme) {
  try {
    storage.setItem(THEME_KEY, theme)
  } catch {
    // Not remembered, still shown.
  }
}

/** Switches at once: no fade (DESIGN.md 7.18). */
function apply(env: ThemeEnvironment, theme: Theme) {
  if (theme === 'dark') env.root.setAttribute('data-theme', 'dark')
  else env.root.removeAttribute('data-theme')
  env.themeColor?.setAttribute('content', PAGE_COLOUR[theme])
}
