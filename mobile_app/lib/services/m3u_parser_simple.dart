// lib/services/m3u_parser_simple.dart
//
// Arich Player — SimpleM3uParser
// [FIX-885-v4] HTTP 885 = erreur serveur (IP bloquée, trop de connexions, abonnement expiré)
//   → On lit le body HTML pour extraire le vrai message d'erreur.
//   → On arrête immédiatement si le body est identique entre tentatives (inutile de changer d'UA).
//   → La rotation UA est conservée uniquement si les réponses diffèrent (rare cas de whitelist UA).
// [FIX-TIMEOUT] 60s pour les grosses playlists.

import 'dart:convert';
import 'package:http/http.dart' as http;

// ── User-Agents testés dans l'ordre ────────────────────────────────────────
// [FIX-v13] ktor-client en premier — UA accepté par vortex8k et serveurs
// compatibles Xtream Codes qui bloquent les UAs navigateur/VLC.
// Identifié via HTTP Toolkit en sniffant l'app IPTV Pro Stream Player.
const _kUserAgents = [
  'ktor-client',
  'VLC/3.0.18 LibVLC/3.0.18',
  'Dalvik/2.1.0 (Linux; U; Android 12; SM-G998B Build/SP1A.210812.016)',
  'TiviMate/4.7.0 (Android)',
  'IPTV Smarters/1.0 CFNetwork/1312 Darwin/21.0.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'OTT Navigator/1.6.8.5 (Android)',
  'Perfect Player/1.6.1',
];

class M3uChannel {
  final String name;
  final String url;
  final String logo;
  final String category;
  final String streamId;
  final String tvgId;

  M3uChannel({
    required this.name,
    required this.url,
    this.logo = '',
    this.category = '',
    this.streamId = '',
    this.tvgId = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'stream_url': url,
    'stream_icon': logo,
    'category_id': category,
    'stream_id': streamId,
  };
}

class M3uCategory {
  final String categoryId;
  final String categoryName;

  M3uCategory({required this.categoryId, required this.categoryName});
}

class M3uResult {
  final List<M3uChannel> channels;
  final List<M3uCategory> categories;

  M3uResult({required this.channels, required this.categories});
}

class SimpleM3uParser {
  static bool isValidUrl(Uri uri) {
    if (uri.host.isEmpty) return false;
    if (uri.hasScheme && !uri.hasAuthority) return false;
    if (uri.path.contains('..')) return false;
    return true;
  }

  // ── Point d'entrée principal ───────────────────────────────────────────────
  static Future<M3uResult> parseFromUrl(String url) async {
    final cleanUrl = url.trim();
    print('[M3U] Chargement: $cleanUrl');

    dynamic lastError;

    for (int i = 0; i < _kUserAgents.length; i++) {
      final ua = _kUserAgents[i];
      try {
        print('[M3U] Tentative UA ${i + 1}/${_kUserAgents.length}: ${_shortUa(ua)}');
        final result = await _fetchAndParse(cleanUrl, ua);
        return result;
      } catch (e) {
        final msg = e.toString();

        // [FIX-v13] Suppression de la détection "body identique" :
        // elle stoppait le flow trop tôt et empêchait le fallback Xtream
        // dans IptvProvider de se déclencher.
        // On continue la rotation UA pour tous les codes bloquants.
        if (e is _BlockedWithBody) {
          print('[M3U] UA bloqué (${e.code}) → UA suivant');
          lastError = e;
          continue;
        }

        // UA bloqué sans body spécifique → on essaie le suivant
        if (_isUaBlockError(msg)) {
          print('[M3U] UA bloqué → UA suivant');
          lastError = e;
          continue;
        }

        // Toute autre erreur → on remonte immédiatement
        rethrow;
      }
    }

    // [FIX-v13] Tous les UA ont échoué avec HTTP 885/403.
    // On lève une exception TYPÉE _Xtream885Exception pour que
    // IptvProvider puisse déclencher le fallback Xtream proprement.
    final lastMsg = lastError is _BlockedWithBody
        ? (lastError as _BlockedWithBody).userMessage
        : 'Serveur inaccessible';
    throw _Xtream885Exception(lastMsg);
  }

  // ── Fetch + parse avec un UA donné ────────────────────────────────────────
  static Future<M3uResult> _fetchAndParse(String url, String userAgent) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':      userAgent,
        'Accept':          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept-Encoding': 'gzip, deflate',
        'Upgrade-Insecure-Requests': '1',
        'Connection':      'keep-alive',
      },
    ).timeout(const Duration(seconds: 60));

    print('[M3U] HTTP ${response.statusCode} | UA: ${_shortUa(userAgent)} | '
          'CT: ${response.headers['content-type'] ?? '-'}');

    String content;
    try {
      content = utf8.decode(response.bodyBytes);
    } catch (_) {
      content = latin1.decode(response.bodyBytes);
    }

    if (response.statusCode != 200) {
      final trimmed = content.trimLeft();
      final hasM3u  = trimmed.startsWith('#EXTM3U') ||
                      trimmed.contains('#EXTINF')   ||
                      trimmed.startsWith('#EXT-X-');

      if (hasM3u) {
        // Body M3U valide malgré code non-standard → on parse quand même
        print('[M3U] Code ${response.statusCode} mais body M3U détecté → parsing');
      } else {
        // [FIX-885] Extraire le vrai message du body avant de lever l'exception
        _throwForStatus(response.statusCode, content);
      }
    }

    if (content.isEmpty) {
      throw Exception('Réponse vide du serveur');
    }

    print('[M3U] ${content.length} caractères reçus');
    return _parseM3UContent(content);
  }

  // ── Extraction du message d'erreur depuis le body ─────────────────────────
  static String _extractErrorMessage(String body) {
    if (body.isEmpty) return '';

    // Tentative JSON
    try {
      final data = json.decode(body);
      if (data is Map) {
        final msg = data['message']?.toString()
            ?? data['error']?.toString()
            ?? data['msg']?.toString()
            ?? data['info']?.toString()
            ?? '';
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}

    // HTML → on strip les balises et on cherche les messages connus
    final stripped = body
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'&nbsp;|&amp;|&lt;|&gt;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Mots-clés courants dans les panneaux IPTV
    final lower = stripped.toLowerCase();
    if (lower.contains('too many connection') || lower.contains('max connection')) {
      return 'Trop de connexions simultanées sur ce compte';
    }
    if (lower.contains('expired') || lower.contains('expiré')) {
      return 'Abonnement expiré — contactez votre fournisseur';
    }
    if (lower.contains('banned') || lower.contains('banni')) {
      return 'Compte banni par le fournisseur';
    }
    if (lower.contains('ip') && (lower.contains('block') || lower.contains('banned'))) {
      return 'Adresse IP bloquée par le fournisseur';
    }
    if (lower.contains('invalid') || lower.contains('incorrect') || lower.contains('wrong')) {
      return 'Identifiants incorrects — vérifiez username et password';
    }
    if (lower.contains('suspended') || lower.contains('suspendu')) {
      return 'Compte suspendu — contactez votre fournisseur';
    }

    // Retourner un extrait du texte brut si rien de connu
    if (stripped.length > 150) return '${stripped.substring(0, 150)}…';
    return stripped.isNotEmpty ? stripped : '';
  }

  // ── Lance une exception selon le code HTTP ─────────────────────────────────
  static void _throwForStatus(int code, String body) {
    final extracted = _extractErrorMessage(body);

    switch (code) {
      // [FIX-885] 885 et 403 : on transporte le body pour comparer entre tentatives
      case 885:
      case 403:
        final detail = extracted.isNotEmpty ? '\n\nMessage serveur : $extracted' : '';
        throw _BlockedWithBody(
          code: code,
          body: body,
          userMessage: 'Le serveur a refusé la connexion.$detail',
        );

      case 401:
        throw Exception(
          'Identifiants refusés (HTTP 401).\n'
          '${extracted.isNotEmpty ? '$extracted\n' : ''}'
          'Vérifiez username et password dans votre URL.',
        );
      case 404:
        throw Exception(
          'Playlist introuvable (HTTP 404).\n'
          'Vérifiez que l\'URL est correcte et que le serveur est en ligne.',
        );
      case 429:
        throw Exception(
          'Trop de requêtes (HTTP 429).\n'
          'Attendez quelques secondes puis réessayez.',
        );
      case 500:
      case 502:
      case 503:
      case 504:
        throw Exception(
          'Erreur serveur (HTTP $code).\n'
          '${extracted.isNotEmpty ? '$extracted\n' : ''}'
          'Le serveur IPTV est peut-être hors ligne ou surchargé.\n'
          'Réessayez dans quelques minutes.',
        );
      default:
        throw Exception(
          'Erreur HTTP $code.\n'
          '${extracted.isNotEmpty ? '$extracted\n' : ''}'
          'Vérifiez l\'URL et l\'état de votre abonnement.',
        );
    }
  }

  // ── Parse du contenu M3U ───────────────────────────────────────────────────
  static M3uResult _parseM3UContent(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    final channels      = <M3uChannel>[];
    final categoryNames = <String>{};
    String? pendingExtinf;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        pendingExtinf = line;
        continue;
      }

      if (!line.startsWith('#') && line.contains('://')) {
        if (pendingExtinf != null) {
          final channel = _parseChannel(extinfLine: pendingExtinf, urlLine: line);
          if (channel != null) {
            channels.add(channel);
            categoryNames.add(channel.category);
          }
          pendingExtinf = null;
        }
      }
    }

    final categoryList = categoryNames
        .map((n) => M3uCategory(categoryId: n, categoryName: n))
        .toList();

    print('[M3U] ${channels.length} chaînes, ${categoryList.length} catégories');

    if (channels.isEmpty) {
      throw Exception(
        'Aucune chaîne trouvée dans cette playlist.\n'
        'Vérifiez que l\'URL pointe bien vers une playlist M3U valide.',
      );
    }

    return M3uResult(channels: channels, categories: categoryList);
  }

  static String _extractAttribute(String line, String attr) {
    return RegExp('$attr="([^"]*)"').firstMatch(line)?.group(1)
        ?? RegExp("$attr='([^']*)'").firstMatch(line)?.group(1)
        ?? '';
  }

  static String _extractCategory(String extinfLine) {
    String cat = _extractAttribute(extinfLine, 'group-title');
    if (cat.contains('|')) cat = cat.split('|').first.trim();
    return cat.isEmpty ? 'Sans catégorie' : cat;
  }

  static String _extractName(String extinfLine) {
    final idx = extinfLine.lastIndexOf(',');
    if (idx != -1 && idx < extinfLine.length - 1) {
      final n = extinfLine.substring(idx + 1).trim();
      if (n.isNotEmpty) return n;
    }
    final tvgName = _extractAttribute(extinfLine, 'tvg-name');
    return tvgName.isNotEmpty ? tvgName : 'Chaîne inconnue';
  }

  static M3uChannel? _parseChannel({
    required String extinfLine,
    required String urlLine,
  }) {
    try {
      final url = urlLine.trim();
      if (!url.contains('://')) return null;
      return M3uChannel(
        name:     _extractName(extinfLine),
        url:      url,
        logo:     _extractAttribute(extinfLine, 'tvg-logo'),
        tvgId:    _extractAttribute(extinfLine, 'tvg-id'),
        category: _extractCategory(extinfLine),
        streamId: '',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Helpers internes ──────────────────────────────────────────────────────

  static bool _isUaBlockError(String msg) =>
      msg.contains('HTTP 885') || msg.contains('HTTP 403');

  static String _shortUa(String ua) =>
      ua.length > 30 ? '${ua.substring(0, 30)}…' : ua;
}

// ── Exception publique : tous les UA ont échoué avec HTTP 885/403 ────────────
// Utilisée par IptvProvider pour détecter qu'il faut basculer sur Xtream API.
class _Xtream885Exception implements Exception {
  final String message;
  const _Xtream885Exception(this.message);

  @override
  String toString() => message;
}

// ── Exception interne transportant le body pour comparaison ──────────────────
class _BlockedWithBody implements Exception {
  final int code;
  final String body;
  final String userMessage;

  const _BlockedWithBody({
    required this.code,
    required this.body,
    required this.userMessage,
  });

  @override
  String toString() => userMessage;
}