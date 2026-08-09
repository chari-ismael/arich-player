/** Light / dark theme — persists in localStorage, respects system preference once. */

const KEY = 'arich_theme'

function systemPrefersLight() {
  return window.matchMedia('(prefers-color-scheme: light)').matches
}

export function getTheme() {
  const saved = localStorage.getItem(KEY)
  if (saved === 'light' || saved === 'dark') return saved
  return systemPrefersLight() ? 'light' : 'dark'
}

export function applyTheme(theme) {
  const next = theme === 'light' ? 'light' : 'dark'
  document.documentElement.dataset.theme = next
  document.documentElement.style.colorScheme = next
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) meta.setAttribute('content', next === 'light' ? '#F4F1EA' : '#0D1017')
  document.querySelectorAll('[data-theme-btn]').forEach((btn) => {
    btn.classList.toggle('is-on', btn.getAttribute('data-theme-btn') === next)
    btn.setAttribute('aria-pressed', btn.getAttribute('data-theme-btn') === next ? 'true' : 'false')
  })
  window.dispatchEvent(new CustomEvent('arich:theme', { detail: next }))
}

export function setTheme(theme) {
  const next = theme === 'light' ? 'light' : 'dark'
  localStorage.setItem(KEY, next)
  applyTheme(next)
}

export function toggleTheme() {
  setTheme(getTheme() === 'light' ? 'dark' : 'light')
}

export function initTheme() {
  applyTheme(getTheme())
  document.querySelectorAll('[data-theme-btn]').forEach((btn) => {
    btn.addEventListener('click', () => setTheme(btn.getAttribute('data-theme-btn')))
  })
  const toggle = document.getElementById('themeToggle')
  toggle?.addEventListener('click', () => toggleTheme())
}
