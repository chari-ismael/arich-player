/**
 * Maintenance-only dist (no Vite). Use when landing build is blocked
 * or we only need the maintenance façade online.
 */
import { cpSync, mkdirSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const dist = resolve(root, 'dist')
const pub = resolve(root, 'public')

rmSync(dist, { recursive: true, force: true })
mkdirSync(dist, { recursive: true })
cpSync(pub, dist, { recursive: true })
cpSync(resolve(pub, 'maintenance.html'), resolve(dist, 'index.html'))
writeFileSync(
  resolve(dist, 'maintenance.json'),
  JSON.stringify({ enabled: true, mode: 'maintenance-only', at: new Date().toISOString() }, null, 2),
)
console.log('maintenance-only dist ready')
