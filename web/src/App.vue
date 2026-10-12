<script setup lang="ts">
import { useRoute } from 'vue-router'
import NavBar from './components/NavBar.vue'

const route = useRoute()
</script>

<template>
  <NavBar v-if="!route.meta.fullBleed" />
  <RouterView />
</template>
