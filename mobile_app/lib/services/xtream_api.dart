// lib/services/xtream_api.dart
//
// Arich Player — XtreamApi v2.0 PERF
// ─────────────────────────────────────────────────────────────────────────────
// [PERF-1] json.decode + parsing Channel.fromJson → compute() isolate
//          Libère le main thread pendant le parsing de 5k-20k chaînes
// [PERF-2] Cache HTTP en mémoire avec TTL 10min — évite les re-téléchargements
//          répétés à chaque changement d'onglet ou retour de navigation
// [PERF-3] Timeout réduit : auth 12s, streams 45s, categories 20s
// [PERF-4] http.Client persistant (connexion keep-alive) au lieu de http.get()
//          qui ouvre une nouvelle connexion à chaque appel
// [PERF-5] Chunked notification : allMovies/allSeries notifiés en 2 passes
//          (1000 items d'abord → UI responsive, reste en background)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import 'dart:developer' as dev;

// ── Cache HTTP en mémoire ────────────────────────────────────────────────────
class _CacheEntry {
  final String body;
  final DateTime expiry;
  const _CacheEntry(this.body, this.expiry);
  bool get isValid => DateTime.now().isBefore(expiry);
}

// ─────────────────────────────────────────────────────────────────────────────
// Fonctions top-level pour compute() — DOIVENT être au top level
// ─────────────────────────────────────────────────────────────────────────────
List<Channel> _parseChannels(String body) {
  try {
    final decoded = json.decode(body);
    if (decoded is! List) return [];
    return decoded.map((item) => Channel.fromJson(item as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
}

List<Map<String, dynamic>> _parseCategories(String body) {
  try {
    final List<dynamic> data = json.decode(body);
    return data.map((e) => {
      'id': e['category_id']?.toString() ?? '',
      'name': e['category_name']?.toString() ?? '',
    }).toList();
  } catch (_) {
    return [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class XtreamApi {
  String baseUrl  = '';
  String username = '';
  String password = '';
  String lastRawResponse = '';

  // [PERF-4] Client persistant keep-alive
  // [FIX-v13] Non-final : recréé après logout() pour éviter "Client is already closed"
  http.Client _client = http.Client();

  // [PERF-2] Cache en mémoire TTL
  final Map<String, _CacheEntry> _cache = {};
  static const _kCacheTtl = Duration(minutes: 10);

  // [FIX-v12] UA ktor-client — identifié via HTTP Toolkit comme le UA accepté
  // par les serveurs CDN IPTV (vortex8k et compatibles).
  final Map<String, String> _headers = const {
    'User-Agent':      'ktor-client',
    'Accept':          'application/json',
    'Accept-Charset':  'UTF-8',
    'Accept-Encoding': 'deflate,gzip',
    'Connection':      'Keep-Alive',
  };

  void setCredentials(String url, String user, String pass) {
    var clean = url.trim();

    clean = clean.replaceAll(RegExp(r'/+$'), '');

    // 🔥 FIX XTREAM
    if (clean.endsWith('/c')) {
      clean = clean.substring(0, clean.length - 2);
    }

    baseUrl  = clean;
    username = user.trim();
    password = pass.trim();

    clearCache();
  }

  void clearCache() => _cache.clear();

  // [FIX-v13] reset() : ferme l'ancien client et en recrée un neuf.
  // Appelé par IptvProvider.logout() — remplace dispose() pour que
  // le prochain login() ne tombe pas sur "Client is already closed".
  void reset() {
    try { _client.close(); } catch (_) {}
    _client = http.Client();
    _cache.clear();
    baseUrl  = '';
    username = '';
    password = '';
    lastRawResponse = '';
  }

  void dispose() {
    try { _client.close(); } catch (_) {}
    _cache.clear();
  }

  // ── GET avec cache ─────────────────────────────────────────────────────────
  Future<String?> _cachedGet(Uri uri, {Duration? timeout}) async {
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null && cached.isValid) {
      dev.log('[API] Cache hit: ${uri.path}');
      return cached.body;
    }
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(timeout ?? const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final body = response.body;
        _cache[key] = _CacheEntry(body, DateTime.now().add(_kCacheTtl));
        return body;
      }
    } catch (e) {
      dev.log('[API] HTTP error: $e');
    }
    return null;
  }

  // ── Auth ───────────────────────────────────────────────────────────────────
  Future<bool> authenticate() async {
    final result = await authenticateWithInfo();
    return result != null;
  }

  Future<Map<String, dynamic>?> authenticateWithInfo() async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {'username': username, 'password': password},
    );
    dev.log('[API] authenticateWithInfo() → $uri');
    try {
      // Auth : pas de cache (toujours frais), timeout court
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20)); // [FIX] 20s pour VPN/réseau lent

      final bodyPreview = response.body.length > 400
          ? response.body.substring(0, 400)
          : response.body;
      dev.log('[API] HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        lastRawResponse = 'HTTP ${response.statusCode}\n$bodyPreview';
        return null;
      }

      final trimmed = response.body.trimLeft();
      if (trimmed.startsWith('<!') || trimmed.startsWith('<html') || trimmed.startsWith('<HTML')) {
        lastRawResponse = 'HTML_RESPONSE';
        return null;
      }

      dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        lastRawResponse = 'JSON invalide:\n$bodyPreview';
        return null;
      }

      if (data is! Map) {
        lastRawResponse = 'Réponse non-JSON:\n$bodyPreview';
        return null;
      }

      if (data['user_info'] is Map) {
        final userInfo = Map<String, dynamic>.from(data['user_info'] as Map);
        final auth = userInfo['auth'];
        final isAuthed = auth == 1 || auth == '1' || auth == true ||
            userInfo['status']?.toString().toLowerCase() == 'active' ||
            userInfo['status']?.toString().toLowerCase() == 'actif';
        if (isAuthed || userInfo.isNotEmpty) {
          lastRawResponse = '';
          return userInfo;
        }
        lastRawResponse = 'auth=0\n$bodyPreview';
      }

      if ((data as Map).containsKey('username') && data.containsKey('password')) {
        lastRawResponse = '';
        return Map<String, dynamic>.from(data);
      }

      lastRawResponse = 'Structure inconnue:\n$bodyPreview';
      return null;
    } catch (e) {
      if (e.toString().contains('TimeoutException') || e.toString().contains('timed out')) {
        dev.log('[API] authenticateWithInfo() TIMEOUT: $e');
        lastRawResponse = 'TIMEOUT';
      } else {
        dev.log('[API] authenticateWithInfo() EXCEPTION: $e');
        lastRawResponse = e.toString().length > 200 ? e.toString().substring(0, 200) : e.toString();
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    final result = await authenticateWithInfo();
    return result ?? {};
  }

  // ── Streams — parsing dans isolate ────────────────────────────────────────
  Future<List<Channel>> getStreams(String action) async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {'username': username, 'password': password, 'action': action},
    );
    try {
      // [PERF-3] Timeout réduit à 45s
      final body = await _cachedGet(uri, timeout: const Duration(seconds: 45));
      if (body == null || body.isEmpty) return [];

      // [PERF-1] Parsing dans un isolate — libère le main thread
      final channels = await compute(_parseChannels, body);
      dev.log('[API] getStreams($action): ${channels.length} items');
      return channels;
    } catch (e) {
      dev.log('[API] getStreams($action) EXCEPTION: $e');
      return [];
    }
  }

  // ── Categories — parsing dans isolate ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCategories(String action) async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {'username': username, 'password': password, 'action': action},
    );
    try {
      final body = await _cachedGet(uri, timeout: const Duration(seconds: 20));
      if (body == null || body.isEmpty) return [];

      // [PERF-1] Parsing dans un isolate
      final cats = await compute(_parseCategories, body);
      dev.log('[API] getCategories($action): ${cats.length} items');
      return cats;
    } catch (e) {
      dev.log('[API] getCategories($action) EXCEPTION: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSeriesInfo(int seriesId) async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {
        'username': username, 'password': password,
        'action': 'get_series_info', 'series_id': seriesId.toString(),
      },
    );
    try {
      final body = await _cachedGet(uri, timeout: const Duration(seconds: 30));
      if (body == null) return {};
      return json.decode(body) as Map<String, dynamic>;
    } catch (e) {
      dev.log('[API] getSeriesInfo EXCEPTION: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getVodInfo(int vodId) async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {
        'username': username, 'password': password,
        'action': 'get_vod_info', 'vod_id': vodId.toString(),
      },
    );
    try {
      final body = await _cachedGet(uri, timeout: const Duration(seconds: 30));
      if (body == null) return {};
      return json.decode(body) as Map<String, dynamic>;
    } catch (e) {
      dev.log('[API] getVodInfo EXCEPTION: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getShortEpg(int streamId, {int limit = 2}) async {
    final uri = Uri.parse('$baseUrl/player_api.php').replace(
      queryParameters: {
        'username': username, 'password': password,
        'action': 'get_short_epg',
        'stream_id': streamId.toString(),
        'limit': limit.toString(),
      },
    );
    try {
      final body = await _cachedGet(uri, timeout: const Duration(seconds: 15));
      if (body == null) return {};
      return json.decode(body) as Map<String, dynamic>;
    } catch (e) {
      dev.log('[API] getShortEpg EXCEPTION: $e');
      return {};
    }
  }
}