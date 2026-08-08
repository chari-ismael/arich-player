import { clamp, dur, easeInOutCubic, easeOutCubic, easeOutQuint, lerp } from './motion.js'

const LOGO_SRC = '/logo-fg.png'
const STORAGE_KEY = 'arich_booted'

/**
 * Signature boot: copper ember draws depth trails → exact logo mark → FLIP into nav.
 * First visit ~2.3s · return ~0.7s · prefers-reduced-motion: instant settle.
 */
export function runArichLoader({ reduced } = {}) {
  const boot = document.getElementById('boot')
  const app = document.getElementById('app')
  const canvas = document.getElementById('bootCanvas')
  const mark = document.getElementById('bootMark')
  const markImg = document.getElementById('bootMarkImg')
  const navMark = document.getElementById('navBrandMark')
  const nav = document.getElementById('nav')

  if (!boot || !app) {
    return Promise.resolve()
  }

  const params = new URLSearchParams(location.search)
  const forceFresh = params.has('boot') && params.get('boot') !== '0'
  if (forceFresh) sessionStorage.removeItem(STORAGE_KEY)
  const returning = !forceFresh && sessionStorage.getItem(STORAGE_KEY) === '1'
  const slowMo = params.get('boot') === 'slow' ? 2.2 : 1

  if (reduced) {
    return settleInstant(boot, app, navMark, nav)
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

    const trails = []
    const paths = buildPaths()
    let ember = { x: 0, y: 0, z: 0 }
    let logoOpacity = 0
    let trailFade = 1
    let camPull = 0
    let lastTrailAt = 0

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
    const drawEnd = returning ? 0.18 : 0.58
    const revealEnd = returning ? 0.4 : 0.78

    boot.classList.add('is-live')
    app.classList.add('is-booting')

    function project(x, y, z) {
      const camZ = 3.4 - camPull * 0.55
      const f = 2.35 / (camZ - z)
      const scale = Math.min(w, h) * 0.22
      return {
        x: w * 0.5 + x * f * scale,
        y: h * 0.48 + y * f * scale,
        s: f,
        depth: clamp((z + 1) / 2, 0, 1),
      }
    }

    function samplePath(path, t) {
      const p = path.points
      if (p.length === 2) {
        return {
          x: lerp(p[0].x, p[1].x, t),
          y: lerp(p[0].y, p[1].y, t),
          z: lerp(p[0].z, p[1].z, t),
        }
      }
      // quadratic through mid control
      const u = 1 - t
      return {
        x: u * u * p[0].x + 2 * u * t * p[1].x + t * t * p[2].x,
        y: u * u * p[0].y + 2 * u * t * p[1].y + t * t * p[2].y,
        z: u * u * p[0].z + 2 * u * t * p[1].z + t * t * p[2].z,
      }
    }

    function frame(now) {
      if (!start) start = now
      const elapsed = now - start
      const p = clamp(elapsed / totalMs, 0, 1)

      ctx.clearRect(0, 0, w, h)
      drawAtmosphere(ctx, w, h, p)

      if (phase === 'draw' || phase === 'reveal') {
        if (!returning) {
          const drawP = clamp(p / drawEnd, 0, 1)
          camPull = easeOutCubic(drawP) * 0.9
          const pathProgress = drawP * paths.length * 0.999
          const pathIdx = Math.min(paths.length - 1, Math.floor(pathProgress))
          const pathT = pathProgress - pathIdx
          ember = samplePath(paths[pathIdx], easeInOutCubic(clamp(pathT, 0, 1)))

          // denser ribbon along the stroke
          if (now - lastTrailAt > 10) {
            trails.push({ ...ember, life: 1 })
            lastTrailAt = now
            if (trails.length > 220) trails.shift()
          }
        } else {
          camPull = easeOutCubic(clamp(p / 0.3, 0, 1))
        }

        for (const tr of trails) tr.life *= 0.978
        while (trails.length && trails[0].life < 0.05) trails.shift()

        trailFade = phase === 'reveal' ? 1 - clamp((p - drawEnd) / ((revealEnd - drawEnd) * 0.85), 0, 1) : 1
        drawTrails(ctx, trails, trailFade, project)

        if (!returning && phase === 'draw') {
          const pe = project(ember.x, ember.y, ember.z)
          drawEmber(ctx, pe.x, pe.y, pe.s)
        }

        if (p >= drawEnd) {
          phase = 'reveal'
          const rp = clamp((p - drawEnd) / (revealEnd - drawEnd), 0, 1)
          logoOpacity = easeOutQuint(rp)
          mark.style.opacity = String(logoOpacity)
          mark.style.transform = `translate(-50%, -50%) scale(${lerp(0.92, 1, logoOpacity)})`
          mark.classList.add('is-visible')
        }
      }

      if (p >= revealEnd && phase !== 'handoff' && phase !== 'done') {
        phase = 'handoff'
        handoffStart = now
        beginHandoff(mark, navMark, nav, boot, app).then(() => {
          phase = 'done'
          sessionStorage.setItem(STORAGE_KEY, '1')
          window.removeEventListener('resize', resize)
          stopTicks()
          window.dispatchEvent(new CustomEvent('arich:ready'))
          resolve()
        })
      }

      if (phase === 'handoff') {
        const hp = clamp((now - handoffStart) / dur.handoff, 0, 1)
        canvas.style.opacity = String(1 - easeOutCubic(hp))
      }

      if (params.has('boot')) {
        window.__bootDebug = { p, phase, trails: trails.length, ember, logoOpacity, w, h }
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
      mark.style.opacity = '0'
      mark.style.transform = 'translate(-50%, -50%) scale(0.88)'
      if (returning) {
        mark.classList.add('is-visible')
        logoOpacity = 1
        mark.style.opacity = '1'
        mark.style.transform = 'translate(-50%, -50%) scale(1)'
      }
      // Wall-clock ticker (more reliable than rAF in background tabs)
      tickTimer = window.setInterval(() => frame(performance.now()), 1000 / 60)
      frame(performance.now())
    }

    markImg.addEventListener('load', kick, { once: true })
    markImg.addEventListener('error', kick, { once: true })
    if (markImg.complete) kick()
    window.setTimeout(kick, 80)
  })
}

function buildPaths() {
  // Construction strokes in local space — final mark is the real logo asset.
  return [
    {
      points: [
        { x: -0.95, y: 0.95, z: -0.55 },
        { x: -0.55, y: -0.05, z: 0.05 },
        { x: -0.12, y: -0.98, z: 0.4 },
      ],
    },
    {
      points: [
        { x: -0.12, y: -0.98, z: 0.4 },
        { x: 0.42, y: -0.55, z: 0.25 },
        { x: 0.62, y: 0.35, z: -0.05 },
      ],
    },
    {
      points: [
        { x: 0.22, y: -0.2, z: 0.55 },
        { x: 0.3, y: 0.15, z: 0.35 },
        { x: 0.34, y: 0.72, z: 0.05 },
      ],
    },
    {
      points: [
        { x: 0.55, y: -0.02, z: 0.65 },
        { x: 0.82, y: 0.08, z: 0.2 },
        { x: 1.05, y: 0.18, z: -0.25 },
      ],
    },
  ]
}

function drawAtmosphere(ctx, w, h, p) {
  const g = ctx.createRadialGradient(w * 0.5, h * 0.45, 0, w * 0.5, h * 0.45, Math.max(w, h) * 0.55)
  g.addColorStop(0, `rgba(197,138,42,${0.06 + p * 0.04})`)
  g.addColorStop(0.45, 'rgba(13,16,23,0)')
  g.addColorStop(1, 'rgba(5,7,11,0)')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, w, h)
}

function drawTrails(ctx, trails, fade, project) {
  if (fade <= 0.01) return
  ctx.save()
  ctx.globalCompositeOperation = 'lighter'
  for (let i = 1; i < trails.length; i++) {
    const a = project(trails[i - 1].x, trails[i - 1].y, trails[i - 1].z)
    const b = project(trails[i].x, trails[i].y, trails[i].z)
    const life = trails[i].life * fade
    const width = lerp(1.2, 5.5, b.depth) * (0.55 + life * 0.7)
    ctx.beginPath()
    ctx.strokeStyle = `rgba(212,160,74,${0.16 + life * 0.55})`
    ctx.lineWidth = width
    ctx.lineCap = 'round'
    ctx.moveTo(a.x, a.y)
    ctx.lineTo(b.x, b.y)
    ctx.stroke()

    ctx.beginPath()
    ctx.strokeStyle = `rgba(240,239,236,${0.05 + life * 0.22 * b.depth})`
    ctx.lineWidth = width * 0.4
    ctx.moveTo(a.x, a.y)
    ctx.lineTo(b.x, b.y)
    ctx.stroke()
  }
  ctx.restore()
}

function drawEmber(ctx, x, y, s) {
  const r = 3.2 * s
  const g = ctx.createRadialGradient(x, y, 0, x, y, r * 7)
  g.addColorStop(0, 'rgba(255,220,150,0.95)')
  g.addColorStop(0.2, 'rgba(197,138,42,0.55)')
  g.addColorStop(1, 'rgba(197,138,42,0)')
  ctx.fillStyle = g
  ctx.beginPath()
  ctx.arc(x, y, r * 7, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = '#F0EFEC'
  ctx.beginPath()
  ctx.arc(x, y, r * 0.55, 0, Math.PI * 2)
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
