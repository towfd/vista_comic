// The button styles of DESIGN.md section 7.1, as class strings, so every page
// draws the same buttons. Use them on <button> and on button-like RouterLinks.
//
// Primary buttons sit on a darker edge and sink onto it when pressed; with
// reduced motion they only change colour. `disabled:` covers <button> only --
// a link that is not available should not be rendered as one.

const primaryBase =
  'inline-flex items-center justify-center gap-2.5 rounded-full bg-brand text-white transition-[translate,box-shadow,background-color] duration-120 ease-standard hover:bg-brand-hover active:bg-brand-pressed active:shadow-edge-pressed motion-reduce:active:translate-y-0 disabled:bg-blush-strong disabled:text-ink-faint disabled:shadow-none disabled:active:translate-y-0'

/** 56px: the one main action of a screen (繼續閱讀, 開始複習, 送出 ...). Full width on a phone. */
export const primaryLg = `${primaryBase} h-14 w-full px-6 text-label shadow-edge active:translate-y-0.75`
/** 44px. */
export const primaryMd = `${primaryBase} h-11 px-5 text-body font-extrabold shadow-edge-sm active:translate-y-0.75`
/** 36px; pad the touch area to 44 where it stands alone (DESIGN 7.1). */
export const primarySm = `${primaryBase} h-9 px-4 text-meta font-extrabold shadow-edge-sm active:translate-y-0.5`

const secondaryBase =
  'inline-flex items-center justify-center gap-1.5 rounded-full bg-paper text-ink inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush disabled:text-ink-faint disabled:hover:bg-paper'

/** Beside a primary lg. */
export const secondaryLg = `${secondaryBase} h-14 px-6 text-label`
/** Beside a primary md, or alone. */
export const secondaryMd = `${secondaryBase} h-11 px-5 text-body font-extrabold`

/** A secondary button for a destructive action (刪除卡片) before it is confirmed. */
export const secondaryDangerMd = `${secondaryMd} text-danger`

/** Solid red: the confirming press of a destructive action. */
export const dangerMd =
  'inline-flex h-11 items-center justify-center gap-1.5 rounded-full bg-danger px-5 text-body font-extrabold text-white hover:bg-danger-hover active:bg-danger-hover disabled:bg-blush-strong disabled:text-ink-faint'

/** Solid amber: the confirming press of 重設為新卡. */
export const warningMd =
  'inline-flex h-11 items-center justify-center gap-1.5 rounded-full bg-warning px-5 text-body font-extrabold text-white active:scale-98 motion-reduce:active:scale-100 disabled:bg-blush-strong disabled:text-ink-faint'

/** Pink-on-blush, 36px with its touch area padded to 44. */
export const soft =
  "relative inline-flex h-9 items-center justify-center gap-1.5 rounded-full bg-blush px-4 text-meta font-extrabold text-brand before:absolute before:-inset-1 before:content-[''] hover:bg-blush-strong active:bg-blush-strong disabled:bg-mist disabled:text-ink-faint"

/** A quiet text button (結束, 設定 ...). */
export const textButton =
  'inline-flex h-11 items-center justify-center gap-1.5 rounded-full px-2 text-body text-ink-soft hover:bg-blush active:bg-blush disabled:text-ink-faint'

/** Round icon buttons (back, refresh, close). Always 44px; always give them an aria-label. */
export const iconButton =
  'grid size-11 shrink-0 place-items-center rounded-full bg-paper text-ink-soft inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush disabled:text-ink-faint'
export const iconButtonBlush =
  'grid size-11 shrink-0 place-items-center rounded-full bg-blush text-ink-soft hover:bg-blush-strong active:bg-blush-strong disabled:text-ink-faint'
