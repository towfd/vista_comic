<script setup lang="ts">
// Plays one card's recording on a press; a press while it loads or plays
// stops it. Never plays by itself. The page shares one player, so pressing
// another button stops this one (see audio/player.ts).
//
// Render it only for a card whose `hasAudio` is true: it does not ask first.
import { computed, onUnmounted, watch } from 'vue'
import { cardAudioPath } from '../api/client'
import { player } from '../audio/player'
import AppIcon from './AppIcon.vue'

const props = withDefaults(defineProps<{ cardId: number; label?: string }>(), { label: '播放發音' })

// Each button is its own owner: one card can have two buttons on a screen.
const me = Symbol('card-audio-button')
const phase = computed(() => player.phaseOf(me))

const press = () => player.toggle(me, cardAudioPath(props.cardId))

// A button that leaves the screen, or moves to another card, takes its sound along.
watch(
  () => props.cardId,
  () => player.stop(me),
)
onUnmounted(() => player.stop(me))
</script>

<template>
  <button
    type="button"
    class="grid size-11 shrink-0 place-items-center rounded-full transition-colors duration-120"
    :class="
      phase === 'playing'
        ? 'bg-brand text-on-fill'
        : 'bg-paper text-brand inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush'
    "
    :aria-label="phase === 'idle' ? label : '停止播放'"
    :aria-busy="phase === 'loading'"
    @click="press"
  >
    <AppIcon v-if="phase === 'loading'" name="refresh" class="size-5 animate-spin motion-reduce:animate-none" />
    <AppIcon v-else-if="phase === 'playing'" name="stop" class="size-6 fill-current" />
    <AppIcon v-else name="speaker" class="size-5.5" />
  </button>
</template>
