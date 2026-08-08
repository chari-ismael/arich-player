/** Shared motion language for ARICH — keep values intentional, not decorative. */
export const ease = {
  out: 'cubic-bezier(0.22, 1, 0.36, 1)',
  inOut: 'cubic-bezier(0.65, 0, 0.35, 1)',
  cinema: 'cubic-bezier(0.16, 1, 0.3, 1)',
  soft: 'cubic-bezier(0.33, 1, 0.68, 1)',
}

export const dur = {
  micro: 160,
  short: 320,
  med: 560,
  long: 900,
  bootFirst: 2300,
  bootReturn: 720,
  handoff: 780,
}

/** Cubic ease-out in JS timelines */
export function easeOutCubic(t) {
  return 1 - (1 - t) ** 3
}

export function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2
}

export function easeOutQuint(t) {
  return 1 - (1 - t) ** 5
}

export function lerp(a, b, t) {
  return a + (b - a) * t
}

export function clamp(v, min, max) {
  return Math.min(max, Math.max(min, v))
}
