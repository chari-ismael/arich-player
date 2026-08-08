/**
 * FAQ categories + smooth one-open accordion (class-driven, not native open jump).
 */
export function initFaq() {
  const root = document.getElementById('faq')
  const list = document.getElementById('faqList')
  const tabs = document.getElementById('faqTabs')
  if (!root || !list) return

  const items = [...list.querySelectorAll('.faq__item')]

  const setOpen = (item, open) => {
    item.classList.toggle('is-open', open)
    if (open) item.setAttribute('open', '')
    else item.removeAttribute('open')
    const summary = item.querySelector('summary')
    summary?.setAttribute('aria-expanded', open ? 'true' : 'false')
  }

  items.forEach((item) => {
    const summary = item.querySelector('summary')
    if (!summary) return
    summary.setAttribute('aria-expanded', item.classList.contains('is-open') ? 'true' : 'false')

    summary.addEventListener('click', (e) => {
      e.preventDefault()
      const willOpen = !item.classList.contains('is-open')
      items.forEach((other) => {
        if (other !== item) setOpen(other, false)
      })
      setOpen(item, willOpen)
    })
  })

  tabs?.querySelectorAll('button[data-faq-cat]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const cat = btn.getAttribute('data-faq-cat') || 'all'
      tabs.querySelectorAll('button').forEach((b) => {
        const on = b === btn
        b.classList.toggle('is-active', on)
        b.setAttribute('aria-selected', on ? 'true' : 'false')
      })
      items.forEach((item) => {
        const match = cat === 'all' || item.dataset.cat === cat
        item.hidden = !match
        if (!match) setOpen(item, false)
      })
    })
  })
}
