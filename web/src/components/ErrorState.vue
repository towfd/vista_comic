<script setup lang="ts">
import type { ApiErrorKind } from '../api/client'

const props = defineProps<{
  kind: ApiErrorKind
  /** What was not found, for a not-found message that names the thing. */
  notFoundTitle?: string
}>()
defineEmits<{ retry: [] }>()

const messages: Record<ApiErrorKind, { title: string; hint: string }> = {
  auth: {
    title: '無法通過 Cloudflare 驗證',
    hint: '請檢查 web/.env 的 CF_ACCESS_CLIENT_ID 與 CF_ACCESS_CLIENT_SECRET，修改後重新啟動 npm run dev。',
  },
  unavailable: {
    title: '連不上伺服器',
    hint: '請確認網路連線，或伺服器是否正在運作。',
  },
  notFound: {
    title: '找不到這個項目',
    hint: '它可能已被移除，或書庫重新掃描過。',
  },
  unexpected: {
    title: '發生未預期的錯誤',
    hint: '請稍後再試。',
  },
}

const title = () => (props.kind === 'notFound' && props.notFoundTitle) || messages[props.kind].title
</script>

<template>
  <div class="mx-auto max-w-md py-24 text-center">
    <p class="text-lg font-medium text-neutral-100">{{ title() }}</p>
    <p class="mt-2 text-sm text-neutral-400">{{ messages[kind].hint }}</p>
    <div class="mt-6 flex justify-center gap-3">
      <!-- Retrying a 404 asks the same question for the same answer. -->
      <button
        v-if="kind !== 'notFound'"
        class="rounded-md bg-neutral-800 px-4 py-2 text-sm text-neutral-100 hover:bg-neutral-700"
        @click="$emit('retry')"
      >
        重試
      </button>
      <slot name="actions" />
    </div>
  </div>
</template>
