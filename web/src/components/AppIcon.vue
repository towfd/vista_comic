<script lang="ts">
/**
 * The line icons, one set for the whole site: 24-unit grid, 2px round-ended
 * strokes in the current text colour, so an icon takes the colour of whatever
 * it sits in. The tab bar's three are the preview's (direction C).
 */
const paths = {
  library: [
    'M5.1 4h1.3A1.6 1.6 0 0 1 8 5.6v12.8A1.6 1.6 0 0 1 6.4 20H5.1a1.6 1.6 0 0 1-1.6-1.6V5.6A1.6 1.6 0 0 1 5.1 4z',
    'M11.6 4h1.3a1.6 1.6 0 0 1 1.6 1.6v12.8a1.6 1.6 0 0 1-1.6 1.6h-1.3a1.6 1.6 0 0 1-1.6-1.6V5.6A1.6 1.6 0 0 1 11.6 4z',
    'M16.7 5.3l3.3-.9 3 14.9-3.3.9z',
  ],
  cards: [
    'M10.5 3.5h7a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-7a3 3 0 0 1-3-3v-9a3 3 0 0 1 3-3z',
    'M4 7.5v10.5a2.5 2.5 0 0 0 2.5 2.5H15',
  ],
  practice: [
    'M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17z',
    'M12 7.5a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9z',
    'M12 11.2a.8.8 0 1 1 0 1.6.8.8 0 0 1 0-1.6z',
  ],
  // Can't reach the server: a cloud, struck through.
  offline: ['M7.5 18a3.5 3.5 0 0 1-.4-6.98 5.5 5.5 0 0 1 10.6 1.04A3 3 0 0 1 17.5 18z', 'M3.5 3.5l17 17'],
  lock: ['M8 10.5h8a3 3 0 0 1 3 3v4a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3v-4a3 3 0 0 1 3-3z', 'M8.5 10.5v-3a3.5 3.5 0 0 1 7 0v3'],
  search: ['M11 4.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13z', 'M16 16l4.5 4.5'],
  alert: ['M12 5v9', 'M12 18.5v.01'],
  // The rest of the site's controls, here up front so the pages share one set.
  back: ['M15 5l-7 7 7 7'],
  forward: ['M9 5l7 7-7 7'],
  down: ['M6 9l6 6 6-6'],
  close: ['M6 6l12 12M18 6L6 18'],
  check: ['M5 12.5l4.5 4.5L19 7.5'],
  plus: ['M12 5v14M5 12h14'],
  refresh: ['M19.5 12a7.5 7.5 0 1 1-2.2-5.3', 'M19.5 4.5v4h-4'],
  play: ['M7 4.5v15l13-7.5z'],
  settings: ['M4 7h9M19 7h1M4 17h3M13 17h7', 'M16 4.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z', 'M10 14.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z'],
  calendar: ['M7 5.5h10a3 3 0 0 1 3 3v8.5a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V8.5a3 3 0 0 1 3-3z', 'M4 10h16M8.5 3.5v4M15.5 3.5v4'],
  book: ['M12 6.5C10 5 7 4.5 3.5 5v13c3.5-.5 6.5 0 8.5 1.5 2-1.5 5-2 8.5-1.5V5C17 4.5 14 5 12 6.5z', 'M12 6.5v13'],
  external: ['M14 4.5h5.5V10', 'M19.5 4.5L11 13', 'M18 14v3.5a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2H10'],
  trash: ['M4.5 7h15', 'M9.5 7V5a1.5 1.5 0 0 1 1.5-1.5h2A1.5 1.5 0 0 1 14.5 5v2', 'M6.5 7l.8 11.2A2 2 0 0 0 9.3 20h5.4a2 2 0 0 0 2-1.8L17.5 7'],
  sparkle: ['M12 4l1.8 4.7L18.5 10.5l-4.7 1.8L12 17l-1.8-4.7L5.5 10.5l4.7-1.8z'],
} satisfies Record<string, string[]>

export type IconName = keyof typeof paths
</script>

<script setup lang="ts">
defineProps<{ name: IconName }>()
</script>

<!-- Decorative: whatever it stands beside carries the words. 24px unless a
     size class (size-8 ...) says otherwise. -->
<template>
  <svg
    width="24"
    height="24"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    class="shrink-0"
  >
    <path v-for="d in paths[name]" :key="d" :d="d" />
  </svg>
</template>
