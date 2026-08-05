// lib/services/m3u_parser.dart

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/category.dart';
import 'country_detector.dart';
import 'dart:developer' as dev;

class M3uParser {

  /// Rejette les URL où la requête a été collée sans domaine : [Uri] met alors
  /// toute la chaîne dans [host] (ex. `http://name=foo&password=bar&type=m3u_plus`).
  static bool isPlausibleHttpAuthority(Uri uri) {
    if (uri.host.isEmpty) return false;
    final h = uri.host;
    if (h.contains('=') || h.contains('&')) return false;
    if (h.contains('?') || h.contains('#')) return false;
    return true;
  }

  /// Lit un petit snippet du corps de réponse (pour erreurs) sans faire planter
  /// l'import. Le contenu peut être HTML/JSON; on masque `password=...`.
  static Future<String> _readErrorSnippet(HttpClientResponse response,
      {int limitBytes = 600}) async {
    final bytes = <int>[];
    try {
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= limitBytes) break;
      }
    } catch (_) {
      return '';
    }

    if (bytes.isEmpty) return '';

    String s;
    try {
      s = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      s = latin1.decode(bytes);
    }

    // Masquage minimal (évite d'afficher le mot de passe collé dans l'URL).
    s = s.replaceAll(
      RegExp(r'password=[^&\s]+', caseSensitive: false),
      'password=***',
    );

    return s.trim();
  }

  static Future<M3uParseResult> parseFromUrl(String url) async {
    final cleanUrl = url.trim();
    dev.log('[M3U] GET $cleanUrl');

    String content;
    try {
      // Headers ultra-compatibles pour serveurs IPTV stricts
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'max-age=0',
      };

      final response = await http.get(
        Uri.parse(cleanUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 90));

      dev.log('[M3U] HTTP ${response.statusCode} | CT: ${response.headers['content-type']}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        final snippet = response.body.substring(0, response.body.length > 600 ? 600 : response.body.length);
        throw Exception(
            'Accès refusé (HTTP ${response.statusCode}).\n'
            'Vérifiez vos identifiants dans l\'URL M3U_PLUS.'
            '${snippet.isNotEmpty ? '\nRéponse (début): $snippet' : ''}');
      }
      if (response.statusCode == 404) {
        final snippet = response.body.substring(0, response.body.length > 600 ? 600 : response.body.length);
        throw Exception(
            'Playlist introuvable (HTTP 404).\n'
            'Vérifiez que l\'URL est correcte.'
            '${snippet.isNotEmpty ? '\nRéponse (début): $snippet' : ''}');
      }
      if (response.statusCode >= 500) {
        final snippet = response.body.substring(0, response.body.length > 600 ? 600 : response.body.length);
        final ct = response.headers['content-type'] ?? '';
        throw Exception(
            'Erreur serveur (HTTP ${response.statusCode}).\n'
            'Content-Type: $ct.\n'
            'Le serveur IPTV est peut-être hors ligne ou bloque l\'accès.\n'
            '${snippet.isNotEmpty ? 'Réponse (début): $snippet\n' : ''}'
            'Vérifie aussi l\'URL et les identifiants.');
      }
      if (response.statusCode != 200) {
        throw Exception('Serveur a répondu HTTP ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      dev.log('[M3U] ${bytes.length} octets reçus');

      if (bytes.isEmpty) {
        throw Exception('La playlist reçue est vide (0 octets)');
      }

      final ct = response.headers['content-type'] ?? '';
      if (ct.contains('utf-8') || ct.contains('UTF-8')) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else {
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          dev.log('[M3U] UTF-8 invalide → latin-1');
          content = latin1.decode(bytes);
        }
      }

    } on SocketException catch (e) {
      throw Exception(
          'Impossible de joindre le serveur.\n'
          'Vérifiez votre connexion internet.\nDétail: ${e.message}');
    } on HttpException catch (e) {
      throw Exception('Erreur réseau : ${e.message}');
    } on TimeoutException {
      throw Exception(
          'Délai dépassé — le serveur ne répond pas.\n'
          'Vérifiez que l\'URL est correcte et le serveur en ligne.');
    } on Exception {
      rethrow;
    }

    if (content.isEmpty) throw Exception('Playlist vide après décodage');

    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final data = json.decode(content);
        if (data is Map) {
          final userInfo = data['user_info'];
          if (userInfo is Map) {
            final auth   = userInfo['auth'];
            final status = userInfo['status']?.toString().toLowerCase() ?? '';
            if (auth == 0 || auth == '0' || auth == false) {
              throw Exception(
                  'Identifiants incorrects (auth=0).\n'
                  'Vérifiez username et password dans votre URL.\n'
                  'Ex: /get.php?username=XXX&password=YYY&type=m3u_plus');
            }
            if (status == 'banned') throw Exception('Compte banni par le fournisseur.');
            if (status == 'expired') throw Exception('Abonnement expiré. Contactez votre fournisseur.');
          }
          final msg = data['message']?.toString()
                   ?? data['error']?.toString()
                   ?? data['msg']?.toString();
          if (msg != null && msg.isNotEmpty) throw Exception('Erreur serveur : $msg');
        }
      } on FormatException {
        // JSON malformé → on tente quand même le parsing M3U
      }
      if (!content.contains('#EXTM3U') && !content.contains('#EXTINF')) {
        throw Exception(
            'Le serveur a renvoyé du JSON au lieu d\'une playlist M3U.\n'
            'L\'URL doit contenir &type=m3u_plus dans les paramètres.');
      }
    }

    if (trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html') ||
        trimmed.startsWith('<HTML')) {
      throw Exception(
          'Le serveur a renvoyé une page HTML au lieu d\'une playlist M3U.\n'
          'Vérifiez que l\'URL pointe vers le fichier M3U directement.\n'
          'Ex: http://serveur.com/get.php?username=X&password=Y&type=m3u_plus');
    }

    // Délègue le parsing lourd à un Isolate — ne bloque pas le UI thread
    return await parseContent(content);
  }

  // ── parseContent : délègue le parsing lourd à un Isolate dédié ──────────────
  // Évite le freeze / ANR sur les playlists de 10 000+ chaînes.
  static Future<M3uParseResult> parseContent(String content) async {
    return await Isolate.run(() => _parseContentSync(content));
  }

  // ── Parsing synchrone (s'exécute dans l'Isolate, jamais sur le UI thread) ──
  static M3uParseResult _parseContentSync(String content) {
    // [PERF] BOM strip + normalisation CRLF en une seule passe
        String cleaned = content;
        if (content.startsWith('\uFEFF')) {
          if (content.length > 1) {
            cleaned = content.substring(1);
          } else {
            cleaned = '';
          }
        }
        cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // [PERF] LineSplitter itère sans allouer une List<String> complète
    final lines = const LineSplitter().convert(cleaned);

    final firstMeaningful = lines.take(5)
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final hasExtM3u = firstMeaningful.startsWith('#EXTM3U');

    if (!hasExtM3u) {
      final hasUrls = lines.any((l) =>
          l.startsWith('http://') || l.startsWith('https://') ||
          l.startsWith('rtmp://')  || l.startsWith('rtsp://'));
      if (!hasUrls) {
        throw Exception('Format M3U invalide — ni entête #EXTM3U ni URLs détectées.');
      }
    }

    final channels      = <Channel>[];
    final categorySet   = <String>{};
    final countryCache  = <String, CountryInfo?>{};   // [PERF] évite detect() répété

    int     idCounter    = 1;
    String? pendingExtinf;

    for (final rawLine in lines) {
      try {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#EXTINF')) { pendingExtinf = line; continue; }

        if (line.startsWith('http://') || line.startsWith('https://') ||
            line.startsWith('rtmp://')  || line.startsWith('rtsp://')) {
          final extinf  = pendingExtinf ?? '';
          pendingExtinf = null;

          // [ROBUST] Une ligne malformée ne doit jamais casser tout l'import.
          final extracted = extinf.isNotEmpty ? _extractName(extinf) : '';
          final name      = extracted.isNotEmpty ? extracted : _nameFromUrl(line);
          if (name.isEmpty) continue;

          final logo       = extinf.isNotEmpty ? (_extractAttr(extinf, 'tvg-logo') ?? '') : '';
          final groupTitle = extinf.isNotEmpty
              ? (_extractAttr(extinf, 'group-title') ?? 'Non classé')
              : 'Non classé';
          final tvgId      = extinf.isNotEmpty ? (_extractAttr(extinf, 'tvg-id') ?? '') : '';

          final country = countryCache.putIfAbsent(
            groupTitle,
            () => CountryDetector.detect(groupTitle),
          );

          categorySet.add(groupTitle);

          channels.add(Channel(
            streamId:           idCounter++,
            name:               name,
            streamIcon:         logo,
            categoryId:         groupTitle,
            containerExtension: _getExtension(line),
            streamUrl:          line,
            tvgId:              tvgId,
            groupTitle:         groupTitle,
            countryCode:        country?.code,
            countryFlag:        country?.flag,
            countryName:        country?.name,
          ));
        }
      } catch (_) {
        // Ignore la ligne fautive et continue l'import.
      }
    }

    if (channels.isEmpty) throw Exception('Playlist vide — aucune chaîne trouvée.');

    final categories = categorySet
        .map((n) => Category(categoryId: n, categoryName: n))
        .toList()
      ..sort((a, b) => a.categoryName.compareTo(b.categoryName));

    return M3uParseResult(channels: channels, categories: categories);
  }

  static String _nameFromUrl(String url) {
    try {
      final uri      = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = segments.last;
        final dot  = last.lastIndexOf('.');
        final name = dot > 0 ? last.substring(0, dot) : last;
        if (name.isNotEmpty && name != 'get' && name != 'play') return name;
      }
      return uri.host.isNotEmpty ? uri.host : 'Stream';
    } catch (_) { return 'Stream'; }
  }

  static String _extractName(String extinf) {
    if (extinf.isEmpty) return '';

    final idx = extinf.lastIndexOf(',');
    if (idx == -1) return '';

    // idx peut être égal à extinf.length - 1 (virgule en fin de chaîne)
    // substring(idx+1) est alors autorisé et retourne une chaîne vide
    try {
      final name = extinf.substring(idx + 1).trim();
      return name.isNotEmpty ? name : '';
    } catch (_) {
      return '';
    }
  }

  // [PERF] RegExp compilées une seule fois — évite 150k+ compilations sur grosse M3U
  // Note : on utilise des strings normales (pas raw r'') car \' ne s'échappe pas en raw.
  static final _reLogo  = RegExp('tvg-logo=["\']([^"\']*)["\']');
  static final _reGroup = RegExp('group-title=["\']([^"\']*)["\']');
  static final _reTvgId = RegExp('tvg-id=["\']([^"\']*)["\']');

  static String? _extractAttr(String line, String attr) {
    final re = attr == 'tvg-logo'    ? _reLogo
             : attr == 'group-title' ? _reGroup
             : attr == 'tvg-id'      ? _reTvgId
             : RegExp('$attr=["\']([^"\']*)["\']');
    return re.firstMatch(line)?.group(1);
  }

  static String _getExtension(String url) {
    final path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    if (path.endsWith('.m3u8')) return 'm3u8';
    if (path.endsWith('.mp4'))  return 'mp4';
    if (path.endsWith('.mkv'))  return 'mkv';
    if (path.endsWith('.avi'))  return 'avi';
    if (path.endsWith('.ts'))   return 'ts';
    return 'ts';
  }
}

class M3uParseResult {
  final List<Channel>  channels;
  final List<Category> categories;
  M3uParseResult({required this.channels, required this.categories});
}