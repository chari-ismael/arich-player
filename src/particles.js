/**
 * Particules interactives subtiles — pause onglet caché, allégé mobile, respects prefers-reduced-motion
 */
export function initParticles(canvas) {
  if (!canvas) return () => {}

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  if (reduced) {
    canvas.style.display = 'none'
    return () => {}
  }

  const ctx = canvas.getContext('2d', { alpha: true })
  let raf = 0
  let running = true
  const mouse = { x: -9999, y: -9999 }
  const dots = []
  const mobile = () => window.innerWidth < 768

  function count() {
    const area = window.innerWidth * window.innerHeight
    if (mobile()) return Math.min(28, Math.floor(area / 38000))
    return Math.min(56, Math.floor(area / 22000))
  }

  function resize() {
    const dpr = Math.min(devicePixelRatio || 1, 2)
    canvas.width = window.innerWidth * dpr
    canvas.height = window.innerHeight * dpr
    canvas.style.width = `${window.innerWidth}px`
    canvas.style.height = `${window.innerHeight}px`
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    dots.length = 0
    const n = count()
    for (let i = 0; i < n; i++) {
      dots.push({
        x: Math.random() * window.innerWidth,
        y: Math.random() * window.innerHeight,
        r: Math.random() * 1.4 + 0.3,
        vx: (Math.random() - 0.5) * 0.1,
        vy: (Math.random() - 0.5) * 0.1,
        tw: Math.random() * Math.PI * 2,
      })
    }
  }

  function tick() {
    if (!running) return
    raf = requestAnimationFrame(tick)
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight)

    const linkDist = mobile() ? 70 : 95
    const mouseDist = mobile() ? 120 : 160

    for (const d of dots) {
      d.tw += 0.018
      const dx = mouse.x - d.x
      const dy = mouse.y - d.y
      const dist = Math.hypot(dx, dy) || 1
      if (dist < 200 && !mobile()) {
        d.vx += (dx / dist) * 0.012
        d.vy += (dy / dist) * 0.012
      }
      d.x += d.vx
      d.y += d.vy
      d.vx *= 0.986
      d.vy *= 0.986
      if (d.x < 0 || d.x > window.innerWidth) d.vx *= -1
      if (d.y < 0 || d.y > window.innerHeight) d.vy *= -1

      const alpha = 0.22 + Math.sin(d.tw) * 0.1
      ctx.beginPath()
      ctx.fillStyle = `rgba(240,239,236,${alpha})`
      ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2)
      ctx.fill()

      if (!mobile() && dist < mouseDist) {
        ctx.strokeStyle = `rgba(197,138,42,${0.2 * (1 - dist / mouseDist)})`
        ctx.lineWidth = 0.7
        ctx.beginPath()
        ctx.moveTo(d.x, d.y)
        ctx.lineTo(mouse.x, mouse.y)
        ctx.stroke()
      }
    }

    // Fils entre points proches (skip densité mobile)
    const step = mobile() ? 2 : 1
    for (let i = 0; i < dots.length; i += step) {
      for (let j = i + 1; j < dots.length; j += step) {
        const a = dots[i]
        const b = dots[j]
        const dist = Math.hypot(a.x - b.x, a.y - b.y)
        if (dist < linkDist) {
          ctx.strokeStyle = `rgba(197,138,42,${0.09 * (1 - dist / linkDist)})`
          ctx.beginPath()
          ctx.moveTo(a.x, a.y)
          ctx.lineTo(b.x, b.y)
          ctx.stroke()
        }
      }
    }
  }

  function start() {
    if (running) return
    running = true
    tick()
  }
  function stop() {
    running = false
    cancelAnimationFrame(raf)
  }

  resize()
  tick()

  window.addEventListener('resize', resize)
  window.addEventListener(
    'pointermove',
    (e) => {
      if (mobile()) return
      mouse.x = e.clientX
      mouse.y = e.clientY
    },
    { passive: true },
  )
  window.addEventListener('pointerleave', () => {
    mouse.x = -9999
    mouse.y = -9999
  })
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop()
    else start()
  })

  return () => {
    stop()
    window.removeEventListener('resize', resize)
  }
}
