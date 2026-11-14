<script setup lang="ts">
// The one loading indicator (DESIGN 7.16). Only for a first load with nothing
// to show: pages holding cached data keep showing it while they refresh.
withDefaults(defineProps<{ text?: string }>(), { text: '載入中…' })
</script>

<template>
  <div class="flex flex-col items-center pt-24 text-center" role="status">
    <!-- The dots are decoration; the words say what is happening. -->
    <div class="flex h-4 items-end gap-1.5" aria-hidden="true">
      <span class="size-2 rounded-full bg-brand-vivid motion-safe:animate-[hop_900ms_ease-in-out_infinite]" />
      <span class="size-2 rounded-full bg-sun motion-safe:animate-[hop_900ms_ease-in-out_150ms_infinite]" />
      <span class="size-2 rounded-full bg-brand motion-safe:animate-[hop_900ms_ease-in-out_300ms_infinite]" />
    </div>
    <p class="mt-3 text-meta text-ink-faint">{{ text }}</p>
  </div>
</template>

<style>
@keyframes hop {
  0%,
  60%,
  100% {
    translate: 0 0;
  }
  30% {
    translate: 0 -6px;
  }
}
</style>
