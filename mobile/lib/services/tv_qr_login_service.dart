// lib/services/tv_qr_login_service.dart
//
// Arich Player — TV QR Login Service
//
// Flux :
//  1. generateSession()  → insère un token unique dans tv_sessions (status=pending)
//  2. watchSession()     → subscribe Supabase Realtime sur ce token
//  3. Dès status=authenticated → callback onAuthenticated(userId)
//  4. dispose()          → annule le channel Realtime + supprime le token expiré
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef OnAuthenticated = void Function(String userId, String? email);

class TvQrLoginService {
  static final _client = Supabase.instance.client;

  String? _token;
  RealtimeChannel? _channel;

  String? get token => _token;

  /// URL complète encodée dans le QR code
  String get qrUrl {
    if (_token == null) return '';
    return 'https://arich.fr/tv-login.html'
        '?token=${Uri.encodeComponent(_token!)}';
  }

  // ── Génère un token unique et l'insère dans tv_sessions ─────────────────

  Future<void> generateSession() async {
    _token = _randomToken();
    await _client.from('tv_sessions').insert({
      'token':      _token,
      'status':     'pending',
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
    });
  }

  // ── Subscribe Realtime — déclenche onAuthenticated dès que status change ─

  void watchSession({
    required OnAuthenticated onAuthenticated,
    required void Function() onExpired,
  }) {
    if (_token == null) return;

    _channel = _client
        .channel('tv_session_$_token')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tv_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'token',
            value: _token!,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            final status = newRow['status'] as String?;
            if (status == 'authenticated') {
              final userId = newRow['user_id'] as String?;
              final email  = newRow['email']   as String?;
              if (userId != null) {
                onAuthenticated(userId, email);
              }
            } else if (status == 'expired') {
              onExpired();
            }
          },
        )
        .subscribe();
  }

  // ── Supprime la session et ferme le channel ──────────────────────────────

  Future<void> dispose() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
    if (_token != null) {
      await _client
          .from('tv_sessions')
          .delete()
          .eq('token', _token!);
      _token = null;
    }
  }

  // ── Régénère un nouveau token (QR expiré) ────────────────────────────────

  Future<void> refresh({
    required OnAuthenticated onAuthenticated,
    required void Function() onExpired,
  }) async {
    await dispose();
    await generateSession();
    watchSession(onAuthenticated: onAuthenticated, onExpired: onExpired);
  }

  // ── Token aléatoire 32 chars alphanum ────────────────────────────────────

  static String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}