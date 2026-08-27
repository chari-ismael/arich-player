import './styles.css'
import Lenis from 'lenis'
import { initI18n, getLang, applyI18n, t, formatMoney } from './i18n.js'
import { initTheme } from './theme.js'
import { initParticles } from './particles.js'
import { pricing, downloadLinks, videos, posters } from './config.js'
import { initCheckout } from './checkout.js'
import { runArichLoader } from './loader.js'
import { initHeroEnter } from './heroEnter.js'
import { initContact } from './contact.js'
import { initFaq } from './faq.js'

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
const isMobile = () => window.matchMedia('(max-width: 768px)').matches
const app = document.getElementById('app')

/* ── Smooth scroll (Lenis) ─────────────────────────── */
let lenis = null
if (!reduced) {
  lenis = new Lenis({
    duration: 1.1,
    easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
    smoothWheel: true,
  })
  const raf = (time) => {
    lenis.raf(time)
    requestAnimationFrame(raf)
  }
  requestAnimationFrame(raf)
}

function scrollToEl(el, offset = -64) {
  if (!el) return
  if (lenis) lenis.scrollTo(el, { offset, duration: 1.2 })
  else {
    const top = el.getBoundingClientRect().top + window.scrollY + offset
    window.scrollTo({ top, behavior: 'smooth' })
  }
}

document.querySelectorAll('a[href^="#"]').forEach((a) => {
  a.addEventListener('click', (e) => {
    const href = a.getAttribute('href')
    if (!href || href === '#') return
    const el = document.querySelector(href)
    if (!el) return
    e.preventDefault()
    scrollToEl(el)
    document.getElementById('nav')?.classList.remove('is-open')
    document.getElementById('navBurger')?.setAttribute('aria-expanded', 'false')
  })
})

/* ── Navbar scroll + hamburger + liquid glass ──────── */
const nav = document.getElementById('nav')
const navBurger = document.getElementById('navBurger')
const navLinks = document.getElementById('navLinks')
const navPill = document.getElementById('navPill')
const navLiquid = document.getElementById('navLiquid')

navBurger?.addEventListener('click', () => {
  const open = nav?.classList.toggle('is-open')
  navBurger.setAttribute('aria-expanded', open ? 'true' : 'false')
})

navLinks?.querySelectorAll('a').forEach((a) => {
  a.addEventListener('click', () => {
    nav?.classList.remove('is-open')
    navBurger?.setAttribute('aria-expanded', 'false')
  })
})

if (navPill && navLiquid && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  navPill.addEventListener(
    'pointermove',
    (e) => {
      const r = navPill.getBoundingClientRect()
      const x = ((e.clientX - r.left) / r.width) * 100
      const y = ((e.clientY - r.top) / r.height) * 100
      navLiquid.style.setProperty('--lx', `${x}%`)
      navLiquid.style.setProperty('--ly', `${y}%`)
    },
    { passive: true },
  )
}

const sectionIds = ['top', 'features', 'browse', 'faq', 'contact', 'pricing']
const navLinksPill = document.getElementById('navLinksPill')

function syncNavPill() {
  if (!navLinks || !navLinksPill) return
  const active = navLinks.querySelector('a.is-active') || navLinks.querySelector('a')
  if (!active) {
    navLinksPill.style.opacity = '0'
    return
  }
  const parent = navLinks.getBoundingClientRect()
  const box = active.getBoundingClientRect()
  navLinksPill.style.width = `${box.width}px`
  navLinksPill.style.left = `${box.left - parent.left}px`
  navLinksPill.style.opacity = '1'
}

function updateNav() {
  const y = window.scrollY
  nav?.classList.toggle('is-scrolled', y > 40)

  let current = 'top'
  for (const id of sectionIds) {
    const el = document.getElementById(id)
    if (!el) continue
    if (el.getBoundingClientRect().top <= 120) current = id
  }
  navLinks?.querySelectorAll('a').forEach((a) => {
    const href = a.getAttribute('href') || ''
    a.classList.toggle('is-active', href === `#${current}`)
  })
  syncNavPill()
}

/* ── Hero tilt (after entrance settles) ─────────────── */
function initHeroTilt() {
  const compose = document.getElementById('heroCompose')
  const heroPhone = document.getElementById('heroPhone')
  if (!compose || reduced || isMobile()) return

  let tx = 0
  let ty = 0
  let cx = 0
  let cy = 0
  let active = false
  const stage = document.getElementById('heroStage')

  window.addEventListener(
    'pointermove',
    (e) => {
      if (!active || !stage) return
      const r = stage.getBoundingClientRect()
      const nx = (e.clientX - r.left) / r.width - 0.5
      const ny = (e.clientY - r.top) / r.height - 0.5
      tx = nx * 7
      ty = -ny * 5
    },
    { passive: true },
  )

  const loop = () => {
    if (active) {
      cx += (tx - cx) * 0.06
      cy += (ty - cy) * 0.06
      compose.style.transform = `rotateY(${cx}deg) rotateX(${cy}deg)`
      if (heroPhone) {
        heroPhone.style.transform = `rotateY(${-12 + cx * 0.3}deg) rotateZ(${-6 + cy * 0.25}deg) translateZ(40px)`
      }
    }
    requestAnimationFrame(loop)
  }
  loop()

  const arm = () => {
    const onEnd = (e) => {
      if (e.animationName !== 'heroProductIn') return
      compose.removeEventListener('animationend', onEnd)
      compose.style.animation = 'none'
      compose.style.opacity = '1'
      compose.style.filter = 'none'
      compose.style.transform = 'rotateY(0deg) rotateX(0deg)'
      active = true
    }
    compose.addEventListener('animationend', onEnd)
    window.setTimeout(() => {
      if (!active) {
        compose.style.animation = 'none'
        compose.style.opacity = '1'
        compose.style.filter = 'none'
        active = true
      }
    }, 1600)
  }
  if (app?.classList.contains('is-ready')) arm()
  else window.addEventListener('arich:ready', arm, { once: true })
}

/* ── Browse vertical → horizontal scrub ────────────── */
const browsePin = document.getElementById('browsePin')
const browseRail = document.getElementById('browseRail')
const browseViewport = browseRail?.parentElement || null
const browseProgress = document.getElementById('browseProgress')
const browseLabels = document.getElementById('browseLabels')
const browseCards = browseRail ? [...browseRail.querySelectorAll('.browse__card')] : []
const BROWSE_N = browseCards.length || 5

/** True while the browse pin owns the viewport (sticky scrub range). */
function isBrowseEngaged() {
  if (!browsePin) return false
  const rect = browsePin.getBoundingClientRect()
  // Pin top above/at viewport top, and pin still covers most of the screen
  return rect.top <= 1 && rect.bottom >= window.innerHeight * 0.55
}

function browseCardMid(card) {
  return card.offsetLeft + card.offsetWidth / 2
}

function updateBrowse() {
  if (!browsePin || !browseRail || !browseViewport) return
  const rect = browsePin.getBoundingClientRect()
  const total = browsePin.offsetHeight - window.innerHeight
  if (total <= 0) return

  const scrolled = Math.min(Math.max(-rect.top, 0), total)
  const p = scrolled / total

  // Focus progress across phones (0 → first, 1 → last)
  const raw = p * (BROWSE_N - 1)
  const i0 = Math.floor(raw)
  const i1 = Math.min(BROWSE_N - 1, i0 + 1)
  const localT = raw - i0
  const c0 = browseCards[i0]
  const c1 = browseCards[i1]
  if (!c0) return

  // Center the focused phone in the viewport (not leftover-overflow slide)
  const mid0 = browseCardMid(c0)
  const mid1 = c1 ? browseCardMid(c1) : mid0
  const focusMid = mid0 + (mid1 - mid0) * localT
  const x = browseViewport.clientWidth / 2 - focusMid
  browseRail.style.transform = `translate3d(${x}px, 0, 0)`

  if (browseProgress) browseProgress.style.width = `${p * 100}%`

  const idx = Math.min(BROWSE_N - 1, Math.round(raw))
  browseCards.forEach((card, i) => {
    const dist = Math.abs(raw - i)
    card.classList.toggle('is-active', i === idx)
    card.style.setProperty('--browse-dist', String(Math.min(2, dist)))
    const scale = 1 - Math.min(0.14, dist * 0.08)
    const blur = Math.min(3.5, dist * 1.6)
    const opacity = 1 - Math.min(0.55, dist * 0.28)
    const rot = (i - raw) * -7
    card.style.transform = `scale(${scale}) rotateY(${rot}deg) translateZ(${(1 - Math.min(1, dist)) * 28}px)`
    card.style.opacity = String(opacity)
    card.style.filter = blur > 0.15 ? `blur(${blur}px) brightness(${1 - dist * 0.12})` : 'none'
  })
  browseLabels?.querySelectorAll('button').forEach((btn, i) => {
    btn.classList.toggle('is-active', i === idx)
  })
}

browseLabels?.querySelectorAll('button').forEach((btn) => {
  btn.addEventListener('click', () => {
    if (!browsePin) return
    const i = Number(btn.dataset.browse) || 0
    const total = Math.max(0, browsePin.offsetHeight - window.innerHeight)
    const pinTop = browsePin.getBoundingClientRect().top + window.scrollY
    const target = pinTop + (total * i) / Math.max(1, BROWSE_N - 1)
    if (lenis) lenis.scrollTo(target, { duration: 1 })
    else window.scrollTo({ top: target, behavior: 'smooth' })
  })
})

/* ── Lazy videos (IntersectionObserver) ────────────── */
function playSafe(v) {
  v.muted = true
  v.defaultMuted = true
  v.playsInline = true
  v.setAttribute('muted', '')
  v.setAttribute('playsinline', '')
  v.setAttribute('webkit-playsinline', '')
  const p = v.play()
  if (p?.catch) p.catch(() => {})
}

function armVideoSource(v) {
  const want = v.dataset.src
  if (!want) return
  // HTMLMediaElement.src is never empty — use getAttribute
  if (v.getAttribute('src') !== want) {
    v.setAttribute('src', want)
    v.load()
  }
}

function markVideoReady(v) {
  if (v.classList.contains('is-ready')) return
  // Wait for a real painted frame so poster→video doesn't flash black
  const reveal = () => v.classList.add('is-ready')
  if (typeof v.requestVideoFrameCallback === 'function') {
    v.requestVideoFrameCallback(() => reveal())
  } else if (v.readyState >= 2 && !v.paused) {
    reveal()
  } else {
    v.addEventListener('playing', reveal, { once: true })
  }
}

/** Start hero/player downloads during boot so they're warm when the UI appears. */
function preloadHeroVideos() {
  document.querySelectorAll('.hero video.lazy-video, .feat-intro__player video.lazy-video').forEach((v) => {
    v.muted = true
    v.defaultMuted = true
    v.playsInline = true
    v.loop = true
    v.preload = 'auto'
    armVideoSource(v)
  })
}

function initLazyVideos() {
  const videosEls = document.querySelectorAll('video.lazy-video')
  if (!videosEls.length) return

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const v = entry.target
        if (entry.isIntersecting) {
          armVideoSource(v)
          playSafe(v)
          markVideoReady(v)
        } else {
          v.pause()
        }
      })
    },
    { threshold: 0.12, rootMargin: '200px 0px' },
  )

  videosEls.forEach((v) => {
    v.muted = true
    v.defaultMuted = true
    v.playsInline = true
    v.loop = true
    v.addEventListener('playing', () => markVideoReady(v))
    if (v.closest('.hero') || v.closest('.feat-intro__player')) {
      armVideoSource(v)
      playSafe(v)
      markVideoReady(v)
    }
    io.observe(v)
  })

  document.addEventListener('visibilitychange', () => {
    videosEls.forEach((v) => {
      if (document.hidden) v.pause()
      else if (v.getAttribute('src') && v.getBoundingClientRect().top < window.innerHeight) {
        playSafe(v)
        markVideoReady(v)
      }
    })
  })
}

/* ── Pricing / liens / QR / vidéos depuis config ───── */
function applyConfigUI() {
  const lang = getLang()
  const dlApk = document.getElementById('dlApk')
  const dlPlay = document.getElementById('dlPlay')
  if (dlApk) dlApk.href = downloadLinks.apk
  if (dlPlay) dlPlay.href = downloadLinks.googlePlay

  const qr = document.getElementById('qrImg')
  if (qr && downloadLinks.qrTarget) {
    const target = encodeURIComponent(downloadLinks.qrTarget)
    qr.src = `https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=${target}`
    qr.alt = 'QR — ' + downloadLinks.qrTarget
  }

  // Vidéos / posters (hero + player)
  const map = [
    { sel: '.hero__desktop video.lazy-video', src: videos.homeLand, poster: posters.homeLand },
    { sel: '.hero__phone video.lazy-video', src: videos.homePort, poster: posters.homePort },
    { sel: '.feat-intro__player video.lazy-video', src: videos.playerLand, poster: posters.playerLand || posters.player },
  ]
  map.forEach(({ sel, src, poster }) => {
    const v = document.querySelector(sel)
    if (!v) return
    v.dataset.src = src
    if (poster) v.setAttribute('poster', poster)
  })

  const trial = document.getElementById('trialDays')
  if (trial) trial.textContent = String(pricing.trialDays)

  const yearAmt = document.getElementById('priceYearAmt')
  const lifeAmt = document.getElementById('priceLifeAmt')
  const yearPer = document.getElementById('priceYearPer')
  const lifePer = document.getElementById('priceLifePer')
  const curs = document.querySelectorAll('.price-card__cur')

  if (yearAmt) yearAmt.textContent = String(pricing.yearly.price)
  if (lifeAmt) lifeAmt.textContent = String(pricing.lifetime.price)
  if (yearPer) yearPer.textContent = pricing.yearly.period[lang]
  if (lifePer) lifePer.textContent = pricing.lifetime.period[lang]
  curs.forEach((el) => {
    // Locale-aware currency symbol (fr-FR → "€", en-GB → "€")
    const sample = formatMoney(0).replace(/[\d\s.,]/g, '').trim()
    el.textContent = sample || pricing.currency
  })
  // Optional full-price aria labels for screen readers
  document.getElementById('priceYearCard')?.setAttribute(
    'aria-label',
    formatMoney(pricing.yearly.price) + ' / ' + pricing.yearly.period[lang],
  )
  document.getElementById('priceLifeCard')?.setAttribute(
    'aria-label',
    formatMoney(pricing.lifetime.price) + ' / ' + pricing.lifetime.period[lang],
  )
}

/* ── Scroll top ────────────────────────────────────── */
const scrollTop = document.getElementById('scrollTop')
scrollTop?.addEventListener('click', () => {
  if (lenis) lenis.scrollTo(0, { duration: 1.2 })
  else window.scrollTo({ top: 0, behavior: 'smooth' })
})

/* ── Reveals cinématiques (clip / wipe / scale) ────── */
function initReveals() {
  const targets = [
    { sel: '.section-head', kind: 'rise' },
    { sel: '.feat-intro__fluid', kind: 'wipe-left' },
    { sel: '.feat-intro__player', kind: 'scale' },
    { sel: '.stage__block', kind: 'alt' },
    { sel: '.need__compose', kind: 'scale' },
    { sel: '.steps', kind: 'rise' },
    { sel: '.dl-card', kind: 'wipe-left' },
    { sel: '.pricing__cards', kind: 'scale' },
    { sel: '.faq__tabs', kind: 'rise' },
    { sel: '.contact__layout', kind: 'wipe-left' },
    { sel: '.final-cta__inner', kind: 'rise' },
    { sel: '.hero__copy', kind: 'wipe-left' },
  ]

  const els = []
  let alt = 0
  for (const { sel, kind } of targets) {
    document.querySelectorAll(sel).forEach((el) => {
      let mode = kind
      if (kind === 'alt') {
        mode = alt % 2 === 0 ? 'wipe-left' : 'wipe-right'
        alt += 1
      }
      el.setAttribute('data-reveal', mode)
      els.push(el)
    })
  }

  if (reduced) {
    els.forEach((el) => el.classList.add('is-in'))
    return
  }

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return
        e.target.classList.add('is-in')
        io.unobserve(e.target)
      })
    },
    { threshold: 0.14, rootMargin: '0px 0px -8% 0px' },
  )
  els.forEach((el) => io.observe(el))
}

/* ── Install steps progress ────────────────────────── */
function updateInstallSteps() {
  const section = document.getElementById('install')
  const items = [...document.querySelectorAll('.steps__item')]
  const fill = document.getElementById('stepsFill')
  if (!section || !items.length) return
  const rect = section.getBoundingClientRect()
  const view = window.innerHeight || 1
  const visible = clamp01((view - rect.top) / (view + rect.height * 0.35))
  const idx = Math.min(2, Math.floor(visible * 3))
  items.forEach((el, i) => {
    el.classList.toggle('is-on', i === idx)
    el.classList.toggle('is-done', i < idx)
  })
  if (fill) fill.style.width = `${((idx + 1) / 3) * 100}%`
}

function clamp01(v) {
  return Math.min(1, Math.max(0, v))
}

/* ── Scroll handler ────────────────────────────────── */
function onScroll() {
  updateNav()
  updateBrowse()
  updateInstallSteps()
  scrollTop?.classList.toggle('is-on', window.scrollY > 480)
}

window.addEventListener('scroll', onScroll, { passive: true })
// Lenis emits on its own raf while smoothing — keep both so scrub stays 1:1
if (lenis) lenis.on('scroll', onScroll)
window.addEventListener('resize', () => {
  updateBrowse()
  updateNav()
})

/* ── Init ──────────────────────────────────────────── */
initI18n()
initTheme()
applyConfigUI()
preloadHeroVideos()
initHeroEnter({ reduced })
initHeroTilt()
initReveals()
initFaq()
initContact()
initCheckout()
onScroll()

runArichLoader({ reduced }).then(() => {
  initLazyVideos()
  initParticles(document.getElementById('fx'))
  onScroll()
  // Layout may settle after boot handoff — re-measure browse rail
  requestAnimationFrame(() => {
    updateBrowse()
    requestAnimationFrame(updateBrowse)
  })
})

window.addEventListener('arich:lang', () => {
  applyI18n()
  applyConfigUI()
})
