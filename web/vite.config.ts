import { readFile } from 'node:fs/promises'
import { join, normalize } from 'node:path'
import { defineConfig, loadEnv, type Plugin } from 'vite'
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
    plugins: [vue(), tailwindcss(), ocrData(env.OCR_DATA_PATH)],
    server: {
      // Explicitly localhost: bound to the LAN, any machine on the network
      // could read the library through this proxy using the token.
      host: 'localhost',
      port: 5173,
      strictPort: true,
      proxy: {
        '/comics': upstream,
        '/media': upstream,
        '/cards': upstream,
        '/study': upstream,
        '/rescan': upstream,
        '/line-analyses': upstream,
      },
    },
    test: {
      environment: 'node',
    },
  }
})

// Serves the comic-ocr-data folder (OCR_DATA_PATH in web/.env) at
// /ocr-data/<work_id>/<file>.json -- what nginx.conf.template does in the container.
function ocrData(root: string | undefined): Plugin {
  return {
    name: 'ocr-data',
    configureServer(server) {
      server.middlewares.use('/ocr-data', async (req, res) => {
        const rel = normalize(decodeURIComponent((req.url ?? '').split('?')[0] ?? ''))
        if (!root || rel.includes('..') || !rel.endsWith('.json')) {
          res.statusCode = 404
          res.end()
          return
        }
        try {
          const body = await readFile(join(root, rel))
          res.setHeader('Content-Type', 'application/json')
          res.end(body)
        } catch {
          res.statusCode = 404
          res.end()
        }
      })
    },
  }
}
