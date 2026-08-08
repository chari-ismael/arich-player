import { FORMSPREE_ENDPOINT } from './config.js'
import { getLang, t } from './i18n.js'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/**
 * Contact form — posts to the same Formspree endpoint as manage-playlist support.
 */
export function initContact() {
  const form = document.getElementById('contactForm')
  if (!form) return

  const status = document.getElementById('contactStatus')
  const submit = document.getElementById('contactSubmit')
  const fields = [...form.querySelectorAll('[data-field]')]

  fields.forEach((field) => {
    const input = field.querySelector('input, textarea, select')
    if (!input) return
    const sync = () => {
      field.classList.toggle('is-filled', !!String(input.value || '').trim())
      if (input.checkValidity?.() && String(input.value || '').trim()) {
        field.classList.remove('is-error')
      }
    }
    input.addEventListener('focus', () => field.classList.add('is-focus'))
    input.addEventListener('blur', () => {
      field.classList.remove('is-focus')
      validateField(field, input, false)
      sync()
    })
    input.addEventListener('input', sync)
    sync()
  })

  form.addEventListener('submit', async (e) => {
    e.preventDefault()
    if (submit?.disabled || form.dataset.busy === '1') return

    status?.classList.remove('is-error', 'is-ok')
    if (status) status.textContent = ''

    let ok = true
    fields.forEach((field) => {
      const input = field.querySelector('input, textarea, select')
      if (!input) return
      if (!validateField(field, input, true)) ok = false
    })
    if (!ok) {
      if (status) {
        status.textContent = t('contact_err')
        status.classList.add('is-error')
      }
      form.querySelector('.contact__field.is-error input, .contact__field.is-error textarea, .contact__field.is-error select')?.focus()
      return
    }

    const name = val('contactName')
    const email = val('contactEmail')
    const topic = val('contactTopic')
    const subject = val('contactSubject')
    const message = val('contactMessage')
    const topicLabel = topicLabelOf(topic)

    setBusy(true)
    if (status) status.textContent = t('contact_loading')

    const composedSubject = `[ARICH] ${topicLabel} — ${subject}`
    const composedMessage = [
      getLang() === 'fr' ? `Nom : ${name}` : `Name: ${name}`,
      getLang() === 'fr' ? `Type : ${topicLabel}` : `Type: ${topicLabel}`,
      '',
      message,
    ].join('\n')

    try {
      const res = await fetch(FORMSPREE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          email,
          name,
          subject: composedSubject,
          message: composedMessage,
          topic: topicLabel,
          _replyto: email,
          _subject: composedSubject,
        }),
      })

      if (!res.ok) throw new Error('formspree')

      form.classList.add('is-success')
      if (status) {
        status.textContent = t('contact_ok')
        status.classList.add('is-ok')
      }
      if (submit) {
        submit.classList.add('is-success')
        const label = submit.querySelector('[data-contact-label]')
        if (label) label.textContent = t('contact_sent_label')
      }
      form.reset()
      fields.forEach((f) => f.classList.remove('is-filled', 'is-error', 'is-valid'))
      window.setTimeout(() => {
        form.classList.remove('is-success')
        if (submit) {
          submit.classList.remove('is-success')
          const label = submit.querySelector('[data-contact-label]')
          if (label) label.textContent = t('contact_send')
        }
        setBusy(false)
      }, 4200)
    } catch {
      setBusy(false)
      if (status) {
        status.textContent = t('contact_err_network')
        status.classList.add('is-error')
      }
    }
  })

  function setBusy(busy) {
    form.dataset.busy = busy ? '1' : '0'
    if (submit) {
      submit.disabled = busy
      submit.classList.toggle('is-loading', busy)
      submit.setAttribute('aria-busy', busy ? 'true' : 'false')
    }
  }
}

function val(id) {
  return /** @type {HTMLInputElement|HTMLTextAreaElement|HTMLSelectElement|null} */ (
    document.getElementById(id)
  )?.value.trim() || ''
}

function validateField(field, input, showError) {
  const raw = String(input.value || '').trim()
  const required = input.hasAttribute('required')
  let valid = true
  let msg = ''

  if (required && !raw) {
    valid = false
    msg = t('contact_err_required')
  } else if (input.type === 'email' && raw && !EMAIL_RE.test(raw)) {
    valid = false
    msg = t('contact_err_email')
  } else if (input.tagName === 'SELECT' && required && !raw) {
    valid = false
    msg = t('contact_err_topic')
  }

  field.classList.toggle('is-error', showError && !valid)
  field.classList.toggle('is-valid', !!raw && valid)
  const err = field.querySelector('.contact__err')
  if (err) err.textContent = showError && !valid ? msg : ''
  return valid
}

function topicLabelOf(value) {
  const map = {
    app: 'contact_topic_app',
    install: 'contact_topic_install',
    billing: 'contact_topic_billing',
    bug: 'contact_topic_bug',
    partner: 'contact_topic_partner',
    other: 'contact_topic_other',
  }
  return t(map[value] || 'contact_topic_other')
}
