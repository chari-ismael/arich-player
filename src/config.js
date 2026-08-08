// config/site.js — contenu commercial + mapping media (un seul endroit)

export const site = {
  name: 'ARICH Player',
  slogan: {
    fr: ['Le cinéma,', 'chez vous.', 'Sans le bruit.'],
    en: ['Cinema,', 'at home.', 'Without the noise.'],
  },
  subtitle: {
    fr: 'Votre bibliothèque, vos chaînes, vos films et séries. Une expérience fluide, pensée pour vous.',
    en: 'Your library, channels, movies and series. A fluid experience, designed for you.',
  },
  email: 'contact@arich.fr',
  year: 2026,
}

export const downloadLinks = {
  apk: 'https://github.com/chari-ismael/arich-player/releases/download/v3.0.6/ArichPlayer-v3.0.6.apk',
  googlePlay: 'https://play.google.com/store/apps/details?id=com.arich.iptv',
  qrTarget: 'https://github.com/chari-ismael/arich-player/releases/latest',
}

export const pricing = {
  trialDays: 14,
  currency: '€',
  yearly: {
    id: 'yearly',
    price: 3,
    period: { fr: 'an', en: 'year' },
    label: { fr: 'Annuel', en: 'Yearly' },
  },
  lifetime: {
    id: 'lifetime',
    price: 5,
    period: { fr: 'à vie', en: 'lifetime' },
    label: { fr: 'À vie', en: 'Lifetime' },
    recommended: true,
  },
}

export const nav = [
  { href: '#top', key: 'nav_home' },
  { href: '#features', key: 'nav_features' },
  { href: '#browse', key: 'nav_browse' },
  { href: '#install', key: 'nav_install' },
  { href: '#pricing', key: 'nav_pricing' },
]

export const videos = {
  homeLand: '/media/video/home-land.mp4',
  homePort: '/media/video/home-port.mp4',
  playerLand: '/media/video/player-land.mp4',
}

/** Captures réelles — ne pas mélanger les usages */
export const media = {
  homePhone: '/media/home-phone.png',
  homeLand: '/media/home-land.png',
  filmsGrid: '/media/films-grid-phone.png',
  filmsList: '/media/films-list-phone.png',
  seriesHome: '/media/series-phone.png',
  liveLand: '/media/live-direct-land.png',
  liveDirect: '/media/live-direct-land.png',
  playlistAdd: '/media/playlist-add-phone.png',
  detail: '/media/detail-phone.png',
  download: '/media/download-phone.png',
  playerLand: '/media/player-land.png',
  playerMenu: '/media/player-menu-land.png',
  experience: '/media/experience.png',
  heroTv: '/media/hero-tv.png',
  lang: '/media/lang-phone.png',
  theme: '/media/theme-phone.png',
  login: '/media/login-phone.png',
  welcome: '/media/welcome-phone.png',
  onboard1: '/media/onboard-1.png',
  onboard2: '/media/onboard-2.png',
  onboard3: '/media/onboard-3.png',
}

/** Alias historique */
export const posters = {
  homeLand: media.homeLand,
  homePort: media.homePhone,
  player: media.playerLand,
  playerLand: media.playerLand,
  experience: media.experience,
  live: media.liveLand,
  liveLand: media.liveLand,
  browse: media.homeLand,
  series: media.seriesHome,
  heroTv: media.heroTv,
  detail: media.detail,
  films: media.filmsGrid,
  filmsList: media.filmsList,
  playlist: media.playlistAdd,
  account: media.lang,
}

export const SUPABASE_URL = 'https://aynucieohuowgkwyftiy.supabase.co'

/** Same Formspree inbox as manage-playlist support form */
export const FORMSPREE_ENDPOINT = 'https://formspree.io/f/xgolqeyj'

export const PRICING = {
  yearly: {
    id: pricing.yearly.id,
    amount: pricing.yearly.price,
    currency: pricing.currency,
    period: pricing.yearly.period,
    label: pricing.yearly.label,
  },
  lifetime: {
    id: pricing.lifetime.id,
    amount: pricing.lifetime.price,
    currency: pricing.currency,
    period: pricing.lifetime.period,
    label: pricing.lifetime.label,
    recommended: true,
  },
}

export const LINKS = {
  apk: downloadLinks.apk,
  playStore: downloadLinks.googlePlay,
  auth: '/auth.html',
  contact: `mailto:${site.email}`,
}
