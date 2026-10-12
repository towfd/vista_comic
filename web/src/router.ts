import { createRouter, createWebHistory } from 'vue-router'
import LibraryView from './views/LibraryView.vue'
import ComicView from './views/ComicView.vue'
import ReaderView from './views/ReaderView.vue'
import PracticeView from './views/PracticeView.vue'

declare module 'vue-router' {
  interface RouteMeta {
    /** Which entry of the navigation bar is current on this route. */
    section?: 'library' | 'practice'
    /** Hides the navigation bar. */
    fullBleed?: boolean
  }
}

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'library', component: LibraryView, meta: { section: 'library' } },
    { path: '/comic/:comicId', name: 'comic', component: ComicView, props: true, meta: { section: 'library' } },
    // The reader keeps the whole screen: no navigation bar over the manga.
    { path: '/comic/:comicId/chapter/:chapterId', name: 'reader', component: ReaderView, props: true, meta: { fullBleed: true } },
    { path: '/practice', name: 'practice', component: PracticeView, meta: { section: 'practice' } },
  ],
  // Without this the router keeps the previous page's scroll offset: a chapter
  // opened from far down a 1162-chapter list would open mid-chapter. Forward
  // navigation starts at the top; back and forward restore where you were.
  scrollBehavior(_to, _from, savedPosition) {
    return savedPosition ?? { top: 0 }
  },
})
