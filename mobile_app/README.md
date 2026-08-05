# ARICH Player — Application mobile Flutter

Code source reconstitué et maintenu dans `mobile_app/`.

## Télécharger l'APK

- **v2.2.0** : [releases/app-release-v2.2.0.apk](../releases/app-release-v2.2.0.apk)
- Ou via [GitHub Releases](https://github.com/chari-ismael/arich-player/releases)

## Build local

```bash
cd mobile_app
flutter pub get
flutter build apk --release
```

L'APK se trouve dans `mobile_app/build/app/outputs/flutter-apk/app-release.apk`.

## Changements v2.2.0

- Accueil : bottom nav (Accueil / Direct / Films / Séries / Plus), section « Ce soir », masquage des rangées vides
- Images hero plus nettes (cache haute résolution)
- Paramètres mobile : pills horizontales (fini le drawer latéral)
- Menu Plus : sheet glassmorphism sans overflow
- Lecteur : menu ⋮ compact (PiP, lock, multi-écrans, réglages)
- Mise à jour obligatoire via `app_config` Supabase (`min_version`, `force_update`)
