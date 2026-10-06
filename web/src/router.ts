import { createRouter, createWebHistory } from 'vue-router'
import LibraryView from './views/LibraryView.vue'
import ComicView from './views/ComicView.vue'
import ReaderView from './views/ReaderView.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'library', component: LibraryView },
    { path: '/comic/:comicId', name: 'comic', component: ComicView, props: true },
    { path: '/comic/:comicId/chapter/:chapterId', name: 'reader', component: ReaderView, props: true },
  ],
  // Without this the router keeps the previous page's scroll offset: a chapter
  // opened from far down a 1162-chapter list would open mid-chapter. Forward
  // navigation starts at the top; back and forward restore where you were.
  scrollBehavior(_to, _from, savedPosition) {
    return savedPosition ?? { top: 0 }
  },
})
