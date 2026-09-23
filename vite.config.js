import { defineConfig } from 'vite'
import { resolve } from 'path'

function rewriteDownload(req) {
  if (!req.url) return
  const u = new URL(req.url, 'http://arich.local')
  const path = u.pathname
  if (
    path === '/download' ||
    path === '/download/' ||
    path === '/Download' ||
    path === '/Download/'
  ) {
    req.url = '/download/index.html' + u.search
  }
}

export default defineConfig({
  root: '.',
  publicDir: 'public',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
      },
    },
  },
  server: {
    port: 8765,
    open: true,
  },
  plugins: [
    {
      name: 'arich-download-page',
      configureServer(server) {
        server.middlewares.use((req, _res, next) => {
          rewriteDownload(req)
          next()
        })
      },
      configurePreviewServer(server) {
        server.middlewares.use((req, _res, next) => {
          rewriteDownload(req)
          next()
        })
      },
    },
  ],
})
