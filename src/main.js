import './styles.css'
import Lenis from 'lenis'
import { initI18n, getLang, applyI18n, t } from './i18n.js'
import { initParticles } from './particles.js'
import { pricing, downloadLinks, site, videos, posters } from './config.js'
import { initCheckout } from './checkout.js'
import { runArichLoader } from './loader.js'
import { initHeroEnter } from './heroEnter.js'

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
const browseProgress = document.getElementById('browseProgress')
const browseLabels = document.getElementById('browseLabels')
const browseCards = browseRail ? [...browseRail.querySelectorAll('.browse__card')] : []
const BROWSE_N = browseCards.length || 5

function updateBrowse() {
  if (!browsePin || !browseRail) return
  const rect = browsePin.getBoundingClientRect()
  const total = browsePin.offsetHeight - window.innerHeight
  if (total <= 0) return

  const scrolled = Math.min(Math.max(-rect.top, 0), total)
  const p = scrolled / total

  const maxX = Math.max(0, browseRail.scrollWidth - browseRail.parentElement.clientWidth)
  browseRail.style.transform = `translate3d(${-maxX * p}px, 0, 0)`

  if (browseProgress) browseProgress.style.width = `${p * 100}%`

  const idx = Math.min(BROWSE_N - 1, Math.floor(p * BROWSE_N + 0.01))
  browseCards.forEach((card, i) => card.classList.toggle('is-active', i === idx))
  browseLabels?.querySelectorAll('button').forEach((btn, i) => {
    btn.classList.toggle('is-active', i === idx)
  })
}

browseLabels?.querySelectorAll('button').forEach((btn) => {
  btn.addEventListener('click', () => {
    if (!browsePin) return
    const i = Number(btn.dataset.browse) || 0
    const total = browsePin.offsetHeight - window.innerHeight
    const target = browsePin.offsetTop + (total * i) / Math.max(1, BROWSE_N - 1)
    if (lenis) lenis.scrollTo(target, { duration: 1 })
    else window.scrollTo({ top: target, behavior: 'smooth' })
  })
})

/* ── Features morph scrub ──────────────────────────── */
const FEAT_KEYS = [
  { tag: 'feat_share_t', title: 'feat_share_t', body: 'feat_share_b' },
  { tag: 'feat_watch_t', title: 'feat_watch_t', body: 'feat_watch_b' },
  { tag: 'feat_offline_t', title: 'feat_offline_t', body: 'feat_offline_b' },
  { tag: 'feat_lang_t', title: 'feat_lang_t', body: 'feat_lang_b' },
  { tag: 'feat_theme_t', title: 'feat_theme_t', body: 'feat_theme_b' },
  { tag: 'feat_hist_t', title: 'feat_hist_t', body: 'feat_hist_b' },
]

const featPin = document.getElementById('featPin')
const featStack = document.getElementById('featStack')
const featSlides = featStack ? [...featStack.querySelectorAll('.featflow__slide')] : []
const featFloat = document.getElementById('featFloat')
const featFloatTag = document.getElementById('featFloatTag')
const featFloatTitle = document.getElementById('featFloatTitle')
const featFloatBody = document.getElementById('featFloatBody')
const featDots = document.getElementById('featDots')
const FEAT_N = featSlides.length || FEAT_KEYS.length
let featIdx = -1

function buildFeatDots() {
  if (!featDots) return
  featDots.innerHTML = ''
  for (let i = 0; i < FEAT_N; i++) {
    const b = document.createElement('button')
    b.type = 'button'
    b.setAttribute('aria-label', `Feature ${i + 1}`)
    b.addEventListener('click', () => {
      if (!featPin) return
      const total = featPin.offsetHeight - window.innerHeight
      const target = featPin.offsetTop + (total * i) / Math.max(1, FEAT_N - 1)
      if (lenis) lenis.scrollTo(target, { duration: 1 })
      else window.scrollTo({ top: target, behavior: 'smooth' })
    })
    featDots.appendChild(b)
  }
}

function setFeatFloat(i, visible) {
  const keys = FEAT_KEYS[i]
  if (!keys || !featFloat) return
  if (i !== featIdx) {
    featIdx = i
    if (featFloatTag) featFloatTag.textContent = t(keys.tag)
    if (featFloatTitle) featFloatTitle.textContent = t(keys.title)
    if (featFloatBody) featFloatBody.textContent = t(keys.body)
    featFloat.classList.toggle('is-left', i % 2 === 1)
    featDots?.querySelectorAll('button').forEach((btn, di) => {
      btn.classList.toggle('is-active', di === i)
    })
  }
  featFloat.classList.toggle('is-on', !!visible)
}

function updateFeatFlow() {
  if (!featPin || !featSlides.length) return
  const rect = featPin.getBoundingClientRect()
  const total = featPin.offsetHeight - window.innerHeight
  if (total <= 0) return

  const scrolled = Math.min(Math.max(-rect.top, 0), total)
  const p = scrolled / total
  featPin.classList.toggle('is-past-hint', p > 0.04)

  if (reduced) {
    featSlides.forEach((slide, i) => {
      slide.style.opacity = i === 0 ? '1' : '0'
      slide.style.transform = i === 0 ? 'scale(1)' : 'scale(0.28)'
      slide.style.zIndex = i === 0 ? '2' : '0'
    })
    setFeatFloat(0, true)
    return
  }

  const raw = p * (FEAT_N - 1)
  const i0 = Math.min(FEAT_N - 2, Math.floor(raw))
  const blend = Math.min(1, Math.max(0, raw - i0))
  const nearest = Math.min(FEAT_N - 1, Math.round(raw))

  featSlides.forEach((slide, i) => {
    let opacity = 0
    let scale = 0.28
    let blur = 0
    let z = 0

    if (i === i0) {
      opacity = 1 - blend * 0.9
      scale = 1 + blend * 0.22
      blur = blend * 4
      z = 2
    } else if (i === i0 + 1) {
      opacity = Math.min(1, blend * 1.15)
      scale = 0.22 + blend * 0.78
      blur = (1 - blend) * 3
      z = 3
    } else if (i < i0) {
      opacity = 0
      scale = 1.25
      z = 0
    } else {
      opacity = 0
      scale = 0.22
      z = 0
    }

    if (p >= 0.995 && i === FEAT_N - 1) {
      opacity = 1
      scale = 1
      blur = 0
      z = 4
    }

    slide.style.opacity = String(opacity)
    slide.style.transform = `scale(${scale})`
    slide.style.filter = blur > 0.2 ? `blur(${blur}px)` : 'none'
    slide.style.zIndex = String(z)
    slide.classList.toggle('is-active', i === nearest)
  })

  const floatStrength = 1 - Math.min(1, Math.abs(raw - nearest) * 2.4)
  setFeatFloat(nearest, floatStrength > 0.28)
}

buildFeatDots()

/* ── Lazy videos (IntersectionObserver) ────────────── */
function initLazyVideos() {
  const videosEls = document.querySelectorAll('video.lazy-video')
  if (!videosEls.length) return

  const playSafe = (v) => {
    const p = v.play()
    if (p?.catch) p.catch(() => {})
  }

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const v = entry.target
        if (entry.isIntersecting) {
          if (v.dataset.src && !v.src) {
            v.src = v.dataset.src
            v.load()
          }
          playSafe(v)
        } else {
          v.pause()
        }
      })
    },
    { threshold: 0.25, rootMargin: '80px' },
  )

  videosEls.forEach((v) => {
    v.muted = true
    v.playsInline = true
    io.observe(v)
  })

  // Pause si onglet caché
  document.addEventListener('visibilitychange', () => {
    videosEls.forEach((v) => {
      if (document.hidden) v.pause()
      else if (v.src && v.getBoundingClientRect().top < window.innerHeight) playSafe(v)
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
    el.textContent = pricing.currency
  })
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
    { sel: '.install__cta', kind: 'wipe-left' },
    { sel: '.pricing__cards', kind: 'scale' },
    { sel: '.faq__list', kind: 'rise' },
    { sel: '.contact__form', kind: 'wipe-left' },
    { sel: '.final-cta', kind: 'rise' },
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

/* ── FAQ accordion (one open) ──────────────────────── */
function initFaq() {
  const list = document.getElementById('faqList')
  if (!list) return
  list.querySelectorAll('details.faq__item').forEach((item) => {
    item.addEventListener('toggle', () => {
      if (!item.open) return
      list.querySelectorAll('details.faq__item').forEach((other) => {
        if (other !== item) other.open = false
      })
    })
  })
}

/* ── Contact form → mailto ─────────────────────────── */
function initContact() {
  const form = document.getElementById('contactForm')
  if (!form) return
  const status = document.getElementById('contactStatus')

  form.addEventListener('submit', (e) => {
    e.preventDefault()
    const name = /** @type {HTMLInputElement} */ (document.getElementById('contactName'))?.value.trim()
    const email = /** @type {HTMLInputElement} */ (document.getElementById('contactEmail'))?.value.trim()
    const subject = /** @type {HTMLInputElement} */ (document.getElementById('contactSubject'))?.value.trim()
    const message = /** @type {HTMLTextAreaElement} */ (document.getElementById('contactMessage'))?.value.trim()

    status?.classList.remove('is-error')
    if (!name || !email || !subject || !message) {
      if (status) {
        status.textContent = t('contact_err')
        status.classList.add('is-error')
      }
      return
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      if (status) {
        status.textContent = t('contact_err_email')
        status.classList.add('is-error')
      }
      return
    }

    const body = [
      `Nom: ${name}`,
      `Email: ${email}`,
      '',
      message,
    ].join('\n')
    const mailto = `mailto:${site.email}?subject=${encodeURIComponent(`[ARICH] ${subject}`)}&body=${encodeURIComponent(body)}`
    if (status) status.textContent = t('contact_ok')
    window.location.href = mailto
    form.reset()
  })
}

/* ── Scroll handler ────────────────────────────────── */
function onScroll() {
  updateNav()
  updateBrowse()
  updateFeatFlow()
  scrollTop?.classList.toggle('is-on', window.scrollY > 480)
}

window.addEventListener('scroll', onScroll, { passive: true })
window.addEventListener('resize', () => {
  updateBrowse()
  updateFeatFlow()
  updateNav()
})

/* ── Init ──────────────────────────────────────────── */
initI18n()
applyConfigUI()
initHeroEnter({ reduced })
initHeroTilt()
initLazyVideos()
initReveals()
initFaq()
initContact()
initCheckout()
onScroll()

runArichLoader({ reduced }).then(() => {
  if (!reduced) initParticles(document.getElementById('fx'))
})

window.addEventListener('arich:lang', () => {
  applyI18n()
  applyConfigUI()
  featIdx = -1
  updateFeatFlow()
})
