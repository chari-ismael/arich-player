/**
 * FAQ categories + accessible one-open accordion.
 */
export function initFaq() {
  const root = document.getElementById('faq')
  const list = document.getElementById('faqList')
  const tabs = document.getElementById('faqTabs')
  if (!root || !list) return

  const items = [...list.querySelectorAll('.faq__item')]

  items.forEach((item) => {
    item.addEventListener('toggle', () => {
      if (!item.open) return
      items.forEach((other) => {
        if (other !== item) other.open = false
      })
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
        if (!match) item.open = false
      })
    })
  })
}
