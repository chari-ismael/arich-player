// lib/providers/license_provider.dart
//
// Arich Player — License Provider v3.0
//
// Adapté au schéma Supabase existant :
//   Table licenses : id, device_id, status, plan_name, plan_type,
//                    expires_at, starts_at, is_active (absent → déduit de status)
//   Table app_config : key, value
//
// Colonnes réelles utilisées :
//   device_id  → UUID de l'appareil (correspond à DeviceService.deviceId)
//   status     → 'trial' | 'active' | 'expired' | 'suspended' | 'banned'
//   plan_type  → 'trial_7' | 'beta' | 'pro' | 'lifetime'
//   plan_name  → label affiché
//   expires_at → date d'expiration (NULL = lifetime)
//
// ENFORCEMENT SERVEUR :
//   app_config WHERE key = 'license_enforcement' → 'true'/'false'
//   false (défaut) = tout le monde passe, peu importe la licence
//   true           = les licences expirées/suspendues sont bloquées
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/device_service.dart';

const _kLicenseCacheKey     = 'license_cache_v3';
const _kEnforcementCacheKey = 'license_enforcement_v3';
const _kCheckedAtKey        = 'license_checked_at_v3';
const _kCacheDuration       = Duration(hours: 24);

// ── Modèle ────────────────────────────────────────────────────────────────────

class LicenseInfo {
  final String    status;    // trial | active | expired | suspended | banned
  final String    planType;  // trial_7 | beta | pro | lifetime
  final String    planName;
  final DateTime? expiresAt;
  final String    deviceId;

  const LicenseInfo({
    required this.status,
    required this.planType,
    required this.planName,
    this.expiresAt,
    required this.deviceId,
  });

  bool get isLifetime  => planType == 'lifetime';
  bool get isTrial     => planType == 'trial_7' || planType == 'trial';
  bool get isBeta      => planType == 'beta';
  bool get isActive    => status == 'active' || status == 'trial';
  bool get isSuspended => status == 'suspended' || status == 'banned';
  bool get isExpired   => status == 'expired' ||
      (!isLifetime && expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  bool get isIntrinsicallyValid => isActive && !isExpired;

  int? get daysLeft {
    if (isLifetime) return null;
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.inDays.clamp(0, 9999);
  }

  String get planLabel => switch (planType) {
    'lifetime' => 'Lifetime',
    'pro'      => 'Pro',
    'beta'     => 'Bêta Testeur',
    _          => planName.isNotEmpty ? planName : 'Essai gratuit',
  };

  String get statusLabel {
    if (isSuspended) return 'Suspendu';
    if (isExpired)   return 'Expiré';
    if (isLifetime)  return 'Actif — Illimité';
    final d = daysLeft;
    if (d == null) return 'Actif';
    if (d == 0)    return 'Expire aujourd\'hui';
    return 'Actif — $d jour${d > 1 ? 's' : ''} restant${d > 1 ? 's' : ''}';
  }

  Map<String, dynamic> toMap() => {
    'status':    status,
    'planType':  planType,
    'planName':  planName,
    'expiresAt': expiresAt?.toIso8601String(),
    'deviceId':  deviceId,
  };

  factory LicenseInfo.fromMap(Map m) {
    final expiresStr = m['expiresAt'] as String?;
    return LicenseInfo(
      status:    m['status']   as String? ?? 'trial',
      planType:  m['planType'] as String? ?? 'trial_7',
      planName:  m['planName'] as String? ?? 'Essai gratuit',
      expiresAt: expiresStr != null ? DateTime.tryParse(expiresStr) : null,
      deviceId:  m['deviceId'] as String? ?? '',
    );
  }

  // Construit depuis une row Supabase (schéma réel)
  factory LicenseInfo.fromRow(Map row, String deviceId) {
    final expiresStr = row['expires_at'] as String?;
    return LicenseInfo(
      status:    row['status']    as String? ?? 'trial',
      planType:  row['plan_type'] as String? ?? 'trial_7',
      planName:  row['plan_name'] as String? ?? 'Essai gratuit',
      expiresAt: expiresStr != null ? DateTime.tryParse(expiresStr) : null,
      deviceId:  deviceId,
    );
  }

  factory LicenseInfo.failOpen(String deviceId) => LicenseInfo(
    status:    'trial',
    planType:  'trial_7',
    planName:  'Essai gratuit',
    expiresAt: DateTime.now().add(const Duration(days: 1)),
    deviceId:  deviceId,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class LicenseProvider extends ChangeNotifier {
  LicenseInfo? _license;
  bool         _enforcementActive = false;
  bool         _isChecking        = false;
  String?      _errorMsg;
  Timer?       _recheckTimer;

  LicenseInfo? get license           => _license;
  bool         get isChecking        => _isChecking;
  bool         get enforcementActive => _enforcementActive;
  String?      get errorMsg          => _errorMsg;

  bool get isValid {
    if (!_enforcementActive) return true;
    return _license?.isIntrinsicallyValid ?? true;
  }

  bool get isSuspended =>
      _enforcementActive && (_license?.isSuspended ?? false);

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _loadFromCache();
    await check();
    _scheduleRecheck();
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  void _loadFromCache() {
    try {
      final box = Hive.box('settings');
      final enfRaw = box.get(_kEnforcementCacheKey);
      if (enfRaw is bool) _enforcementActive = enfRaw;

      final licRaw    = box.get(_kLicenseCacheKey);
      final checkedAt = box.get(_kCheckedAtKey) as String?;
      if (licRaw == null) return;

      _license = LicenseInfo.fromMap(Map<dynamic, dynamic>.from(licRaw as Map));
      final checked = checkedAt != null ? DateTime.tryParse(checkedAt) : null;
      final fresh   = checked != null &&
          DateTime.now().difference(checked) < _kCacheDuration;
      if (fresh) notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveToCache(LicenseInfo info, bool enforcement) async {
    try {
      final box = Hive.box('settings');
      await box.put(_kLicenseCacheKey,     info.toMap());
      await box.put(_kEnforcementCacheKey, enforcement);
      await box.put(_kCheckedAtKey,        DateTime.now().toIso8601String());
    } catch (_) {}
  }

  // ── Check Supabase ────────────────────────────────────────────────────────

  Future<bool> check() async {
    if (_isChecking) return isValid;
    _isChecking = true;
    _errorMsg   = null;
    notifyListeners();

    try {
      final db       = Supabase.instance.client;
      final identity = await DeviceService.getOrCreate();

      // ── 1. Lire enforcement ───────────────────────────────────────────
      bool enforcement = false;
      try {
        final cfg = await db
            .from('app_config')
            .select('value')
            .eq('key', 'license_enforcement')
            .maybeSingle();
        enforcement = (cfg?['value'] as String?)?.toLowerCase() == 'true';
      } catch (_) {
        enforcement = false;
      }
      _enforcementActive = enforcement;

      // ── 2. Chercher la licence par device_id ──────────────────────────
      // Le schéma existant utilise device_id (UUID Supabase de l'appareil)
      Map<String, dynamic>? row;

      if (identity.deviceId.isNotEmpty) {
        row = await db
            .from('licenses')
            .select()
            .eq('device_id', identity.deviceId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      if (row == null) {
        // Aucune licence → fail-open (trial créé automatiquement par l'ancien système)
        _license = LicenseInfo.failOpen(identity.deviceId);
        await _saveToCache(_license!, enforcement);
        notifyListeners();
        return true;
      }

      _license = LicenseInfo.fromRow(row, identity.deviceId);
      await _saveToCache(_license!, enforcement);
      notifyListeners();
      return isValid;

    } catch (e) {
      debugPrint('[License] check error: $e');
      _errorMsg = e.toString();
      if (_license == null) {
        _license = LicenseInfo.failOpen('unknown');
      }
      notifyListeners();
      return true; // fail-open
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  // ── Recheck ───────────────────────────────────────────────────────────────

  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(_kCacheDuration, (_) => check());
  }

  Future<void> forceRefresh() async {
    try {
      await Hive.box('settings').delete(_kCheckedAtKey);
    } catch (_) {}
    await check();
  }

  @override
  void dispose() {
    _recheckTimer?.cancel();
    super.dispose();
  }
}