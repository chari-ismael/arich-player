/**
 * After Vite build: optionally serve maintenance as the homepage.
 *
 * Always copies maintenance.html + 404.html into dist.
 * Maintenance ON when: MAINTENANCE=1 or --on (and not --off)
 * Default: OFF → real landing as index.html
 */
import { copyFileSync, existsSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')
const dist = resolve(root, 'dist')
const pub = resolve(root, 'public')

const enabled =
  !process.argv.includes('--off') &&
  (process.env.MAINTENANCE === '1' || process.argv.includes('--on'))
mkdirSync(dist, { recursive: true })

const maintSrc = resolve(pub, 'maintenance.html')
const notFoundSrc = resolve(pub, '404.html')

if (!existsSync(maintSrc)) {
  console.error('missing public/maintenance.html')
  process.exit(1)
}

copyFileSync(maintSrc, resolve(dist, 'maintenance.html'))

if (existsSync(notFoundSrc)) {
  copyFileSync(notFoundSrc, resolve(dist, '404.html'))
}

writeFileSync(
  resolve(dist, 'maintenance.json'),
  JSON.stringify({ enabled, at: new Date().toISOString() }, null, 2),
)

if (enabled) {
  const builtIndex = resolve(dist, 'index.html')
  if (existsSync(builtIndex)) {
    copyFileSync(builtIndex, resolve(dist, 'landing.html'))
  }
  copyFileSync(maintSrc, builtIndex)
  console.log('MAINTENANCE ON → dist/index.html is maintenance page (landing saved as landing.html)')
} else {
  console.log('MAINTENANCE OFF → normal landing')
}
