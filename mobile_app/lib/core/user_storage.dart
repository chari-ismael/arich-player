// lib/core/user_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as dev;

class UserStorage {
  UserStorage._();

  static Box? _userBox;
  static String? _currentKey;

  // ── Ouverture de la box pour un compte ────────────────────────────────────

  /// Ouvre la box du compte et la met en cache.
  /// [accountKey] : identifiant unique du compte (ex: "xtream_monlogin_hash")
  static Future<void> openForAccount(String accountKey) async {
    if (_currentKey == accountKey && _userBox != null && _userBox!.isOpen) return;
    await _closeCurrentBox();
    final safeName = _sanitizeBoxName(accountKey);
    _userBox = await Hive.openBox('user_$safeName');
    _currentKey = accountKey;
    dev.log('[UserStorage] Opened box for account: $safeName');
  }

  /// Ferme la box courante (à appeler au logout)
  static Future<void> closeCurrentBox() async {
    await _closeCurrentBox();
  }

  static Future<void> _closeCurrentBox() async {
    if (_userBox != null && _userBox!.isOpen) {
      await _userBox!.close();
    }
    _userBox = null;
    _currentKey = null;
  }

  // ── Accès aux données ─────────────────────────────────────────────────────

  static Box? get box => (_userBox != null && _userBox!.isOpen) ? _userBox : null;

  static T get<T>(String key, {required T defaultValue}) {
    final b = box;
    if (b == null) return defaultValue;
    try {
      return b.get(key, defaultValue: defaultValue) as T;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<void> put(String key, dynamic value) async {
    final b = box;
    if (b == null) {
      dev.log('[UserStorage] WARNING: put() called but no box open (key: $key)');
      return;
    }
    await b.put(key, value);
  }

  static Future<void> delete(String key) async {
    await box?.delete(key);
  }

  static Future<void> deleteAll(List<String> keys) async {
    await box?.deleteAll(keys);
  }

  /// Supprime complètement les données d'un compte (ex: bouton "Supprimer le compte")
  static Future<void> deleteAccountData(String accountKey) async {
    final safeName = _sanitizeBoxName(accountKey);
    final boxName = 'user_$safeName';
    try {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).clear();
        await Hive.box(boxName).close();
      } else {
        final b = await Hive.openBox(boxName);
        await b.clear();
        await b.close();
      }
      await Hive.deleteBoxFromDisk(boxName);
      dev.log('[UserStorage] Deleted account data: $safeName');
    } catch (e) {
      dev.log('[UserStorage] Error deleting account data: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Génère une clé propre pour le nom de box Hive (alphanum + underscore seulement)
  static String _sanitizeBoxName(String key) {
    final s = key
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    // Ne jamais utiliser key.length ici : replaceAll peut raccourcir la chaîne → RangeError.
    if (s.length <= 40) return s;
    return s.substring(0, 40);
  }

  /// Génère la clé de compte depuis les credentials
  static String accountKey({
    required String sourceType, // 'xtream' | 'm3u'
    required String identifier, // username pour xtream, url hashée pour m3u
    String serverHost = '',
  }) {
    // On prend les 8 premiers chars du host pour différencier serveurs
    String hostPart = '';
    if (serverHost.isNotEmpty) {
      final h = serverHost.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (h.isNotEmpty) {
        final n = h.length < 8 ? h.length : 8;
        hostPart = h.substring(0, n);
      }
    }
    String identPart = '';
    final id = identifier.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (id.isNotEmpty) {
      final n = id.length < 20 ? id.length : 20;
      identPart = id.substring(0, n);
    }
    return '${sourceType}_${hostPart}_$identPart';
  }
}