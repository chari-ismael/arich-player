/**
 * Discreet starfield background — few dots, soft twinkle, no dense webs.
 * Reduced-motion: static stars (no RAF thrash). Mobile: ~12–16 max.
 */
export function initParticles(canvas) {
  if (!canvas) return () => {}

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  const ctx = canvas.getContext('2d', { alpha: true })
  if (!ctx) {
    canvas.style.display = 'none'
    return () => {}
  }

  let raf = 0
  let running = true
  /** @type {{ x: number, y: number, r: number, tw: number, spd: number, warm: boolean }[]} */
  const stars = []
  const mobile = () => window.innerWidth < 768

  function count() {
    if (mobile()) return 14
    return 22
  }

  function spawn() {
    stars.length = 0
    const n = count()
    const w = window.innerWidth
    const h = window.innerHeight
    for (let i = 0; i < n; i++) {
      stars.push({
        x: Math.random() * w,
        y: Math.random() * h,
        r: Math.random() * 1.15 + 0.35,
        tw: Math.random() * Math.PI * 2,
        spd: 0.008 + Math.random() * 0.014,
        warm: Math.random() > 0.72,
      })
    }
  }

  function resize() {
    const dpr = Math.min(devicePixelRatio || 1, 1.5)
    canvas.width = Math.floor(window.innerWidth * dpr)
    canvas.height = Math.floor(window.innerHeight * dpr)
    canvas.style.width = `${window.innerWidth}px`
    canvas.style.height = `${window.innerHeight}px`
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    spawn()
    paint(0)
  }

  function paint(t) {
    const w = window.innerWidth
    const h = window.innerHeight
    ctx.clearRect(0, 0, w, h)

    for (const s of stars) {
      const pulse = reduced ? 0.55 : 0.38 + (Math.sin(t * s.spd + s.tw) * 0.5 + 0.5) * 0.42
      const a = pulse * (s.warm ? 0.55 : 0.42)

      // Soft glow halo (1 extra circle — cheap)
      if (s.r > 0.9) {
        ctx.beginPath()
        ctx.fillStyle = s.warm
          ? `rgba(197,138,42,${a * 0.22})`
          : `rgba(240,239,236,${a * 0.16})`
        ctx.arc(s.x, s.y, s.r * 3.2, 0, Math.PI * 2)
        ctx.fill()
      }

      ctx.beginPath()
      ctx.fillStyle = s.warm
        ? `rgba(212,160,74,${a})`
        : `rgba(240,239,236,${a})`
      ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  function tick(now) {
    if (!running) return
    raf = requestAnimationFrame(tick)
    paint(now * 0.001)
  }

  function start() {
    if (running) return
    running = true
    if (reduced) paint(0)
    else tick(performance.now())
  }

  function stop() {
    running = false
    cancelAnimationFrame(raf)
  }

  resize()
  if (reduced) {
    // One paint — no continuous animation
    paint(0)
  } else {
    tick(performance.now())
  }

  window.addEventListener('resize', resize, { passive: true })
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop()
    else {
      running = false
      start()
    }
  })

  return () => {
    stop()
    window.removeEventListener('resize', resize)
  }
}
