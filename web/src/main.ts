import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { router } from './router'
import { useTheme } from './theme'
import './style.css'

// Before the app mounts, so the theme follows the phone from the first page
// opened -- the reader included -- and lives as long as the page does, not as
// long as a component.
useTheme()

createApp(App).use(createPinia()).use(router).mount('#app')
