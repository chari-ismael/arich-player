// lib/services/supabase_service.dart
//
// Arich Player — Supabase Service
// • Auth : signIn / signUp / signOut / currentUser / authStateChanges
// • checkAndRegisterDevice : enregistrement appareil + licence trial
// • fetchWebPlaylists      : playlists du compte (user_id) ou appareil (device_key)
// • subscribeToPlaylists   : realtime sync
// • pushPlaylist           : app → Supabase
// • deletePlaylist         : suppression bidirectionnelle
// • pingDevice             : mise à jour last_seen
// • getLicenseInfo         : infos licence pour LicenseScreen
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/device_service.dart';

class SupabaseService {
  static SupabaseClient get _db => Supabase.instance.client;
  static User?          get currentUser => _db.auth.currentUser;
  static bool           get isSignedIn  => _db.auth.currentUser != null;

  // ── Auth state stream ─────────────────────────────────────────────────────
  //
  // Écouter pour déclencher une sync quand l'utilisateur se connecte/déconnecte.

  static Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;

  // ── Connexion email/password ──────────────────────────────────────────────

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _db.auth.signInWithPassword(email: email, password: password);
  }

  // ── Inscription email/password ────────────────────────────────────────────

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return _db.auth.signUp(email: email, password: password);
  }

  // ── Déconnexion ───────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  // ── Reset mot de passe ────────────────────────────────────────────────────

  static Future<void> resetPassword(String email) async {
    await _db.auth.resetPasswordForEmail(
      email,
      redirectTo: 'https://arich.fr/auth.html',
    );
  }

  // ── Enregistrement appareil ───────────────────────────────────────────────

  static Future<bool> checkAndRegisterDevice() async {
    try {
      final identity = await DeviceService.getOrCreate();
      final user = currentUser;

      final deviceRow = <String, dynamic>{
        'device_key':      identity.deviceKey,
        'mac_address':     identity.macAddress,
        'device_name':     identity.deviceName,
        'device_model':    identity.deviceModel,
        'device_brand':    identity.deviceBrand,
        'android_version': identity.androidVersion,
        'last_seen_at':    DateTime.now().toIso8601String(),
      };
      if (user != null) deviceRow['user_id'] = user.id;

      await _db.from('devices').upsert(deviceRow, onConflict: 'device_key');

      Map<String, dynamic>? licenseRes;

      if (user != null) {
        licenseRes = await _db
            .from('licenses')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      licenseRes ??= await _db
          .from('licenses')
          .select()
          .eq('device_key', identity.deviceKey)
          .maybeSingle();

      if (licenseRes == null) {
        final trialEnd = DateTime.now().add(const Duration(days: 7)).toIso8601String();
        final trialRow = <String, dynamic>{
          'device_key': identity.deviceKey,
          'plan':       'trial',
          'expires_at': trialEnd,
          'is_active':  true,
        };
        if (user != null) trialRow['user_id'] = user.id;
        await _db.from('licenses').insert(trialRow);
        return true;
      }

      if (licenseRes['plan'] == 'lifetime') return true;
      if (licenseRes['is_active'] == false)  return false;

      final expiresAt = DateTime.tryParse(licenseRes['expires_at'] ?? '');
      if (expiresAt == null) return true;
      return expiresAt.isAfter(DateTime.now());

    } catch (e) {
      return true; // Fail-open si Supabase est down
    }
  }

  // ── Fetch playlists ───────────────────────────────────────────────────────
  //
  // Priorité : user_id (compte connecté) → device_key (fallback sans compte)

  static Future<List<Map<String, dynamic>>> fetchWebPlaylists() async {
    try {
      final identity = await DeviceService.getOrCreate();
      final user = currentUser;
      final List<Map<String, dynamic>> results = [];

      if (user != null) {
        final byUser = await _db
            .from('playlists')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        results.addAll(List<Map<String, dynamic>>.from(byUser));
      }

      try {
        final byDevice = await _db
            .from('playlists')
            .select()
            .eq('device_key', identity.deviceKey)
            .order('created_at', ascending: false);

        final seen = results.map((r) => r['id'] as String).toSet();
        for (final row in List<Map<String, dynamic>>.from(byDevice)) {
          if (!seen.contains(row['id'])) results.add(row);
        }
      } catch (_) {}

      return results;
    } catch (e) {
      return [];
    }
  }

  // ── Realtime : écoute les changements de playlists ────────────────────────

  static RealtimeChannel subscribeToPlaylists(
    void Function(List<Map<String, dynamic>>) onUpdate,
  ) {
    final channel = _db.channel('playlists-app-sync');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'playlists',
      callback: (_) async {
        final fresh = await fetchWebPlaylists();
        onUpdate(fresh);
      },
    ).subscribe();

    return channel;
  }

  // ── Push playlist depuis l'app vers Supabase ─────────────────────────────

  static Future<String?> pushPlaylist({
    required String name,
    required String type,
    String? xtreamHost,
    String? xtreamUsername,
    String? xtreamPassword,
    String? m3uUrl,
  }) async {
    try {
      final identity = await DeviceService.getOrCreate();
      final user = currentUser;

      final row = <String, dynamic>{
        'name':       name,
        'type':       type,
        'is_active':  true,
        'device_key': identity.deviceKey,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (user != null) row['user_id'] = user.id;

      if (type == 'xtream') {
        row['xtream_host']     = xtreamHost     ?? '';
        row['xtream_username'] = xtreamUsername ?? '';
        row['xtream_password'] = xtreamPassword ?? '';
      } else {
        row['m3u_url'] = m3uUrl ?? '';
      }

      final res = await _db
          .from('playlists')
          .insert(row)
          .select('id')
          .single();

      return res['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  // ── Supprime une playlist dans Supabase ───────────────────────────────────

  static Future<void> deletePlaylist(String supabaseId) async {
    try {
      await _db.from('playlists').delete().eq('id', supabaseId);
    } catch (_) {}
  }

  // ── Mise à jour last_seen ─────────────────────────────────────────────────

  static Future<void> pingDevice() async {
    try {
      final identity = await DeviceService.getOrCreate();
      await _db
          .from('devices')
          .update({'last_seen_at': DateTime.now().toIso8601String()})
          .eq('device_key', identity.deviceKey);
    } catch (_) {}
  }

  // ── Récupère les infos de licence ─────────────────────────────────────────

  static Future<Map<String, dynamic>?> getLicenseInfo() async {
    try {
      final identity = await DeviceService.getOrCreate();
      final user = currentUser;
      Map<String, dynamic>? lic;

      if (user != null) {
        lic = await _db
            .from('licenses')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      lic ??= await _db
          .from('licenses')
          .select()
          .eq('device_key', identity.deviceKey)
          .maybeSingle();

      return lic;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC CLOUD — Favoris & Historique
  // ══════════════════════════════════════════════════════════════════════════

  // ── Upload favoris local → Supabase (upsert) ─────────────────────────────

  static Future<void> uploadFavorites(List<Map<String, dynamic>> favorites) async {
    final user = currentUser;
    if (user == null || favorites.isEmpty) return;
    try {
      final rows = favorites.map((f) => {
        'user_id':     user.id,
        'stream_id':   f['streamId']  as int? ?? 0,
        'tab_index':   f['tabIndex']  as int? ?? 1,
        'title':       f['title']     as String? ?? '',
        'stream_icon': f['streamIcon'] as String? ?? '',
        'stream_url':  f['streamUrl'] as String? ?? '',
        'container_extension': f['containerExtension'] as String? ?? '',
        'added_at':    f['addedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(f['addedAt'] as int).toIso8601String()
            : DateTime.now().toIso8601String(),
      }).toList();
      await _db.from('user_favorites').upsert(rows,
          onConflict: 'user_id,stream_id,tab_index');
    } catch (e) {
      debugPrint('[Sync] uploadFavorites: \$e');
    }
  }

  // ── Download favoris Supabase → local ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>> downloadFavorites() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final rows = await _db
          .from('user_favorites')
          .select()
          .eq('user_id', user.id)
          .order('added_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows).map((r) => {
        'streamId':           r['stream_id']          as int? ?? 0,
        'tabIndex':           r['tab_index']           as int? ?? 1,
        'title':              r['title']               as String? ?? '',
        'streamIcon':         r['stream_icon']         as String? ?? '',
        'streamUrl':          r['stream_url']          as String? ?? '',
        'containerExtension': r['container_extension'] as String? ?? '',
        'addedAt': r['added_at'] != null
            ? DateTime.parse(r['added_at'] as String).millisecondsSinceEpoch
            : 0,
      }).toList();
    } catch (e) {
      debugPrint('[Sync] downloadFavorites: \$e');
      return [];
    }
  }

  // ── Upload historique local → Supabase ────────────────────────────────────

  static Future<void> uploadHistory(List<Map<String, dynamic>> history) async {
    final user = currentUser;
    if (user == null || history.isEmpty) return;
    try {
      final rows = history.take(50).map((h) => {
        'user_id':                user.id,
        'stream_id':              h['streamId']             as int? ?? 0,
        'tab_index':              h['tabIndex']             as int? ?? 1,
        'title':                  h['title']                as String? ?? '',
        'stream_icon':            h['streamIcon']           as String? ?? '',
        'stream_url':             h['streamUrl']            as String? ?? '',
        'position_seconds':       h['positionSeconds']      as int? ?? 0,
        'total_duration_seconds': h['totalDurationSeconds'] as int? ?? 0,
        'watched_at': h['watchedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(h['watchedAt'] as int).toIso8601String()
            : DateTime.now().toIso8601String(),
      }).toList();
      await _db.from('user_history').upsert(rows,
          onConflict: 'user_id,stream_id,tab_index');
    } catch (e) {
      debugPrint('[Sync] uploadHistory: \$e');
    }
  }

  // ── Download historique Supabase → local ──────────────────────────────────

  static Future<List<Map<String, dynamic>>> downloadHistory() async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final rows = await _db
          .from('user_history')
          .select()
          .eq('user_id', user.id)
          .order('watched_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(rows).map((r) => {
        'streamId':              r['stream_id']              as int? ?? 0,
        'tabIndex':              r['tab_index']              as int? ?? 1,
        'title':                 r['title']                  as String? ?? '',
        'streamIcon':            r['stream_icon']            as String? ?? '',
        'streamUrl':             r['stream_url']             as String? ?? '',
        'positionSeconds':       r['position_seconds']       as int? ?? 0,
        'totalDurationSeconds':  r['total_duration_seconds'] as int? ?? 0,
        'watchedAt': r['watched_at'] != null
            ? DateTime.parse(r['watched_at'] as String).millisecondsSinceEpoch
            : 0,
      }).toList();
    } catch (e) {
      debugPrint('[Sync] downloadHistory: \$e');
      return [];
    }
  }

}