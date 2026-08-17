# 📺 ARICH Player

> Lecteur IPTV premium français — Android · Android TV · Samsung Tizen · Design AAA · Fluide & moderne

![Flutter](https://img.shields.io/badge/Flutter-3.41.3-02569B?style=flat-square&logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.11.1-0175C2?style=flat-square&logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Android%20TV%20%7C%20Tizen-3DDC84?style=flat-square&logo=android)
![Version](https://img.shields.io/badge/Version-2.1.0-7C5CFC?style=flat-square)
![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)

---

## ✨ Présentation

**ARICH Player** est une application multi-plateforme premium pour la lecture de contenus IPTV via :
- 🔗 **Xtream Codes** — authentification serveur URL / identifiants
- 📄 **Playlists M3U** — import local ou distant

L'application **ne fournit aucun contenu**. Elle se connecte aux serveurs IPTV de l'utilisateur.

Direction artistique : fond `#0A0A0F` OLED profond, accents violet `#7C5CFC` / bleu `#3D8EFF`, glassmorphism, animations fluides. Le niveau d'exigence visuel vise Netflix / Apple TV+.

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── theme.dart              # Design tokens, couleurs, gradients
│   ├── tv_layout.dart          # TVSizes, TVDetector, extensions context
│   ├── tv_navigation.dart      # TvBackHandler, FocusableNavTab
│   ├── l10n.dart               # Localisation FR/EN/AR
│   ├── country_utils.dart      # Détection pays depuis nom catégorie
│   └── user_storage.dart       # Hive par compte utilisateur
├── models/
│   ├── category.dart
│   ├── channel.dart
│   └── playlist_account.dart
├── providers/
│   ├── iptv_provider.dart      # État global IPTV — chaînes, catégories, favoris, historique
│   ├── playlist_provider.dart  # Gestion multi-playlists + sync Supabase
│   ├── language_provider.dart
│   ├── theme_provider.dart
│   └── mini_player_provider.dart
├── services/
│   ├── m3u_parser.dart         # Parser M3U optimisé
│   ├── xtream_api.dart         # Client API Xtream Codes
│   ├── tmdb_service.dart       # Métadonnées films/séries
│   ├── sync_service.dart       # Cloud sync favoris/historique via Supabase
│   ├── dead_stream_checker.dart# Vérification santé des streams favoris
│   ├── device_service.dart
│   ├── media_kit_player.dart   # Wrapper IVideoPlayer → media_kit
│   ├── tizen_video_player.dart # Wrapper IVideoPlayer → Tizen
│   └── video_player_service.dart # Interface IVideoPlayer
├── ui/
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── auth_screen.dart
│   │   ├── onboarding_screen.dart
│   │   ├── home_screen.dart
│   │   ├── category_grid_screen.dart
│   │   ├── details_screen.dart
│   │   ├── player_screen.dart
│   │   ├── epg_screen.dart
│   │   ├── favorites_screen.dart
│   │   ├── profile_screen.dart
│   │   ├── stats_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── login_screen.dart   # Conservé pour usage futur
│   │   └── license_screen.dart # Conservé pour usage futur
│   └── widgets/
│       ├── channel_card.dart
│       ├── mini_player_bar.dart
│       ├── focusable_ink.dart
│       └── parental_gate.dart
└── main.dart
```

---

## 🛠️ Stack technique

| Technologie | Usage |
|---|---|
| **Flutter 3.41.3 / Dart 3.11.1** | Framework UI principal |
| **Provider** | Gestion d'état (ChangeNotifier + Selector) |
| **Hive Flutter** | Persistance locale (favoris, historique, préférences) |
| **Supabase Flutter** | Auth, cloud sync favoris/historique |
| **media_kit 1.2.6** | Lecteur vidéo Android (hardware decode H264/HEVC/VP9/AV1) |
| **cached_network_image** | Images réseau avec cache — jamais `Image.network` |
| **google_fonts** | Rajdhani (titres) + Inter (body) |
| **flutter_animate** | Animations déclaratives, shimmer skeletons |
| **app_links** | Deep links OAuth (com.arich.iptv://auth-callback) |
| **http** | Requêtes API Xtream + keep-alive |
| **permission_handler** | Permissions Android (notifications) |
| **url_launcher** | Liens externes |
| **wakelock_plus** | Maintien écran allumé pendant lecture |
| **crypto** | Hash SHA-256 PIN parental |

---

## 🎯 Plateformes

| Plateforme | Statut | Notes |
|---|---|---|
| **Android Phone** | ✅ Production | Portrait + Paysage |
| **Android TV** | ✅ Production | Navigation D-pad, sidebar TV |
| **Samsung Tizen** | ✅ Production | UA50MU6125, bypass BackdropFilter |

---

## ⚠️ Règles de code absolues

### Navigation
```dart
// ❌ INTERDIT — flash blanc
MaterialPageRoute(builder: (_) => Screen())

// ✅ OBLIGATOIRE
PageRouteBuilder(
  pageBuilder: (_, a, __) => Screen(),
  transitionsBuilder: (_, a, __, child) =>
      FadeTransition(opacity: a, child: child),
)
```

### Images réseau
```dart
// ❌ INTERDIT
Image.network(url)

// ✅ OBLIGATOIRE
CachedNetworkImage(imageUrl: url, memCacheWidth: 220, memCacheHeight: 220)
```

### Layout
```dart
// ✅ Stack → SizedBox.expand sur TOUS les children
// ✅ Sidebar : SizedBox(width: X, child: DecoratedBox(...)) + Row(crossAxisAlignment: CrossAxisAlignment.stretch)
// ✅ Column dans SingleChildScrollView : mainAxisSize: MainAxisSize.min
```

### Performance
```dart
// ✅ isFavorite() → O(1) via Set<String> _favoriteKeys
// ✅ GridView/ListView → cacheExtent: MediaQuery.sizeOf(context).height * 3
// ✅ Regex/calculs dans build() → cacher dans state (initState/didUpdateWidget)
// ✅ context.watch dans build() lourd → Selector ou context.read
// ✅ Badges animés en boucle → singleton ticker global (_LiveDotTicker)
```

### Stabilité
```dart
// ✅ IptvProvider : _disposed flag + void _notify() wrapper
// ✅ _prefetchInBackground : _isPrefetching lock + check _disposed après await
// ✅ loadTabContent : _isLoadingTab lock + _pendingTab pour files d'attente
// ✅ Navigation post-async : toujours if (!mounted) return
// ✅ StreamSubscription : toujours cancel() dans dispose()
```

### Tizen
```dart
// ✅ Bypass BackdropFilter sur Tizen (non supporté)
final isTizen = Platform.operatingSystem == 'tizen';
if (!isTizen) ClipOval(child: BackdropFilter(..., child: inner))
else inner
```

---

## 🎨 Design tokens

```dart
// Backgrounds
bg        = 0xFF0A0A0F    surface = 0xFF13131A
card      = 0xFF1C1C26    border  = 0xFF2A2A3A

// Accents
violet    = 0xFF7C5CFC    blue    = 0xFF3D8EFF
cyan      = 0xFF00B4D8    gold    = 0xFFF59E0B
green     = 0xFF22C55E    red     = 0xFFEF4444
orange    = 0xFFFF9F43

// Texte
textPri   = 0xFFF5F5F7    textSec = 0xFF8E8EA0
textMut   = 0xFF52526A

// Fonts
titres    → GoogleFonts.rajdhani()
body      → GoogleFonts.inter()
```

### Composants design system
- **Section headers** : bar gauche 3px gradient + glow + icône pill gradient
- **Primary buttons** : `gradientHorizontal` + double `boxShadow`
- **Cards** : gradient dark `11101C→0D0C17` + border gauche 3px gradient
- **Glassmorphism** : `ClipOval/ClipRRect + BackdropFilter blur(12)` + bypass Tizen
- **Séparateurs** : toujours gradient (`transparent→violet→transparent`)
- **Skeletons** : `flutter_animate` shimmer + `repeat(reverse: true)`

---

## 🚀 Fonctionnalités

### Lecture
- [x] Lecteur vidéo full-screen hardware-accelerated
- [x] Navigation chaîne précédente/suivante (flèches ◀▶ + swipe vertical + D-pad TV)
- [x] Preview chaîne cible (logo + nom) sous chaque flèche
- [x] Sleep timer (15 / 30 / 60 / 90 / 120 min)
- [x] Speed boost (maintien long pour ×2)
- [x] Seek par double-tap ou swipe horizontal
- [x] Volume / luminosité par swipe vertical
- [x] Picture-in-Picture (Android 8+, auto sur Home)
- [x] EPG en cours + suivant
- [x] Watchdog de stagnation + reconnexion silencieuse
- [x] Keep-alive toutes les 4 minutes

### Contenu
- [x] Live TV, Films, Séries (Xtream Codes + M3U)
- [x] Catégories avec sidebar (landscape/TV) ou grille portrait
- [x] Réorganisation drag & drop des catégories
- [x] Filtre par catégorie + recherche
- [x] Recherche globale multi-onglets
- [x] Guide TV (EPG hebdomadaire)
- [x] Détails films/séries (TMDB)

### Compte & sync
- [x] Auth Supabase (email/password + OAuth Google)
- [x] Onboarding guidé 3 étapes
- [x] Cloud sync favoris + historique (debounce + merge bidirectionnel)
- [x] Multi-playlists (Xtream + M3U)
- [x] Historique de lecture avec reprise de position
- [x] Favoris + dead stream checker (HTTP HEAD en arrière-plan)

### TV & accessibilité
- [x] Navigation D-pad complète (Android TV + Tizen)
- [x] Sidebar fixe paysage/TV
- [x] Mini player persistant
- [x] Contrôle parental PIN SHA-256
- [x] Tri A→Z / Z→A
- [x] Masquage catégories / onglets

---

## 📦 Installation

```bash
git clone <repo>
cd arich_iptv
flutter pub get
flutter run
```

> Requis : Flutter 3.41.3+, Android SDK 21+, Dart 3.11.1+

---

## 🗂️ Versions des écrans principaux

| Fichier | Version |
|---|---|
| `main.dart` | v7.1 |
| `iptv_provider.dart` | v4.2 |
| `home_screen.dart` | v17 |
| `category_grid_screen.dart` | v9 |
| `player_screen.dart` | v10.1 |
| `details_screen.dart` | v3 |
| `settings_screen.dart` | v16 |
| `channel_card.dart` | v3 |
| `MainActivity.kt` | PiP + Volume + Brightness |

---

## 🔒 Licence

Propriétaire — Tous droits réservés © ARICH Player
