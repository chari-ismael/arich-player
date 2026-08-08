import { clamp, dur, easeInOutCubic, easeOutCubic, easeOutQuint, lerp } from './motion.js'

const LOGO_SRC = '/logo-fg.png'
const LOGO_SVG = '/logo-mark.svg'
const STORAGE_KEY = 'arich_booted'

/** Construction order matches the real mark: main A → inner bar → copper play. */
const PATH_ORDER = [
  { id: 'arich-main', kind: 'cream', start: 0, end: 0.42 },
  { id: 'arich-inner', kind: 'cream', start: 0.32, end: 0.72 },
  { id: 'arich-play', kind: 'play', start: 0.62, end: 1 },
]

/**
 * Signature boot: luminous tip traces REAL SVG geometry → exact logo mark → FLIP into nav.
 * First visit ~2.3s · return ~0.7s · prefers-reduced-motion: instant settle.
 *
 * Preview / debug (overrides reduced-motion):
 *   ?boot=force  — full first-visit cinematic
 *   ?boot=fresh  — same, clears arich_booted
 *   ?boot=slow   — full cinematic at 2.2× duration
 *   ?boot=0      — do not force (respect reduced-motion + storage)
 */
export function runArichLoader({ reduced } = {}) {
  const boot = document.getElementById('boot')
  const app = document.getElementById('app')
  const canvas = document.getElementById('bootCanvas')
  const mark = document.getElementById('bootMark')
  const markImg = document.getElementById('bootMarkImg')
  const construct = document.getElementById('bootConstruct')
  const navMark = document.getElementById('navBrandMark')
  const nav = document.getElementById('nav')

  if (!boot || !app) {
    return Promise.resolve()
  }

  const params = new URLSearchParams(location.search)
  const bootParam = params.has('boot') ? (params.get('boot') ?? '') : null
  const forceFresh = bootParam !== null && bootParam !== '0'
  if (forceFresh) sessionStorage.removeItem(STORAGE_KEY)
  const returning = !forceFresh && sessionStorage.getItem(STORAGE_KEY) === '1'
  const slowMo = bootParam === 'slow' ? 2.2 : 1

  if (reduced && !forceFresh) {
    if (typeof console !== 'undefined' && console.info) {
      console.info(
        '[arich] boot loader skipped (prefers-reduced-motion). Preview with ?boot=force',
      )
    }
    return settleInstant(boot, app, navMark, nav)
  }

  if (reduced && forceFresh) {
    document.documentElement.classList.add('arich-boot-force')
  }

  return new Promise((resolve) => {
    const ctx = canvas?.getContext('2d')
    if (!ctx || !mark || !markImg) {
      settleInstant(boot, app, navMark, nav).then(resolve)
      return
    }

    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    let w = 0
    let h = 0
    let start = 0
    let phase = 'draw'
    let handoffStart = 0
    let logoOpacity = 0
    let tip = null
    /** @type {{ el: SVGPathElement, len: number, kind: string, start: number, end: number }[]} */
    let tracks = []

    markImg.src = LOGO_SRC
    if (navMark) {
      navMark.src = LOGO_SRC
      navMark.style.opacity = '0'
    }

    function resize() {
      w = window.innerWidth
      h = window.innerHeight
      canvas.width = Math.floor(w * dpr)
      canvas.height = Math.floor(h * dpr)
      canvas.style.width = `${w}px`
      canvas.style.height = `${h}px`
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }

    resize()
    window.addEventListener('resize', resize, { passive: true })

    const totalMs = (returning ? dur.bootReturn : dur.bootFirst) * slowMo
    const drawEnd = returning ? 0.12 : 0.56
    const revealEnd = returning ? 0.38 : 0.78

    boot.classList.add('is-live')
    app.classList.add('is-booting')

    function svgPointToScreen(svg, pt) {
      const rect = mark.getBoundingClientRect()
      const vb = svg.viewBox.baseVal
      const sx = rect.width / vb.width
      const sy = rect.height / vb.height
      return {
        x: rect.left + pt.x * sx,
        y: rect.top + pt.y * sy,
      }
    }

    function applyDraw(drawP) {
      tip = null
      for (const track of tracks) {
        const local = clamp((drawP - track.start) / (track.end - track.start), 0, 1)
        const eased = easeInOutCubic(local)
        track.el.style.strokeDashoffset = String(track.len * (1 - eased))

        // Fill blooms once the silhouette is mostly traced
        const fillT = clamp((eased - 0.55) / 0.45, 0, 1)
        track.el.style.fillOpacity = String(easeOutQuint(fillT))
        track.el.style.strokeOpacity = String(1 - fillT * 0.85)

        if (local > 0 && local < 1) {
          const pt = track.el.getPointAtLength(track.len * eased)
          tip = { track, pt, eased }
        } else if (local >= 1 && !tip) {
          const pt = track.el.getPointAtLength(track.len)
          tip = { track, pt, eased: 1 }
        }
      }
    }

    function frame(now) {
      if (!start) start = now
      const elapsed = now - start
      const p = clamp(elapsed / totalMs, 0, 1)

      ctx.clearRect(0, 0, w, h)
      drawAtmosphere(ctx, w, h, p)

      if (phase === 'draw' || phase === 'reveal') {
        if (!returning && tracks.length) {
          const drawP = clamp(p / drawEnd, 0, 1)
          applyDraw(drawP)

          if (phase === 'draw' && tip) {
            const svg = construct?.querySelector('svg')
            if (svg) {
              const screen = svgPointToScreen(svg, tip.pt)
              const glow = tip.track.kind === 'play' ? 1.15 : 1
              drawEmber(ctx, screen.x, screen.y, glow)
            }
          }
        }

        if (p >= drawEnd) {
          phase = 'reveal'
          const rp = clamp((p - drawEnd) / (revealEnd - drawEnd), 0, 1)
          logoOpacity = easeOutQuint(rp)
          mark.style.opacity = '1'
          mark.classList.add('is-visible')
          mark.style.transform = `translate(-50%, -50%) scale(${lerp(0.94, 1, logoOpacity)})`
          markImg.style.opacity = String(logoOpacity)
          if (construct) {
            construct.style.opacity = String(1 - logoOpacity)
          }
          // Ensure geometry is fully settled under the asset
          if (tracks.length) applyDraw(1)
        }
      }

      if (p >= revealEnd && phase !== 'handoff' && phase !== 'done') {
        phase = 'handoff'
        handoffStart = now
        markImg.style.opacity = '1'
        if (construct) construct.style.opacity = '0'
        beginHandoff(mark, navMark, nav, boot, app).then(() => {
          phase = 'done'
          sessionStorage.setItem(STORAGE_KEY, '1')
          window.removeEventListener('resize', resize)
          stopTicks()
          document.documentElement.classList.remove('arich-boot-force')
          window.dispatchEvent(new CustomEvent('arich:ready'))
          resolve()
        })
      }

      if (phase === 'handoff') {
        const hp = clamp((now - handoffStart) / dur.handoff, 0, 1)
        canvas.style.opacity = String(1 - easeOutCubic(hp))
      }

      if (params.has('boot')) {
        window.__bootDebug = { p, phase, tracks: tracks.length, logoOpacity, tip, w, h }
      }
    }

    let kicked = false
    let tickTimer = 0
    const stopTicks = () => {
      if (tickTimer) window.clearInterval(tickTimer)
      tickTimer = 0
    }

    const kick = () => {
      if (kicked) return
      kicked = true
      mark.classList.add('is-visible')
      mark.style.opacity = '1'
      if (returning) {
        mark.style.transform = 'translate(-50%, -50%) scale(1)'
        markImg.style.opacity = '1'
        if (construct) construct.style.opacity = '0'
        logoOpacity = 1
      } else {
        // Construct SVG must be visible while geometry draws; PNG stays hidden until reveal
        mark.style.transform = 'translate(-50%, -50%) scale(0.94)'
        markImg.style.opacity = '0'
        if (construct) construct.style.opacity = '1'
      }
      tickTimer = window.setInterval(() => frame(performance.now()), 1000 / 60)
      frame(performance.now())
    }

    prepareGeometry(construct, returning)
      .then((prepared) => {
        tracks = prepared
        markImg.addEventListener('load', kick, { once: true })
        markImg.addEventListener('error', kick, { once: true })
        if (markImg.complete) kick()
        window.setTimeout(kick, 120)
      })
      .catch(() => {
        // Geometry unavailable — still hand off the exact PNG mark (no fake paths)
        if (construct) construct.style.opacity = '0'
        markImg.style.opacity = '1'
        mark.classList.add('is-visible')
        mark.style.opacity = '1'
        kick()
      })
  })
}

/**
 * Load real logo SVG into the construct layer and prep stroke lengths.
 * @returns {Promise<{ el: SVGPathElement, len: number, kind: string, start: number, end: number }[]>}
 */
async function prepareGeometry(construct, returning) {
  if (!construct) return []
  if (returning) {
    construct.innerHTML = ''
    return []
  }

  const res = await fetch(LOGO_SVG, { cache: 'force-cache' })
  if (!res.ok) throw new Error(`logo svg ${res.status}`)
  const text = await res.text()
  construct.innerHTML = text
  const svg = construct.querySelector('svg')
  if (!svg) throw new Error('logo svg missing root')

  svg.setAttribute('aria-hidden', 'true')
  // Tighten framing around the mark (content lives mid-viewBox)
  svg.setAttribute('viewBox', '48 100 400 320')
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet')

  const tracks = []
  for (const spec of PATH_ORDER) {
    const el = /** @type {SVGPathElement | null} */ (svg.querySelector(`#${spec.id}`))
    if (!el) continue
    const len = el.getTotalLength()
    el.classList.add(spec.kind === 'play' ? 'is-play' : 'is-cream')
    el.style.strokeDasharray = String(len)
    el.style.strokeDashoffset = String(len)
    el.style.fillOpacity = '0'
    el.style.strokeOpacity = '1'
    tracks.push({ el, len, kind: spec.kind, start: spec.start, end: spec.end })
  }

  if (!tracks.length) throw new Error('logo svg paths missing')
  return tracks
}

function drawAtmosphere(ctx, w, h, p) {
  const g = ctx.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.45, Math.max(w, h) * 0.55)
  g.addColorStop(0, `rgba(197,138,42,${0.05 + p * 0.035})`)
  g.addColorStop(0.45, 'rgba(13,16,23,0)')
  g.addColorStop(1, 'rgba(5,7,11,0)')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, w, h)
}

function drawEmber(ctx, x, y, s) {
  const r = 2.6 * s
  const g = ctx.createRadialGradient(x, y, 0, x, y, r * 7)
  g.addColorStop(0, 'rgba(255,220,150,0.9)')
  g.addColorStop(0.22, 'rgba(197,138,42,0.45)')
  g.addColorStop(1, 'rgba(197,138,42,0)')
  ctx.fillStyle = g
  ctx.beginPath()
  ctx.arc(x, y, r * 7, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = '#F0EFEC'
  ctx.beginPath()
  ctx.arc(x, y, r * 0.5, 0, Math.PI * 2)
  ctx.fill()
}

function beginHandoff(mark, navMark, nav, boot, app) {
  return new Promise((resolve) => {
    const from = mark.getBoundingClientRect()
    const to = navMark?.getBoundingClientRect()

    app.classList.remove('is-booting')
    app.classList.add('is-entering')
    nav?.classList.add('is-receiving')

    if (!to || !navMark) {
      finish()
      return
    }

    const dx = to.left + to.width / 2 - (from.left + from.width / 2)
    const dy = to.top + to.height / 2 - (from.top + from.height / 2)
    const scale = to.width / from.width

    mark.classList.add('is-flying')
    mark.style.transition = `transform ${dur.handoff}ms cubic-bezier(0.16, 1, 0.3, 1), opacity ${Math.round(dur.handoff * 0.55)}ms ${Math.round(dur.handoff * 0.45)}ms cubic-bezier(0.22, 1, 0.36, 1)`
    void mark.offsetWidth
    mark.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(${scale})`
    mark.style.opacity = '0'

    boot.style.transition = `opacity ${dur.handoff}ms cubic-bezier(0.22, 1, 0.36, 1), background ${dur.handoff}ms`
    boot.classList.add('is-handoff')

    window.setTimeout(finish, dur.handoff + 40)

    function finish() {
      navMark.style.opacity = '1'
      navMark.style.transition = 'opacity 180ms ease'
      boot.classList.add('is-done')
      mark.classList.remove('is-flying', 'is-visible')
      nav?.classList.remove('is-receiving')
      app.classList.remove('is-entering')
      app.classList.add('is-ready')
      resolve()
    }
  })
}

function settleInstant(boot, app, navMark, nav) {
  return new Promise((resolve) => {
    document.documentElement.classList.remove('arich-boot-force')
    if (navMark) navMark.style.opacity = '1'
    boot?.classList.add('is-done')
    app?.classList.remove('is-booting')
    app?.classList.add('is-ready')
    nav?.classList.remove('is-receiving')
    sessionStorage.setItem(STORAGE_KEY, '1')
    window.dispatchEvent(new CustomEvent('arich:ready'))
    resolve()
  })
}
