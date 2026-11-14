// Whether the chapter page was reached by walking the browser's history (back
// or forward) rather than by opening it. On a history walk the router restores
// the saved scroll position (router.ts scrollBehavior), and the page must not
// then jump to the current chapter over it.
//
// A `popstate` always precedes the router's handling of a history walk, and
// `location` is already the destination when it fires. Remembering that
// destination lets the page, once set up, compare it with where it is: a push
// made later to a different page never matches a stale record.

let traversedTo: string | null = null

if (typeof window !== 'undefined') {
  window.addEventListener('popstate', () => {
    traversedTo = window.location.pathname
  })
}

/** True when the page now showing was reached by back/forward. Consumes the record. */
export function takeArrivedByHistory(): boolean {
  const arrived = traversedTo !== null && traversedTo === window.location.pathname
  traversedTo = null
  return arrived
}
