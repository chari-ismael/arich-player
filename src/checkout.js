/**
 * Pricing CTAs → full checkout page (auth-gated).
 */
export function initCheckout() {
  document.querySelectorAll('[data-plan]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.preventDefault()
      const plan = btn.getAttribute('data-plan') || 'lifetime'
      const safe = plan === 'yearly' ? 'yearly' : 'lifetime'
      window.location.href = `/checkout.html?plan=${safe}`
    })
  })
}
