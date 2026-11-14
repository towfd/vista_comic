<script setup lang="ts">
import AppIcon, { type IconName } from './AppIcon.vue'

// Nothing here yet (DESIGN 7.15): the error screen's frame with a yellow
// sticker, and always a next step in the `actions` slot.
defineProps<{
  icon: IconName
  title: string
  hint?: string
}>()
defineSlots<{ actions?: () => unknown }>()
</script>

<template>
  <div class="flex flex-col items-center px-4 pt-16 text-center">
    <div
      class="grid size-18 -rotate-8 place-items-center rounded-full bg-sun text-ink ring-5 ring-paper outline-2 outline-offset-5 outline-blush-strong"
    >
      <AppIcon :name="icon" class="size-8" />
    </div>
    <p class="mt-4 text-heading text-ink">{{ title }}</p>
    <p v-if="hint" class="mt-1.5 max-w-[22em] text-meta text-ink-soft">{{ hint }}</p>
    <div v-if="$slots.actions" class="mt-6 flex flex-wrap justify-center gap-3">
      <slot name="actions" />
    </div>
  </div>
</template>
