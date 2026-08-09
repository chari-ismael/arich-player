/**
 * Cinema dust — tiny warm motes, not a starfield.
 * Few particles, very low alpha, almost unnoticed until compared to flat black.
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
  /** @type {{ x: number, y: number, r: number, tw: number, spd: number, drift: number }[]} */
  const motes = []
  const mobile = () => window.innerWidth < 768

  function count() {
    return mobile() ? 10 : 16
  }

  function spawn() {
    motes.length = 0
    const n = count()
    const w = window.innerWidth
    const h = window.innerHeight
    for (let i = 0; i < n; i++) {
      motes.push({
        x: Math.random() * w,
        y: Math.random() * h,
        r: Math.random() * 0.7 + 0.25,
        tw: Math.random() * Math.PI * 2,
        spd: 0.004 + Math.random() * 0.008,
        drift: (Math.random() - 0.5) * 0.04,
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

    for (const m of motes) {
      if (!reduced) {
        m.x += m.drift
        m.y += m.drift * 0.35
        if (m.x < -4) m.x = w + 4
        if (m.x > w + 4) m.x = -4
        if (m.y < -4) m.y = h + 4
        if (m.y > h + 4) m.y = -4
      }

      const pulse = reduced ? 0.5 : 0.35 + (Math.sin(t * m.spd + m.tw) * 0.5 + 0.5) * 0.35
      const a = pulse * 0.22

      ctx.beginPath()
      ctx.fillStyle = `rgba(210, 170, 110, ${a})`
      ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2)
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
  if (reduced) paint(0)
  else tick(performance.now())

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
