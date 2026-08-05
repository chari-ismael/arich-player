// lib/services/device_service.dart
//
// Arich Player — Identification Hardware Virtuelle
// ─────────────────────────────────────────────────────────────────────────────
// CONTEXTE TECHNIQUE :
//   Android 6+ bloque la vraie adresse MAC hardware (retourne 02:00:00:00:00:00).
//   C'est une restriction OS permanente, identique pour DuplexPlay, TiviMate, etc.
//
// NOTRE SOLUTION (identique aux apps IPTV premium) :
//   1. Android ID (Settings.Secure.ANDROID_ID) — unique par device + compte Google
//      Stable jusqu'au factory reset. C'est le meilleur identifiant disponible.
//   2. On le hache (SHA-256) avec des infos hardware pour créer :
//      - Une "MAC Virtuelle" : XX:XX:XX:XX:XX:XX (16 chars hex formatés)
//      - Une "Device Key"    : XXXXXXXX (8 chars, identifiant court d'activation)
//   3. Ces deux identifiants sont STABLES tant que l'utilisateur ne fait pas
//      de factory reset. Même comportement que DuplexPlay.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as dev;

class DeviceIdentity {
  final String macAddress;   // Format: AB:CD:EF:12:34:56
  final String deviceKey;    // Format: A1B2C3D4 (8 chars)
  final String androidId;    // ID brut (ne jamais afficher à l'utilisateur)
  final String deviceName;   // "Samsung Galaxy S23"
  final String deviceModel;  // "SM-S918B"
  final String deviceBrand;  // "samsung"
  final String androidVersion;
  final String deviceId;     // UUID Supabase (une fois enregistré)

  const DeviceIdentity({
    required this.macAddress,
    required this.deviceKey,
    required this.androidId,
    required this.deviceName,
    required this.deviceModel,
    required this.deviceBrand,
    required this.androidVersion,
    this.deviceId = '',
  });

  Map<String, dynamic> toMap() => {
    'mac_address':     macAddress,
    'device_key':      deviceKey,
    'android_id':      androidId,
    'device_name':     deviceName,
    'device_model':    deviceModel,
    'device_brand':    deviceBrand,
    'android_version': androidVersion,
    'device_id':       deviceId,
  };

  factory DeviceIdentity.fromMap(Map map) => DeviceIdentity(
    macAddress:     map['mac_address']     ?? '',
    deviceKey:      map['device_key']      ?? '',
    androidId:      map['android_id']      ?? '',
    deviceName:     map['device_name']     ?? '',
    deviceModel:    map['device_model']    ?? '',
    deviceBrand:    map['device_brand']    ?? '',
    androidVersion: map['android_version'] ?? '',
    deviceId:       map['device_id']       ?? '',
  );

  DeviceIdentity copyWith({String? deviceId}) => DeviceIdentity(
    macAddress:     macAddress,
    deviceKey:      deviceKey,
    androidId:      androidId,
    deviceName:     deviceName,
    deviceModel:    deviceModel,
    deviceBrand:    deviceBrand,
    androidVersion: androidVersion,
    deviceId:       deviceId ?? this.deviceId,
  );
}

class DeviceService {
  static const String _hiveKey = 'device_identity';
  static DeviceIdentity? _cached;

  // ─────────────────────────────────────────────
  // POINT D'ENTRÉE PRINCIPAL
  // Appelé une fois au lancement de l'app.
  // Cache en Hive + Supabase.
  // ─────────────────────────────────────────────
  static Future<DeviceIdentity> getOrCreate() async {
    // 1. Cache mémoire
    if (_cached != null) return _cached!;

    // 2. Cache Hive (disque)
    final box = Hive.box('settings');
    final raw = box.get(_hiveKey);
    if (raw != null && raw is Map) {
      final identity = DeviceIdentity.fromMap(Map<String, dynamic>.from(raw));
      if (identity.macAddress.isNotEmpty && identity.deviceKey.isNotEmpty) {
        _cached = identity;
        dev.log('[DeviceService] Identité chargée depuis Hive: ${identity.macAddress}');
        // Mettre à jour last_seen en background
        _updateLastSeen(identity);
        return _cached!;
      }
    }

    // 3. Générer une nouvelle identité
    final identity = await _generateIdentity();

    // 4. Enregistrer sur Supabase
    final withId = await _registerOnSupabase(identity);

    // 5. Sauvegarder en Hive
    await box.put(_hiveKey, withId.toMap());
    _cached = withId;

    dev.log('[DeviceService] Nouvelle identité créée: ${withId.macAddress} / ${withId.deviceKey}');
    return _cached!;
  }

  // ─────────────────────────────────────────────
  // GÉNÉRATION DE L'IDENTITÉ
  // ─────────────────────────────────────────────
  static Future<DeviceIdentity> _generateIdentity() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    // Récupération Android ID
    // C'est le meilleur identifiant stable sur Android (équivalent à ce que
    // font DuplexPlay, TiviMate, IPTV Smarters, etc.)
    final androidId = androidInfo.id; // Settings.Secure.ANDROID_ID

    // Infos hardware pour enrichir le hash
    final model   = androidInfo.model;        // ex: "SM-S918B"
    final brand   = androidInfo.brand;        // ex: "samsung"
    final product = androidInfo.product;      // ex: "dm3qxxx"
    final board   = androidInfo.board;        // ex: "kona"

    // Nom lisible du device
    final displayName = _buildDisplayName(brand, model);

    // Version Android
    final androidVersion = androidInfo.version.release; // ex: "14"

    // ── Génération MAC Virtuelle ────────────────────────────────────────
    // Input: Android ID + model + brand + product + board
    // On concatène pour maximiser l'entropie et la stabilité
    final macInput = '$androidId|$model|$brand|$product|$board|ARICH_MAC_SALT';
    final macHash  = sha256.convert(utf8.encode(macInput)).bytes;

    // Formater en XX:XX:XX:XX:XX:XX (on prend les 6 premiers bytes du hash)
    final macAddress = _formatAsMac(macHash.sublist(0, 6));

    // ── Génération Device Key ───────────────────────────────────────────
    // Input différent (salt différent) pour avoir un résultat distinct
    final keyInput = '$androidId|$model|$board|ARICH_KEY_SALT';
    final keyHash  = sha256.convert(utf8.encode(keyInput)).toString().toUpperCase();

    // 8 premiers caractères hexadécimaux → Device Key lisible
    final deviceKey = keyHash.substring(0, 8);

    return DeviceIdentity(
      macAddress:     macAddress,
      deviceKey:      deviceKey,
      androidId:      androidId,
      deviceName:     displayName,
      deviceModel:    model,
      deviceBrand:    brand,
      androidVersion: androidVersion,
    );
  }

  // ─────────────────────────────────────────────
  // ENREGISTREMENT SUPABASE
  // ─────────────────────────────────────────────
  static Future<DeviceIdentity> _registerOnSupabase(DeviceIdentity identity) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'register_device',
        params: {
          'p_mac_address':     identity.macAddress,
          'p_device_key':      identity.deviceKey,
          'p_android_id':      identity.androidId,
          'p_device_name':     identity.deviceName,
          'p_device_model':    identity.deviceModel,
          'p_device_brand':    identity.deviceBrand,
          'p_android_version': identity.androidVersion,
          'p_app_version':     '1.0.0', // TODO: remplacer par PackageInfo
        },
      );

      if (result != null && result['device'] != null) {
        final deviceId = result['device']['id'] as String? ?? '';
        dev.log('[DeviceService] Enregistré sur Supabase: $deviceId');
        return identity.copyWith(deviceId: deviceId);
      }
    } catch (e) {
      // Pas bloquant — l'app fonctionne offline
      dev.log('[DeviceService] Erreur Supabase (non bloquant): $e');
    }
    return identity;
  }

  // ─────────────────────────────────────────────
  // MISE À JOUR LAST_SEEN (background)
  // ─────────────────────────────────────────────
  static Future<void> _updateLastSeen(DeviceIdentity identity) async {
    try {
      await Supabase.instance.client
          .from('devices')
          .update({'last_seen_at': DateTime.now().toIso8601String()})
          .eq('mac_address', identity.macAddress);
    } catch (e) {
      dev.log('[DeviceService] last_seen update failed (ignoré): $e');
    }
  }

  // ─────────────────────────────────────────────
  // RÉCUPÉRATION LICENCE
  // ─────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getLicense(DeviceIdentity identity) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_device_by_credentials',
        params: {
          'p_mac_address': identity.macAddress,
          'p_device_key':  identity.deviceKey,
        },
      );
      return result as Map<String, dynamic>?;
    } catch (e) {
      dev.log('[DeviceService] getLicense error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // UTILITAIRES
  // ─────────────────────────────────────────────

  /// Formate 6 bytes en XX:XX:XX:XX:XX:XX
  static String _formatAsMac(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// Construit un nom lisible depuis brand + model
  static String _buildDisplayName(String brand, String model) {
    final b = brand.isEmpty ? '' : '${brand[0].toUpperCase()}${brand.substring(1).toLowerCase()}';
    // Si le model contient déjà le brand, ne pas dupliquer
    if (model.toLowerCase().contains(brand.toLowerCase())) {
      return model;
    }
    return '$b $model'.trim();
  }

  /// Réinitialiser l'identité (factory reset — usage admin uniquement)
  static Future<void> clearIdentity() async {
    _cached = null;
    await Hive.box('settings').delete(_hiveKey);
    dev.log('[DeviceService] Identité effacée');
  }

  /// URL du QR Code renvoyant vers le panel web avec les credentials
  static String buildQrUrl(DeviceIdentity identity) {
    final mac = Uri.encodeComponent(identity.macAddress);
    final key = Uri.encodeComponent(identity.deviceKey);
    return 'https://arich.fr/manage-playlist.html?mac=$mac&key=$key';
  }
}