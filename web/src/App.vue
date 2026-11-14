<script setup lang="ts">
import { onMounted, onUnmounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useDeckStore } from './stores/deck'
import TabBar from './components/TabBar.vue'

const route = useRoute()
const deck = useDeckStore()

// The count beside 練習 is fetched behind whatever page is showing. A failure
// is never surfaced: the tab simply reads 練習 with no number, and the page
// under it is neither delayed nor told. Pages about cards load the deck
// themselves; the library is the one tab that does not, so it is loaded here
// on arriving there -- here and not in the tab bar, which is absent from the
// sub-pages a visit to the library passes through.
watch(
  () => route.meta.section,
  (section) => {
    if (section === 'library' && !deck.loaded && !deck.loading) deck.load()
  },
  { immediate: true },
)

// Coming back to the tab is the ordinary way a deck goes stale: the reader
// was on the phone. Listened for here, on every page but the manga reader,
// which shows nothing about cards -- the count must be current when the tab
// bar reappears, not only while it is on screen.
function onVisibilityChange() {
  if (document.visibilityState === 'visible' && !route.meta.fullBleed) deck.refresh()
}

// iOS Safari leaves :active unset on a tap unless the page listens for
// touches; without this no `active:` press style would show on the phone.
function onTouchStart() {}

onMounted(() => {
  document.addEventListener('visibilitychange', onVisibilityChange)
  document.addEventListener('touchstart', onTouchStart, { passive: true })
})
onUnmounted(() => {
  document.removeEventListener('visibilitychange', onVisibilityChange)
  document.removeEventListener('touchstart', onTouchStart)
})
</script>

<template>
  <!--
    The tab bar covers the bottom of the page it sits on, so those pages end
    with room for it: its 52px plus 24 of air. The Home bar under it is
    already cleared by the body's safe-area padding (style.css).
  -->
  <div :class="route.meta.tabBar && 'pb-19'">
    <RouterView />
  </div>
  <TabBar v-if="route.meta.tabBar" />
</template>
