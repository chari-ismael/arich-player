#!/usr/bin/env node
/** Push website/ subtree to chari-ismael/arich-player (GitHub Pages → arich.fr) */
import { execSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')

execSync('git subtree split -P website -b site-only', { cwd: root, stdio: 'inherit' })
execSync('git push pages site-only:main --force', { cwd: root, stdio: 'inherit' })
console.log('Site deploy pushed to pages → arich.fr')
