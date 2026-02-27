# 📺 Arich IPTV

> Lecteur IPTV premium français — Android · Design-first · Fluide & moderne

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android)
![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)

---

## ✨ Présentation

**Arich IPTV** est une application Android premium pour la lecture de contenus IPTV via :
- 🔗 **Xtream Codes** — authentification serveur URL / identifiants
- 📄 **Playlists M3U** — import local ou distant

L'application **ne fournit aucun contenu**. Elle se connecte aux serveurs IPTV de l'utilisateur.

Direction artistique : noir OLED profond, ambiance cinéma, interface minimaliste et impactante. Le niveau d'exigence visuel vise Netflix / Apple TV+.

---

## 🏗️ Architecture

```
lib/
├── core/
│   └── theme.dart              # Thème global, couleurs, typographie
├── models/
│   ├── category.dart
│   ├── channel.dart
│   └── playlist_account.dart
├── providers/
│   ├── iptv_provider.dart      # État global IPTV (chaînes, catégories)
│   └── playlist_provider.dart  # Gestion multi-playlists
├── services/
│   ├── m3u_parser.dart         # Parser M3U optimisé
│   └── xtream_api.dart         # Client API Xtream Codes
├── ui/
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── auth_screen.dart    # Login / Register animé
│   │   ├── login_screen.dart
│   │   ├── home_screen.dart
│   │   ├── details_screen.dart
│   │   ├── player_screen.dart
│   │   └── settings_screen.dart
│   └── widgets/
│       ├── channel_card.dart
│       ├── tv_focusable.dart
│       └── theme.dart
└── main.dart
```

---

## 🛠️ Stack technique

| Technologie | Usage |
|---|---|
| **Flutter** | Framework UI principal |
| **Provider** | Gestion d'état (ChangeNotifier) |
| **Hive** | Persistance locale (favoris, historique, comptes) |
| **media_kit `1.1.11`** | Lecteur vidéo (contrainte de version critique) |
| **google_fonts** | Typographie Poppins |
| **flutter_animate** | Animations déclaratives |
| **http** | Requêtes API Xtream |
| **permission_handler** | Permissions Android |
| **url_launcher** | Liens externes |

---

## ⚠️ Contraintes critiques

### media_kit 1.1.11

La classe `Player` dans cette version :

```dart
// ❌ INTERDIT — méthode inexistante dans cette version
_player.setProperty('key', 'value');

// ✅ CORRECT — options passées uniquement au constructeur
final player = Player(
  configuration: PlayerConfiguration(
    // options ici
  ),
);
```

### Bonnes pratiques Flutter obligatoires

- Pas de strings multiline avec vrais sauts de ligne → toujours `\n`
- Toujours vérifier `if (context.mounted)` dans les callbacks async
- Toujours vérifier l'ouverture des Hive boxes avant accès
- Attention aux doubles appels de chargement (lazy loading fragile)

---

## 🚀 Fonctionnalités

- [x] Authentification Xtream Codes
- [x] Import playlists M3U (local & URL)
- [x] Multi-playlists simultanées
- [x] Lazy loading optimisé des chaînes
- [x] Lecteur vidéo avec buffer réduit
- [x] Historique de lecture persistant
- [x] Favoris persistants
- [x] Paramètres complets
- [x] Splash screen animé
- [x] Auth screen avec animations (login / register)
- [x] Device Key générée localement
- [ ] Backend / compte utilisateur (non prioritaire)

---

## 🎨 Direction artistique

| Élément | Valeur |
|---|---|
| **Background** | Noir OLED `#000000` / `#0A0A0A` |
| **Accent** | Rouge → gradient violet-rouge |
| **Typographie** | Poppins (Google Fonts) |
| **Ambiance** | Cinéma / streaming premium |
| **Inspiration** | Netflix, Apple TV+, TiviMate |

> ⚠️ Avant toute modification majeure de direction artistique, toujours valider avec l'équipe.

---

## 📦 Installation

```bash
# Cloner le projet
git clone <repo>
cd arich_iptv

# Installer les dépendances
flutter pub get

# Lancer sur Android
flutter run
```

> Requis : Flutter SDK 3.x, Android SDK 21+

---

## 📁 Assets

Les assets (icônes, images, fonts) sont organisés dans le dossier `assets/`. Déclarés dans `pubspec.yaml`.

---

## 🔒 Licence

Propriétaire — Tous droits réservés © Arich IPTV
