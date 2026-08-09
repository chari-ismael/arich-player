import { SUPABASE_URL, SUPABASE_ANON_KEY, pricing } from './config.js'
import { getLang } from './i18n.js'

/**
 * Checkout via Device Key modal — calme, guidé.
 * Labels de plan depuis pricing (config centralisée).
 */
export function initCheckout() {
  const modal = document.getElementById('modal')
  const input = document.getElementById('modalKey')
  const err = document.getElementById('modalErr')
  const planLabel = document.getElementById('modalPlan')
  const ok = document.getElementById('modalOk')
  const cancel = document.getElementById('modalCancel')

  if (!modal || !input || !ok || !cancel) return

  let plan = null

  function planText(id) {
    const lang = getLang()
    const cur = pricing.currency
    if (id === 'yearly') {
      return `${pricing.yearly.label[lang]} — ${pricing.yearly.price}${cur}`
    }
    if (id === 'lifetime') {
      return `${pricing.lifetime.label[lang]} — ${pricing.lifetime.price}${cur}`
    }
    return lang === 'fr' ? 'Licence' : 'License'
  }

  function open(p) {
    plan = p
    planLabel.textContent = planText(p)
    err.textContent = ''
    input.value = ''
    modal.hidden = false
    requestAnimationFrame(() => modal.classList.add('open'))
    document.body.style.overflow = 'hidden'
    setTimeout(() => input.focus(), 60)
  }

  function close() {
    modal.classList.remove('open')
    document.body.style.overflow = ''
    setTimeout(() => {
      modal.hidden = true
    }, 280)
    plan = null
  }

  document.querySelectorAll('[data-plan]').forEach((btn) => {
    btn.addEventListener('click', () => open(btn.dataset.plan))
  })

  cancel.addEventListener('click', close)
  modal.addEventListener('click', (e) => {
    if (e.target === modal) close()
  })
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modal.classList.contains('open')) close()
  })
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') ok.click()
  })

  ok.addEventListener('click', async () => {
    const deviceKey = input.value.trim().toUpperCase()
    if (!deviceKey || deviceKey.length < 6) {
      err.textContent = getLang() === 'fr' ? 'Entrez la Device Key complète.' : 'Enter the full Device Key.'
      input.focus()
      return
    }
    err.textContent = ''
    ok.disabled = true
    const label = ok.textContent
    ok.textContent = '…'

    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/create-checkout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({
          plan,
          deviceKey,
          userId: null,
          email: null,
        }),
      })
      const data = await res.json()
      if (data.error) {
        err.textContent = data.error
        ok.disabled = false
        ok.textContent = label
        return
      }
      window.location.href = data.url
    } catch {
      err.textContent = getLang() === 'fr' ? 'Erreur réseau. Réessayez.' : 'Network error. Try again.'
      ok.disabled = false
      ok.textContent = label
    }
  })
}
