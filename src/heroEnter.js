import { site } from './config.js'
import { getLang } from './i18n.js'

/**
 * Hero entrance as continuation of the boot — mask reveals + product settle.
 * Not a generic stagger of opacity/translateY on every child.
 */
export function initHeroEnter({ reduced } = {}) {
  const hero = document.querySelector('.hero')
  const title = document.getElementById('heroTitle')
  if (!hero || !title) return

  const lines = [...title.querySelectorAll('.type-line')]

  function syncSlogan() {
    const slogan = site.slogan[getLang()] || site.slogan.fr
    lines.forEach((el, i) => {
      if (slogan[i]) el.textContent = slogan[i]
    })
    title.setAttribute('aria-label', slogan.join(' '))
  }

  syncSlogan()
  window.addEventListener('arich:lang', syncSlogan)

  if (reduced) {
    hero.classList.add('is-in')
    title.classList.add('is-typed')
    return
  }

  // Hold staged until boot completes
  hero.classList.add('is-waiting')

  const start = () => {
    hero.classList.remove('is-waiting')
    hero.classList.add('is-in')
    title.classList.add('is-typed')
  }

  if (document.getElementById('app')?.classList.contains('is-ready')) start()
  else window.addEventListener('arich:ready', start, { once: true })
}
