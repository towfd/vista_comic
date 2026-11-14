<script setup lang="ts">
import type { ApiErrorKind } from '../api/client'
import AppIcon, { type IconName } from './AppIcon.vue'

const props = defineProps<{
  kind: ApiErrorKind
  /** What was not found, for a not-found message that names the thing. */
  notFoundTitle?: string
}>()
defineEmits<{ retry: [] }>()
defineSlots<{
  /**
   * The page's own way out (回到書庫 ...). `buttonClass` styles it to sit
   * beside 重試: secondary, or -- where there is no retry -- primary, so the
   * screen always has one main action.
   */
  actions?: (props: { buttonClass: string }) => unknown
}>()

const messages: Record<ApiErrorKind, { title: string; hint: string; icon: IconName }> = {
  auth: {
    title: '無法通過 Cloudflare 驗證',
    hint: '請檢查 web/.env 的 CF_ACCESS_CLIENT_ID 與 CF_ACCESS_CLIENT_SECRET，修改後重新啟動 npm run dev。',
    icon: 'lock',
  },
  unavailable: {
    title: '連不上伺服器',
    hint: '請確認網路連線，或伺服器是否正在運作。',
    icon: 'offline',
  },
  notFound: {
    title: '找不到這個項目',
    hint: '它可能已被移除，或書庫重新掃描過。',
    icon: 'search',
  },
  unexpected: {
    title: '發生未預期的錯誤',
    hint: '請稍後再試。',
    icon: 'alert',
  },
}

const title = () => (props.kind === 'notFound' && props.notFoundTitle) || messages[props.kind].title

// Medium buttons (44px): the primary one sinks onto its edge when pressed.
const primaryButton =
  'inline-flex h-11 items-center justify-center gap-2 rounded-full bg-brand px-5 text-body font-extrabold text-white shadow-edge-sm transition-[translate,box-shadow,background-color] duration-120 ease-standard hover:bg-brand-hover active:translate-y-0.75 active:bg-brand-pressed active:shadow-edge-pressed motion-reduce:active:translate-y-0'
const secondaryButton =
  'inline-flex h-11 items-center justify-center gap-1.5 rounded-full bg-paper px-5 text-body font-extrabold text-ink inset-ring-2 inset-ring-line hover:bg-blush active:bg-blush'
</script>

<template>
  <div class="flex flex-col items-center px-4 pt-16 text-center">
    <!-- The sticker: white gap, then a pink rim, like a die-cut sticker. -->
    <div
      class="grid size-18 -rotate-6 place-items-center rounded-full bg-blush-strong text-brand ring-5 ring-paper outline-2 outline-offset-5 outline-blush-strong"
    >
      <AppIcon :name="messages[kind].icon" class="size-8" />
    </div>
    <p class="mt-4 text-heading text-ink">{{ title() }}</p>
    <p class="mt-1.5 max-w-[22em] text-meta text-ink-soft">{{ messages[kind].hint }}</p>
    <div class="mt-6 flex flex-wrap justify-center gap-3">
      <!-- Retrying a 404 asks the same question for the same answer. -->
      <button v-if="kind !== 'notFound'" type="button" :class="primaryButton" @click="$emit('retry')">重試</button>
      <slot name="actions" :buttonClass="kind === 'notFound' ? primaryButton : secondaryButton" />
    </div>
  </div>
</template>
