// lib/services/tmdb_service.dart
//
// Arich Player — Service TMDB
// • Recherche poster par nom (film ou série)
// • Cache Hive 7 jours pour éviter les appels répétés
// • Détection automatique film vs série via tabIndex
// • Fallback silencieux (null) si non trouvé
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

class TmdbService {
  static const String _apiKey = 'ac806abca26529c849a97e9f4d36179c';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w300';
  static const String _boxName = 'tmdb_cache';
  static const Duration _cacheDuration = Duration(days: 7);

  // ─── Cache Hive ───────────────────────────────────────────────────────────

  static Box? _box;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox(_boxName);
    } else {
      _box = Hive.box(_boxName);
    }
  }

  static Box get _cache {
    if (_box == null || !_box!.isOpen) {
      _box = Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : null;
    }
    return _box!;
  }
  static String _cacheKey(String title, bool isMovie) =>
      '${isMovie ? "movie" : "tv"}:${title.trim().toLowerCase()}';

  static String? _fromCache(String key) {
    try {
      final raw = _cache.get(key);
      if (raw == null) return null;
      if (raw is Map) {
        final expiresAt = raw['expires_at'] as int?;
        if (expiresAt == null) return null;
        if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
          _cache.delete(key);
          return null;
        }
        return raw['poster'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _toCache(String key, String? posterUrl) async {
    try {
      await _cache.put(key, {
        'poster': posterUrl,
        'expires_at':
            DateTime.now().add(_cacheDuration).millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  // ─── API TMDB ─────────────────────────────────────────────────────────────


  /// [tabIndex] : 2 = film, 3 = série
  /// Retourne null si non trouvé ou erreur réseau.
  static Future<String?> getPoster(String title, {required int tabIndex}) async {
    if (title.isEmpty) return null;

    final isMovie = tabIndex == 2;
    final cleanTitle = _cleanTitle(title);
    final key = _cacheKey(cleanTitle, isMovie);

    // 1) Vérifier le cache
    final cached = _fromCache(key);
    if (cached != null) return cached;

    // 2) Appel API
    try {
      final endpoint = isMovie ? 'search/movie' : 'search/tv';
      final titleParam = isMovie ? 'title' : 'name';

      final uri = Uri.parse('$_baseUrl/$endpoint').replace(
        queryParameters: {
          'api_key': _apiKey,
          'query': cleanTitle,
          'language': 'fr-FR',
          'page': '1',
        },
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        await _toCache(key, null);
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;

      if (results == null || results.isEmpty) {

        final posterEn =
            await _searchInLanguage(cleanTitle, isMovie, 'en-US', titleParam);
        await _toCache(key, posterEn);
        return posterEn;
      }

      for (final item in results) {
        final posterPath = item['poster_path'] as String?;
        if (posterPath != null && posterPath.isNotEmpty) {
          final url = '$_imageBase$posterPath';
          await _toCache(key, url);
          return url;
        }
      }

      await _toCache(key, null);
      return null;
    } catch (e) {
      debugPrint('[TMDB] getPoster("$title") error: $e');
      return null; 
    }
  }

  static Future<String?> _searchInLanguage(
      String title, bool isMovie, String lang, String titleParam) async {
    try {
      final endpoint = isMovie ? 'search/movie' : 'search/tv';
      final uri = Uri.parse('$_baseUrl/$endpoint').replace(
        queryParameters: {
          'api_key': _apiKey,
          'query': title,
          'language': lang,
          'page': '1',
        },
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      for (final item in results) {
        final posterPath = item['poster_path'] as String?;
        if (posterPath != null && posterPath.isNotEmpty) {
          return '$_imageBase$posterPath';
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Nettoyage du titre ───────────────────────────────────────────────────

  /// Supprime les préfixes courants des IPTV (FR:, 4K |, etc.)
  static String _cleanTitle(String raw) {
    String t = raw;

    // Supprime les préfixes type "FR: ", "4K | ", "HD | ", "[FR] ", "(FR) "
    t = t.replaceAll(RegExp(r'^\s*[\[(]?[A-Z]{2,5}[\])]?\s*[:\|]\s*'), '');
    t = t.replaceAll(RegExp(r'^\s*(4K|HD|SD|FHD|UHD)\s*[\|:]\s*', caseSensitive: false), '');

    // Supprime les suffixes qualité " 4K", " HD", " FHD", " S01E01", etc.
    t = t.replaceAll(RegExp(r'\s+(4K|FHD|HD|SD|UHD)\s*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+S\d{2}(E\d{2})?\s*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+SAISON\s+\d+\s*$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+SEASON\s+\d+\s*$', caseSensitive: false), '');

    // Supprime les années entre parenthèses à la fin : " (2023)"
    t = t.replaceAll(RegExp(r'\s+\(\d{4}\)\s*$'), '');

    return t.trim();
  }

  // ─── Préchargement batch ──────────────────────────────────────────────────

  // ─── Détails complets (rating, genres, année, backdrop, overview) ──────────

  static Future<Map<String, dynamic>?> getDetails(String title, {required int tabIndex}) async {
    if (title.isEmpty) return null;
    final isMovie  = tabIndex == 2;
    final cleanTitle = _cleanTitle(title);
    final cacheKey = '${isMovie ? "details_movie" : "details_tv"}:${cleanTitle.toLowerCase()}';

    // Cache Hive 7j
    try {
      final raw = _cache.get(cacheKey);
      if (raw is Map) {
        final exp = raw['expires_at'] as int?;
        if (exp != null && DateTime.now().millisecondsSinceEpoch < exp) {
          final data = raw['data'];
          return data is Map ? Map<String, dynamic>.from(data) : null;
        }
      }
    } catch (_) {}

    try {
      final endpoint = isMovie ? 'search/movie' : 'search/tv';
      final uri = Uri.parse('$_baseUrl/$endpoint').replace(queryParameters: {
        'api_key': _apiKey, 'query': cleanTitle,
        'language': 'fr-FR', 'page': '1',
      });
      final response = await http.get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data    = json.decode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      // Prendre le premier résultat avec une image
      final first = results.firstWhere(
        (r) => (r['poster_path'] as String?) != null,
        orElse: () => results.first,
      );

      // Fetch les détails complets (genres, budget, etc.)
      final detailId = first['id'];
      final detailEndpoint = isMovie ? 'movie/$detailId' : 'tv/$detailId';
      final detailUri = Uri.parse('$_baseUrl/$detailEndpoint').replace(
        queryParameters: {'api_key': _apiKey, 'language': 'fr-FR'});
      final detailResp = await http.get(detailUri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      final details = detailResp.statusCode == 200
          ? json.decode(detailResp.body) as Map<String, dynamic>
          : first as Map<String, dynamic>;

      // Mise en cache
      await _cache.put(cacheKey, {
        'data': details,
        'expires_at': DateTime.now().add(_cacheDuration).millisecondsSinceEpoch,
      });

      return details;
    } catch (e) {
      debugPrint('[TMDB] getDetails("$title") error: $e');
      return null;
    }
  }

  static void prefetchPosters(List<String> titles, {required int tabIndex}) {
    Future.microtask(() async {
      for (final title in titles) {
        await getPoster(title, tabIndex: tabIndex);
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
  }

  static Future<void> clearCache() async {
    try {
      await _cache.clear();
    } catch (_) {}
  }

  static int get cacheSize {
    try {
      return _cache.length;
    } catch (_) {
      return 0;
    }
  }
}