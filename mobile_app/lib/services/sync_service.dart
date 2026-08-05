// lib/services/sync_service.dart
//
// Arich Player — Cloud Sync Service
//
// Synchronise favoris + historique entre Hive local et Supabase.
//
// STRATÉGIE :
//   • Déclencheur login  → full sync bidirectionnel (download + merge + upload)
//   • Déclencheur action → debounced upload (3s) pour ne pas spammer Supabase
//   • Merge favoris      → union locale + distante, local prioritaire
//   • Merge historique   → garde watchedAt le plus récent par (streamId, tabIndex)
//
// USAGE :
//   // Dans IptvProvider.login() :
//   SyncService.init(getFavorites: ..., setFavorites: ..., ...);
//
//   // Après ajout favori / fermeture player :
//   SyncService.scheduleUpload();
//
//   // Au logout :
//   SyncService.dispose();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class SyncService {
  SyncService._();

  // Callbacks injectés depuis IptvProvider (évite circular import)
  static List<Map<String, dynamic>> Function()? _getFavorites;
  static List<Map<String, dynamic>> Function()? _getHistory;
  static Future<void> Function(List<Map<String, dynamic>>)? _setFavorites;
  static Future<void> Function(List<Map<String, dynamic>>)? _setHistory;

  static StreamSubscription<AuthState>? _authSub;
  static Timer? _debounce;

  // ── Init ──────────────────────────────────────────────────────────────────

  static void init({
    required List<Map<String, dynamic>> Function()    getFavorites,
    required List<Map<String, dynamic>> Function()    getHistory,
    required Future<void> Function(List<Map<String, dynamic>>) setFavorites,
    required Future<void> Function(List<Map<String, dynamic>>) setHistory,
  }) {
    _getFavorites = getFavorites;
    _getHistory   = getHistory;
    _setFavorites = setFavorites;
    _setHistory   = setHistory;

    // Écoute les changements d'auth pour déclencher une sync
    _authSub?.cancel();
    _authSub = SupabaseService.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        debugPrint('[Sync] SignedIn → full sync');
        Future.delayed(const Duration(milliseconds: 500), _fullSync);
      }
    });

    // Déjà connecté au démarrage → sync différée
    if (SupabaseService.isSignedIn) {
      Future.delayed(const Duration(seconds: 2), _fullSync);
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  static void dispose() {
    _authSub?.cancel();
    _authSub   = null;
    _debounce?.cancel();
    _debounce  = null;
    _getFavorites = _getHistory = null;
    _setFavorites = _setHistory = null;
  }

  // ── Upload différé (3s debounce) ──────────────────────────────────────────
  // Appeler après chaque modification locale (ajout favori, fin de lecture…)

  static void scheduleUpload() {
    if (!SupabaseService.isSignedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () async {
      if (_getFavorites != null) {
        await SupabaseService.uploadFavorites(_getFavorites!());
      }
      if (_getHistory != null) {
        await SupabaseService.uploadHistory(_getHistory!());
      }
      debugPrint('[Sync] Upload différé terminé');
    });
  }

  // ── Sync complète bidirectionnelle ────────────────────────────────────────

  static Future<void> _fullSync() async {
    if (!SupabaseService.isSignedIn) return;
    await Future.wait([_syncFavorites(), _syncHistory()]);
  }

  // ── Favoris : merge local + remote, local prioritaire ────────────────────

  static Future<void> _syncFavorites() async {
    if (_getFavorites == null || _setFavorites == null) return;
    try {
      final local  = _getFavorites!();
      final remote = await SupabaseService.downloadFavorites();

      final merged = <String, Map<String, dynamic>>{};
      // Remote en premier, local override ensuite
      for (final f in [...remote, ...local]) {
        merged['${f['streamId']}_${f['tabIndex']}'] = f;
      }

      final list = merged.values.toList()
        ..sort((a, b) => (b['addedAt'] as int? ?? 0)
            .compareTo(a['addedAt'] as int? ?? 0));

      await _setFavorites!(list);
      await SupabaseService.uploadFavorites(list);
      debugPrint('[Sync] Favoris OK (${list.length})');
    } catch (e) {
      debugPrint('[Sync] _syncFavorites: $e');
    }
  }

  // ── Historique : merge, garde le watchedAt le plus récent ────────────────

  static Future<void> _syncHistory() async {
    if (_getHistory == null || _setHistory == null) return;
    try {
      final local  = _getHistory!();
      final remote = await SupabaseService.downloadHistory();

      final merged = <String, Map<String, dynamic>>{};
      for (final h in [...remote, ...local]) {
        final key = '${h['streamId']}_${h['tabIndex']}';
        final existing = merged[key];
        if (existing == null ||
            (h['watchedAt'] as int? ?? 0) >
                (existing['watchedAt'] as int? ?? 0)) {
          merged[key] = h;
        }
      }

      final list = merged.values.toList()
        ..sort((a, b) => (b['watchedAt'] as int? ?? 0)
            .compareTo(a['watchedAt'] as int? ?? 0));

      await _setHistory!(list);
      await SupabaseService.uploadHistory(list);
      debugPrint('[Sync] Historique OK (${list.length})');
    } catch (e) {
      debugPrint('[Sync] _syncHistory: $e');
    }
  }
}