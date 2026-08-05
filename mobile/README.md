# ARICH Player — Application mobile Flutter

Ce dossier contient le code source Flutter récupéré depuis l'APK v3.0.0 et amélioré.

## Build APK (sur votre PC)

```bash
cd mobile
flutter pub get
flutter build apk --release
```

L'APK sera dans `build/app/outputs/flutter-apk/app-release.apk`.

## APK actuel (release GitHub)

https://github.com/chari-ismael/arich-player/releases/download/V_3.0.0/app-release.apk

## Changements récents (cette branche)

- Accueil : barre basse portrait, section « Ce soir », masquage des squelettes VOD vides
- Paramètres : refonte mobile épurée (pills, sans drawer)
- Menu Plus : sheet glassmorphism sans overflow
- Lecteur : options regroupées, sheet basse au lieu du panneau latéral
- Monétisation : service de mise à jour forcée + bypass dev via Supabase `app_config`

## Admin Supabase

Panneau admin → Configuration : `min_version`, `force_update`, `dev_bypass_enabled`, etc.
