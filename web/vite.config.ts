import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// The browser only ever talks to this dev server. Requests for the catalog and
// for images are forwarded to the production backend with the Cloudflare
// Access Service Token attached here, on the Node side -- so the token never
// enters the bundle and no request is ever cross-origin.
//
// The variables are read with an empty prefix filter and deliberately carry no
// VITE_ prefix: Vite embeds every VITE_* variable into the browser bundle.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const target = env.VISTA_API_ORIGIN || 'https://api.vistabanana.com'

  const upstream = {
    target,
    // Cloudflare routes by hostname; a forwarded Host of localhost:5173 would
    // match no tunnel route.
    changeOrigin: true,
    headers: {
      'CF-Access-Client-Id': env.CF_ACCESS_CLIENT_ID ?? '',
      'CF-Access-Client-Secret': env.CF_ACCESS_CLIENT_SECRET ?? '',
    },
  }

  return {
    plugins: [vue(), tailwindcss()],
    server: {
      // Explicitly localhost: bound to the LAN, any machine on the network
      // could read the library through this proxy using the token.
      host: 'localhost',
      port: 5173,
      strictPort: true,
      proxy: {
        '/comics': upstream,
        '/media': upstream,
      },
    },
    test: {
      environment: 'node',
    },
  }
})
