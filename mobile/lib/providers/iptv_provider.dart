// lib/providers/iptv_provider.dart
//
// ARICH Player — IptvProvider v4.2
// [FIX-CRASH] _pendingTab : file d'attente pour les appels loadTabContent concurrents
//   (plus de retour silencieux avec filteredContent de l'ancien onglet)
// [PERF]  Suppression délai 1s inutile dans _prefetchInBackground
//
// [FIX v4.1] _loadSavedCredentials() vérifie la session Supabase AVANT
//   de charger les credentials IPTV. Sans ça, les chaînes et playlists
//   s'affichaient même quand l'utilisateur n'était pas authentifié sur Arich.
//
// RÈGLE : l'utilisateur doit d'abord avoir un compte Arich (Supabase) VALIDE
//   pour pouvoir accéder à ses playlists IPTV.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/xtream_api.dart';
import '../services/m3u_parser_simple.dart';
import '../services/dead_stream_checker.dart';
import '../models/channel.dart';
import '../models/category.dart';
import '../core/user_storage.dart';
import 'dart:developer' as dev;

// ── Modèles ───────────────────────────────────────────────────────────────────

class SearchResult {
  final Channel channel;
  final int tabIndex;
  const SearchResult({required this.channel, required this.tabIndex});
  String get typeLabel {
    if (tabIndex == 1) return 'DIRECT';
    if (tabIndex == 2) return 'FILM';
    return 'SÉRIE';
  }
}

class HistoryEntry {
  final String streamUrl;
  final String title;
  final String streamIcon;
  final int tabIndex;
  final int streamId;
  final DateTime watchedAt;
  final int positionSeconds;
  final int totalDurationSeconds;

  const HistoryEntry({
    required this.streamUrl, required this.title, required this.streamIcon,
    required this.tabIndex, required this.streamId, required this.watchedAt,
    this.positionSeconds = 0, this.totalDurationSeconds = 0,
  });

  double get progressRatio {
    if (totalDurationSeconds <= 0 || tabIndex == 1) return 0;
    return (positionSeconds / totalDurationSeconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() => {
    'streamUrl': streamUrl, 'title': title, 'streamIcon': streamIcon,
    'tabIndex': tabIndex, 'streamId': streamId,
    'watchedAt': watchedAt.millisecondsSinceEpoch,
    'positionSeconds': positionSeconds, 'totalDurationSeconds': totalDurationSeconds,
  };

  factory HistoryEntry.fromMap(Map map) => HistoryEntry(
    streamUrl: map['streamUrl'] ?? '', title: map['title'] ?? '',
    streamIcon: map['streamIcon'] ?? '', tabIndex: map['tabIndex'] ?? 1,
    streamId: map['streamId'] ?? 0,
    watchedAt: DateTime.fromMillisecondsSinceEpoch(map['watchedAt'] ?? 0),
    positionSeconds: map['positionSeconds'] ?? 0,
    totalDurationSeconds: map['totalDurationSeconds'] ?? 0,
  );

  HistoryEntry copyWith({int? positionSeconds, int? totalDurationSeconds, DateTime? watchedAt}) =>
      HistoryEntry(
        streamUrl: streamUrl, title: title, streamIcon: streamIcon,
        tabIndex: tabIndex, streamId: streamId,
        watchedAt: watchedAt ?? this.watchedAt,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      );
}

class FavoriteEntry {
  final int streamId;
  final int tabIndex;
  final String title;
  final String streamIcon;
  final String streamUrl;
  final String containerExtension;
  final DateTime addedAt;

  const FavoriteEntry({
    required this.streamId, required this.tabIndex, required this.title,
    required this.streamIcon, required this.streamUrl,
    required this.containerExtension, required this.addedAt,
  });

  Map<String, dynamic> toMap() => {
    'streamId': streamId, 'tabIndex': tabIndex, 'title': title,
    'streamIcon': streamIcon, 'streamUrl': streamUrl,
    'containerExtension': containerExtension,
    'addedAt': addedAt.millisecondsSinceEpoch,
  };

  factory FavoriteEntry.fromMap(Map map) => FavoriteEntry(
    streamId: map['streamId'] ?? 0, tabIndex: map['tabIndex'] ?? 1,
    title: map['title'] ?? '', streamIcon: map['streamIcon'] ?? '',
    streamUrl: map['streamUrl'] ?? '',
    containerExtension: map['containerExtension'] ?? 'mp4',
    addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] ?? 0),
  );

  Channel toChannel() => Channel(
    streamId: streamId, name: title, streamIcon: streamIcon,
    categoryId: '0', containerExtension: containerExtension, streamUrl: streamUrl,
  );
}

enum SourceType { xtream, m3u, direct }

// ─────────────────────────────────────────────────────────────────────────────

// ── Exception interne : URL de type Xtream détectée dans _loadM3uContent ────
// Transportes les credentials extraits pour que loginM3u() et
// _loadSavedCredentials() puissent déclencher le fallback login() directement.
class _XtreamUrlDetectedException implements Exception {
  final String baseUrl;
  final String username;
  final String password;
  const _XtreamUrlDetectedException(this.baseUrl, this.username, this.password);
  @override
  String toString() => 'XtreamUrlDetected: $baseUrl / $username';
}

class IptvProvider with ChangeNotifier {
  final XtreamApi _api = XtreamApi();
  XtreamApi get api => _api;

  bool isAuthenticated = false;
  bool isLoading = false;
  bool isInitializing = true;
  String errorMessage = '';
  SourceType sourceType = SourceType.xtream;
  Map<String, dynamic> userInfo = {};

  List<Map<String, dynamic>> _liveCategories = [];
  List<Map<String, dynamic>> _vodCategories = [];
  List<Map<String, dynamic>> _seriesCategories = [];

  List<Channel> allLive = [];
  List<Channel> allMovies = [];
  List<Channel> allSeries = [];
  List<Channel> filteredContent = [];
  List<Map<String, dynamic>> categories = [];
  String selectedCategoryId = '0';
  int currentTab = 0;
  Map<String, dynamic> currentSeriesInfo = {};
  bool isLoadingSeriesInfo = false;

  // ── Masquage + ordre catégories ───────────────────────────────────────────
  Map<String, Set<String>> _hiddenCategories = {'live': {}, 'vod': {}, 'series': {}};
  Map<String, List<String>> _categoryOrder   = {'live': [], 'vod': [], 'series': []};

  // ── Recherche ─────────────────────────────────────────────────────────────
  bool isGlobalSearchActive = false;
  List<SearchResult> globalSearchResults = [];
  String currentSearchQuery = '';
  Timer? _searchDebounce;

  // ── Tri ───────────────────────────────────────────────────────────────────
  String _sortOrder = 'default';
  String get sortOrder => _sortOrder;

  // ── Historique + Favoris ──────────────────────────────────────────────────
  List<HistoryEntry> watchHistory = [];
  static const int _maxHistoryEntries = 50;
  List<FavoriteEntry> favorites = [];
  // [PERF] Set pour isFavorite O(1) au lieu de List.any() O(n)
  // Clé = "streamId_tabIndex"
  final Set<String> _favoriteKeys = {};

  // ── Getters API ───────────────────────────────────────────────────────────
  String get baseUrl    => _api.baseUrl;
  String get username   => _api.username;
  String get password   => _api.password;
  String get serverUrl  => _api.baseUrl;

  String get expirationDate {
    final ts = userInfo['exp_date'];
    if (ts == null) return 'Inconnu';
    final ms = (int.tryParse(ts.toString()) ?? 0) * 1000;
    if (ms == 0) return 'Inconnu';
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  String get maxConnections    => userInfo['max_connections']?.toString() ?? '—';
  String get activeConnections => userInfo['active_cons']?.toString() ?? '—';
  String get accountStatus     => userInfo['status']?.toString() ?? 'Active';

  // ─────────────────────────────────────────────────────────────────────────
  // INIT
  // [FIX v4.1] On vérifie la session Supabase AVANT de charger les credentials
  // IPTV. Si l'utilisateur n'est pas connecté à son compte Arich, on ne
  // charge rien — il doit d'abord s'authentifier via AuthScreen.
  // ─────────────────────────────────────────────────────────────────────────

  StreamSubscription<AuthState>? _authSub;

  IptvProvider() {
    _loadSavedCredentials();
    _listenAuthState();
  }

  // [FIX v4.3] Écoute les changements d'auth Supabase.
  // Si l'utilisateur se reconnecte (OAuth ou email) après un signOut,
  // on relance _loadSavedCredentials() pour recharger les credentials IPTV.
  void _listenAuthState() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (_disposed) return;
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.tokenRefreshed) {
        // Ne recharger que si pas encore authentifié IPTV
        // (évite un double chargement au démarrage normal)
        if (!isAuthenticated && !isInitializing) {
          dev.log('[Provider] Auth signedIn → reload IPTV credentials');
          _loadSavedCredentials();
        }
      } else if (state.event == AuthChangeEvent.signedOut) {
        // Nettoyage côté IPTV également au signOut
        if (isAuthenticated) logout();
      }
    });
  }

  /// Retourne true si la session Supabase est valide (non expirée)
  bool get _hasValidSupabaseSession {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return false;
      if (session.expiresAt == null) return false;
      return DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
          .isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadSavedCredentials() async {
    // [FIX] Gate : si pas de session Supabase valide, on n'auto-connecte rien.
    // L'utilisateur verra LoginScreen → il devra s'authentifier sur Arich,
    // PUIS ajouter/sélectionner une playlist IPTV.
    if (!_hasValidSupabaseSession) {
      dev.log('[Provider] Pas de session Supabase → pas d\'auto-login IPTV');
      isInitializing = false;
      _notify();
      return;
    }

    final box    = Hive.box('settings');
    final url    = box.get('server_url',  defaultValue: '') as String;
    final user   = box.get('username',    defaultValue: '') as String;
    final pass   = box.get('password',    defaultValue: '') as String;
    final srcStr = box.get('source_type', defaultValue: 'xtream') as String;

    if (srcStr == 'm3u') {
      final m3uUrl = box.get('m3u_url', defaultValue: '') as String;
      if (m3uUrl.isNotEmpty) {
        // [FIX-v13] _loadM3uContent lève _XtreamUrlDetectedException si l'URL
        // contient username+password → on attrape ça et on bascule sur login().
        try {
          final key = UserStorage.accountKey(
            sourceType: 'm3u', identifier: m3uUrl.hashCode.toString());
          await UserStorage.openForAccount(key);
          _loadUserData();
          await _loadM3uContent(m3uUrl);
          isAuthenticated = true;
          sourceType = SourceType.m3u;
        } on _XtreamUrlDetectedException catch (ex) {
          dev.log('[Provider] _loadSavedCredentials: Xtream URL → base=${ex.baseUrl}');
          await login(ex.baseUrl, ex.username, ex.password, fromSavedCredentials: true);
        } catch (e) {
          dev.log('[Provider] M3U auto-login failed: $e');
        }
      }
    } else if (url.isNotEmpty && user.isNotEmpty) {
      await login(url, user, pass, fromSavedCredentials: true);
    }

    isInitializing = false;
    _notify();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIN
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> login(
    String url,
    String user,
    String pass, {
    bool fromSavedCredentials = false,
  }) async {
    isLoading = true;
    errorMessage = '';
    _notify();

    final parsed = Uri.tryParse(url.trim());
    if (parsed == null ||
        parsed.host.isEmpty ||
        !SimpleM3uParser.isValidUrl(parsed)) {
      errorMessage =
          'URL serveur invalide. Exemple : http://serveur.com:8080\n'
          '(domaine ou IP requis — pas seulement des paramètres après http://)';
      isLoading = false;
      _notify();
      return false;
    }

    // Test des ports alternatifs pour Vortex8k
    // [FIX] Construire les URLs de test sans dupliquer le port existant
    final parsedForPort = Uri.tryParse(url);
    final baseHost = (parsedForPort != null && parsedForPort.hasPort)
        ? '${parsedForPort.scheme}://${parsedForPort.host}'  // retirer port existant
        : url;
    final List<String> urlsToTest = [
      url,                       // URL originale telle quelle
      '$baseHost:8080',         // Port 8080
      '$baseHost:25461',        // Port 25461 (Vortex8k)
      '$baseHost:443',          // Port HTTPS
      '$baseHost:80',           // Port HTTP explicite
    ].toSet().toList();          // dédupliquer si url == baseHost:80
    
    Map<String, dynamic>? result;
    for (String testUrl in urlsToTest) {
      dev.log('[Provider] Test Xtream: $testUrl');
      _api.setCredentials(testUrl, user, pass);
      final res = await _api.authenticateWithInfo();
      if (res != null) {
        dev.log('[Provider] Succes avec: $testUrl');
        url = testUrl;
        result = res; // [FIX] on utilise ce result directement, pas de 2e appel
        break;
      }
    }

    if (result != null) {
      isAuthenticated = true;
      userInfo = result;
      sourceType = SourceType.xtream;

      final box = Hive.box('settings');
      box.putAll({
        'server_url': url, 'username': user,
        'password': pass, 'source_type': 'xtream',
      });

      final uri = Uri.tryParse(url);
      final key = UserStorage.accountKey(
        sourceType: 'xtream',
        identifier: user,
        serverHost: uri?.host ?? url,
      );
      await UserStorage.openForAccount(key);
      _loadUserData();

      try {
        await loadTabContent(1);
      } catch (e) {
        // [FIX-CRASH] loadTabContent ne doit jamais faire échouer le login.
        // Le RangeError sur les catégories vides est silencieux ici.
        dev.log('[Provider] login: loadTabContent(1) error (non bloquant): $e');
      }
      // isLoading est remis à false par loadTabContent — on s'assure qu'il l'est.
      isLoading = false;
      _prefetchInBackground();
    } else {
      isAuthenticated = false;
      final raw = _api.lastRawResponse;
      if (raw == 'HTML_RESPONSE') {
        errorMessage = "Ce serveur n'est pas compatible Xtream Codes.\n"
            "👉 Utilisez l'onglet M3U URL avec votre lien de playlist complet.";
      } else if (raw == 'TIMEOUT') {
        errorMessage = "Délai dépassé — le serveur ne répond pas.\n"
            "Vérifiez votre connexion ou essayez avec un VPN/sans VPN.";
      } else if (raw.isNotEmpty) {
        errorMessage = "Connexion échouée — réponse serveur :\n$raw";
      } else {
        errorMessage = "Connexion échouée.\n"
            "Vérifiez l'URL, le port et vos identifiants.";
      }
      isLoading = false;
      _notify();
    }

    return isAuthenticated;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // M3U
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> loginM3u(String url) async {
    // 1. Validation de base
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      errorMessage = 'URL vide';
      return false;
    }

    // 2. Validation URI
    Uri? uri;
    try {
      uri = Uri.parse(trimmedUrl);
    } catch (e) {
      errorMessage = 'URL invalide : ${e.toString()}';
      return false;
    }

    if (uri.host.isEmpty) {
      errorMessage = 'URL invalide : h\u00f4te manquant';
      return false;
    }
    if (!SimpleM3uParser.isValidUrl(uri)) {
      errorMessage =
          "URL invalide : il manque le domaine ou l'adresse du serveur.\n"
          "Collez l'URL compl\u00e8te, par ex. :\n"
          'http://serveur.com:8080/get.php?username=\u2026&password=\u2026&type=m3u_plus&output=m3u8';
      return false;
    }

    // [FIX-v13] isLoading = true ici — manquant dans les versions précédentes.
    // Sans ça, l'UI ne montrait pas le spinner pendant la tentative M3U
    // ET pendant le fallback Xtream. De plus, loginM3u() peut maintenant
    // être appelé sans que isLoading soit positionné par l'appelant.
    isLoading = true;
    errorMessage = '';
    _notify();

    // [FIX-XTREAM-DETECT] Tenter d'abord le chargement M3U direct.
    // Si ça échoue et que l'URL contient username/password, basculer
    // automatiquement sur l'API Xtream Codes (/player_api.php).
    // Cas typique : serveur qui bloque /get.php (HTTP 885) mais répond
    // sur /player_api.php avec UA ktor-client.
    try {
      await _loadM3uContent(url);
      isAuthenticated = true;
      sourceType = SourceType.m3u;
      Hive.box('settings').putAll({'m3u_url': url, 'source_type': 'm3u'});
      isLoading = false;
      _notify();
      return true;
    } catch (e, stack) {
      dev.log('[Provider] loginM3u: M3U échoué — $e');

      // [FIX-v13] Cas 1 : _loadM3uContent a détecté une URL Xtream et lancé
      // _XtreamUrlDetectedException — on utilise directement les credentials extraits.
      if (e is _XtreamUrlDetectedException) {
        dev.log('[Provider] loginM3u: XtreamUrlDetected → base=${e.baseUrl} user=${e.username}');
        isLoading = false;
        final ok = await login(e.baseUrl, e.username, e.password);
        dev.log('[Provider] loginM3u: login() résultat → ok=$ok');
        return ok;
      }

      // [FIX-v13] Cas 2 : Tous les UA M3U ont échoué (HTTP 885).
      // On tente quand même le fallback Xtream si l'URL contient username+password.
      final xtream = _tryExtractXtreamFromM3uUrl(url);
      if (xtream != null) {
        dev.log('[Provider] loginM3u: Fallback Xtream → base=${xtream.$1} user=${xtream.$2}');
        isLoading = false;
        final ok = await login(xtream.$1, xtream.$2, xtream.$3);
        dev.log('[Provider] loginM3u: Fallback Xtream résultat → ok=$ok');
        return ok;
      }

      // Pas de credentials Xtream — erreur M3U classique
      dev.log("[Provider] loginM3u: Aucun fallback possible");
      isAuthenticated = false;
      errorMessage = 'Impossible de charger la playlist :\n${e.toString()}';
      isLoading = false;
      _notify();
      return false;
    }
  }

  (String, String, String)? _tryExtractXtreamFromM3uUrl(String url) {
    try {
      final uri  = Uri.parse(url.trim());
      final user = uri.queryParameters['username'] ?? '';
      final pass = uri.queryParameters['password'] ?? '';
      if (user.isEmpty || pass.isEmpty) return null;

      // Construire l'URL de base proprement :
      // - ne pas inclure le port si c'est le port standard (80/443) ou si == 0
      // - Uri(port: null) lève une exception dans certaines versions de Dart,
      //   on construit donc la string manuellement.
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final host   = uri.host;
      final port   = uri.hasPort &&
          uri.port != 80  &&
          uri.port != 443 &&
          uri.port != 0
          ? uri.port
          : null;

      final baseUrl = port != null
          ? '$scheme://$host:$port'
          : '$scheme://$host';

      dev.log('[Provider] Xtream extrait → base=$baseUrl user=$user');
      return (baseUrl, user, pass);
    } catch (e, stack) {
      dev.log('[Provider] _tryExtract error: $e\n$stack');
      return null;
    }
  }

  Future<void> _loadM3uContent(String url) async {
    // [FIX-v13] Si l'URL contient username+password (format Xtream dans M3U),
    // on tente DIRECTEMENT /player_api.php avec ktor-client avant de perdre
    // du temps sur la rotation M3U. Le résultat est lancé comme exception
    // spéciale pour que loginM3u() / _loadSavedCredentials() basculent sur login().
    final xtreamCreds = _tryExtractXtreamFromM3uUrl(url);
    if (xtreamCreds != null) {
      dev.log('[Provider] _loadM3uContent: URL Xtream détectée → bypass M3U direct');
      throw _XtreamUrlDetectedException(xtreamCreds.$1, xtreamCreds.$2, xtreamCreds.$3);
    }

    // [v12] Appel direct — la rotation UA est gérée dans SimpleM3uParser.
    final result = await SimpleM3uParser.parseFromUrl(url);

    // [FIX 3] Convertir List<M3uChannel> → List<Channel>
    int autoId = 1;
    allLive = result.channels.map((m) => Channel(
      streamId:           autoId++,
      name:               m.name,
      streamIcon:         m.logo,
      categoryId:         m.category,
      containerExtension: 'ts',
      streamUrl:          m.url,
      tvgId:              m.tvgId,
      groupTitle:         m.category,
    )).toList();

    // [FIX M3U-CAT] Peupler _liveCategories pour que loadTabContent M3U les expose
    _liveCategories = result.categories
        .map((c) => {'id': c.categoryId, 'name': c.categoryName})
        .toList();
    categories = List<Map<String, dynamic>>.from(_liveCategories);
    allMovies = [];
    allSeries = [];
    filteredContent = List<Channel>.from(allLive);
    dev.log('[M3U] _loadM3uContent: ${allLive.length} chaines, ${categories.length} categories');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PREFETCH
  // ─────────────────────────────────────────────────────────────────────────

  // [FIX-CRASH] Lock anti-double-prefetch
  bool _isPrefetching = false;

  /// Appelé par HomeScreen après que le Live est chargé et l'UI responsive.
  /// Lance le prefetch Films+Séries en arrière-plan sans bloquer l'interface.
  void prefetchMoviesAndSeries() => _prefetchInBackground();

  // [FIX-v13] isPrefetchingContent exposé publiquement pour que HomeScreen
  // affiche un indicateur de chargement pendant le prefetch films/séries.
  bool get isPrefetchingContent => _isPrefetching;

  void _prefetchInBackground() {
    if (_isPrefetching || _disposed) return;
    _isPrefetching = true;
    _notify(); // [FIX-v13] Notifier immédiatement → HomeScreen affiche le spinner

    Future(() async {
      try {
        dev.log('[Provider] Préchargement films + séries en parallèle...');

        // [FIX-v13] Films ET séries lancés en parallèle — réduit le temps
        // d'attente de 2x le temps réseau à 1x le temps réseau.
        // Chaque résultat notifie l'UI dès qu'il arrive via unawaited futures.
        final moviesNeeded = allMovies.isEmpty;
        final seriesNeeded = allSeries.isEmpty;

        if (!moviesNeeded && !seriesNeeded) {
          _isPrefetching = false;
          _notify();
          return;
        }

        // Lancer les deux en parallèle
        final futures = <Future>[];
        if (moviesNeeded) {
          futures.add(Future(() async {
            try {
              final results = await Future.wait([
                _api.getStreams('get_vod_streams'),
                _api.getCategories('get_vod_categories'),
              ]);
              if (!_disposed) {
                allMovies      = results[0] as List<Channel>;
                _vodCategories = results[1] as List<Map<String, dynamic>>;
                dev.log('[Provider] Films préchargés: ${allMovies.length}');
                _notify(); // UI affiche les films dès qu'ils arrivent
              }
            } catch (e) { dev.log('[Provider] Préchargement films échoué: $e'); }
          }));
        }
        if (seriesNeeded) {
          futures.add(Future(() async {
            try {
              final results = await Future.wait([
                _api.getStreams('get_series'),
                _api.getCategories('get_series_categories'),
              ]);
              if (!_disposed) {
                allSeries         = results[0] as List<Channel>;
                _seriesCategories = results[1] as List<Map<String, dynamic>>;
                dev.log('[Provider] Séries préchargées: ${allSeries.length}');
                _notify(); // UI affiche les séries dès qu'elles arrivent
              }
            } catch (e) { dev.log('[Provider] Préchargement séries échoué: $e'); }
          }));
        }

        await Future.wait(futures);

      } finally {
        _isPrefetching = false;
        if (!_disposed) _notify(); // Spinner disparaît
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTENU ONGLETS
  // ─────────────────────────────────────────────────────────────────────────

  // [FIX-CRASH] Guard contre les appels concurrents à loadTabContent.
  // _pendingTab : si un appel arrive pendant un chargement, on le met en file.
  // À la fin du chargement en cours, on re-déclenche automatiquement.
  bool _isLoadingTab = false;
  int? _pendingTab;

  Future<void> loadTabContent(int index) async {
    // [FIX-CRASH] Éviter les appels concurrents — mécanisme pending.
    if (_isLoadingTab) {
      _pendingTab = index;
      currentTab = index;
      _notify();
      return;
    }
    _pendingTab = null;
    _isLoadingTab = true;
    currentTab = index;

    // [FIX M3U] En mode M3U les données sont déjà chargées via _loadM3uContent.
    // Ne PAS appeler _api.getStreams() (Xtream) qui écraserait allLive avec [].
    if (sourceType == SourceType.m3u) {
      selectedCategoryId = '0';
      isGlobalSearchActive = false;
      globalSearchResults = [];
      currentSearchQuery = '';
      if (index <= 1) {
        filteredContent = List<Channel>.from(allLive);
      } else if (index == 2) {
        filteredContent = List<Channel>.from(allMovies);
      } else {
        filteredContent = List<Channel>.from(allSeries);
      }
      isLoading = false;
      _isLoadingTab = false;
      _applySort();
      _notify();
      if (_pendingTab != null && _pendingTab != index) {
        final next = _pendingTab!;
        _pendingTab = null;
        loadTabContent(next);
      }
      return;
    }
    // [FIX-ANR] Ne pas déclencher isLoading si les données sont déjà en cache.
    // Évite un rebuild inutile au retour de navigation sur un onglet déjà chargé.
    final alreadyCached = (index == 1 && allLive.isNotEmpty)
        || (index == 2 && allMovies.isNotEmpty)
        || (index == 3 && allSeries.isNotEmpty);

    if (!alreadyCached) {
      isLoading = true;
      errorMessage = '';
      _notify();
    }

    selectedCategoryId = '0';
    isGlobalSearchActive = false;
    globalSearchResults = [];
    currentSearchQuery = '';

    try {
      if (index == 0) {
        if (allLive.isEmpty) allLive = await _api.getStreams('get_live_streams');
        filteredContent = List<Channel>.from(allLive);
        _refreshUserInfo();
      } else if (index == 1) {
        final r = await Future.wait([
          allLive.isEmpty ? _api.getStreams('get_live_streams') : Future.value(allLive),
          _liveCategories.isEmpty
              ? _api.getCategories('get_live_categories')
              : Future.value(_liveCategories),
        ]);
        allLive = r[0] as List<Channel>;
        _liveCategories = r[1] as List<Map<String, dynamic>>;
        categories = _buildSortedCategories(_liveCategories, 'live');
        filteredContent = List<Channel>.from(allLive);
      } else if (index == 2) {
        final r = await Future.wait([
          allMovies.isEmpty ? _api.getStreams('get_vod_streams') : Future.value(allMovies),
          _vodCategories.isEmpty
              ? _api.getCategories('get_vod_categories')
              : Future.value(_vodCategories),
        ]);
        allMovies = r[0] as List<Channel>;
        _vodCategories = r[1] as List<Map<String, dynamic>>;
        categories = _buildSortedCategories(_vodCategories, 'vod');
        filteredContent = List<Channel>.from(allMovies);
      } else if (index == 3) {
        final r = await Future.wait([
          allSeries.isEmpty ? _api.getStreams('get_series') : Future.value(allSeries),
          _seriesCategories.isEmpty
              ? _api.getCategories('get_series_categories')
              : Future.value(_seriesCategories),
        ]);
        allSeries = r[0] as List<Channel>;
        _seriesCategories = r[1] as List<Map<String, dynamic>>;
        categories = _buildSortedCategories(_seriesCategories, 'series');
        filteredContent = List<Channel>.from(allSeries);
      }
    } catch (e, stack) {
      errorMessage = 'Erreur : $e';
      dev.log('[Provider] EXCEPTION loadTabContent($index): $e\n$stack');
    }

    isLoading = false;
    _isLoadingTab = false;
    _applySort();
    _notify();
    // [FIX-CRASH] Re-déclencher si un tab a été demandé pendant le chargement
    if (_pendingTab != null && _pendingTab != index) {
      final next = _pendingTab!;
      _pendingTab = null;
      loadTabContent(next);
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      final info = await _api.getUserInfo();
      if (info.isNotEmpty && info.toString() != userInfo.toString()) {
        // [PERF] Notifier seulement si les données ont changé
        userInfo = info;
        _notify();
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MASQUAGE CATÉGORIES
  // ─────────────────────────────────────────────────────────────────────────

  String _tabKey(int tabIndex) {
    if (tabIndex == 1) return 'live';
    if (tabIndex == 2) return 'vod';
    return 'series';
  }
  String _currentTabKey() => _tabKey(currentTab);

  bool isCategoryHidden(String categoryId, {int? tabIndex}) {
    final key = tabIndex != null ? _tabKey(tabIndex) : _currentTabKey();
    return _hiddenCategories[key]?.contains(categoryId) ?? false;
  }

  void toggleCategoryVisibility(String categoryId, {int? tabIndex}) {
    final key = tabIndex != null ? _tabKey(tabIndex) : _currentTabKey();
    final set = _hiddenCategories[key] ??= {};
    if (set.contains(categoryId)) set.remove(categoryId); else set.add(categoryId);
    _saveHiddenCategories();
    _rebuildCategories();
    _notify();
  }

  void _rebuildCategories() {
    if (currentTab == 1)      categories = _buildSortedCategories(_liveCategories,   'live');
    else if (currentTab == 2) categories = _buildSortedCategories(_vodCategories,    'vod');
    else if (currentTab == 3) categories = _buildSortedCategories(_seriesCategories, 'series');
  }

  List<Map<String, dynamic>> getAllCategories({required int tabIndex}) {
    if (tabIndex == 1) return _liveCategories;
    if (tabIndex == 2) return _vodCategories;
    return _seriesCategories;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ORDRE CATÉGORIES
  // ─────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _buildSortedCategories(
    List<Map<String, dynamic>> source,
    String key,
  ) {
    final hidden = _hiddenCategories[key] ?? {};
    final order  = _categoryOrder[key] ?? [];

    // [FIX-CRASH] Copie défensive : source peut être modifiée par le prefetch
    // concurrent pendant le sort → RangeError (end): Invalid value
    final visible = List<Map<String, dynamic>>.from(
      source.where((c) => !hidden.contains(_catId(c))),
    );

    if (order.isEmpty) return visible;

    // Snapshot de l'ordre pour éviter une modification pendant le sort
    final orderSnapshot = List<String>.from(order);
    visible.sort((a, b) {
      final idA = _catId(a);
      final idB = _catId(b);
      final posA = orderSnapshot.indexOf(idA);
      final posB = orderSnapshot.indexOf(idB);
      if (posA == -1 && posB == -1) return 0;
      if (posA == -1) return 1;
      if (posB == -1) return -1;
      return posA.compareTo(posB);
    });

    return visible;
  }

  String _catId(Map<String, dynamic> cat) =>
      cat['category_id']?.toString() ?? cat['id']?.toString() ?? '';

  List<Map<String, dynamic>> getCategoriesOrdered(int tabIndex) {
    if (tabIndex == 1) return _buildSortedCategories(_liveCategories, 'live');
    if (tabIndex == 2) return _buildSortedCategories(_vodCategories, 'vod');
    return _buildSortedCategories(_seriesCategories, 'series');
  }

  void saveCategoryOrder(int tabIndex, List<Map<String, dynamic>> orderedCats) {
    final ids = orderedCats.map(_catId).where((id) => id.isNotEmpty).toList();
    final key = _tabKey(tabIndex);
    _categoryOrder[key] = ids;
    _saveCategoryOrder();
    _rebuildCategories();
    _notify();
  }

  void reorderCategories(int tabIndex, List<String> newOrderIds) {
    final key = _tabKey(tabIndex);
    _categoryOrder[key] = newOrderIds;
    _saveCategoryOrder();
    _rebuildCategories();
    _notify();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERSISTANCE
  // ─────────────────────────────────────────────────────────────────────────

  void _loadUserData() {
    _loadHistory();
    _loadFavorites();
    _loadHiddenCategories();
    _loadCategoryOrder();
  }

  void _loadHiddenCategories() {
    try {
      for (final key in ['live', 'vod', 'series']) {
        final raw = UserStorage.get<List>('hidden_cat_$key', defaultValue: []);
        _hiddenCategories[key] = Set<String>.from(raw.map((e) => e.toString()));
      }
    } catch (e) { dev.log('[Provider] loadHiddenCategories error: $e'); }
  }

  void _saveHiddenCategories() {
    try {
      for (final key in ['live', 'vod', 'series']) {
        UserStorage.put('hidden_cat_$key', (_hiddenCategories[key] ?? {}).toList());
      }
    } catch (e) { dev.log('[Provider] saveHiddenCategories error: $e'); }
  }

  void _loadCategoryOrder() {
    try {
      for (final key in ['live', 'vod', 'series']) {
        final raw = UserStorage.get<List>('cat_order_$key', defaultValue: []);
        _categoryOrder[key] = List<String>.from(raw.map((e) => e.toString()));
      }
    } catch (e) { dev.log('[Provider] loadCategoryOrder error: $e'); }
  }

  void _saveCategoryOrder() {
    try {
      for (final key in ['live', 'vod', 'series']) {
        UserStorage.put('cat_order_$key', _categoryOrder[key] ?? []);
      }
    } catch (e) { dev.log('[Provider] saveCategoryOrder error: $e'); }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECHERCHE
  // ─────────────────────────────────────────────────────────────────────────

  void searchGlobal(String query) {
    currentSearchQuery = query;
    _searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      isGlobalSearchActive = false;
      globalSearchResults = [];
      _notify();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!isAuthenticated) return;
      isGlobalSearchActive = true;
      final q = query.toLowerCase();
      globalSearchResults = [
        ...allLive.where((c) => c.name.toLowerCase().contains(q)).take(30)
            .map((c) => SearchResult(channel: c, tabIndex: 1)),
        ...allMovies.where((c) => c.name.toLowerCase().contains(q)).take(30)
            .map((c) => SearchResult(channel: c, tabIndex: 2)),
        ...allSeries.where((c) => c.name.toLowerCase().contains(q)).take(30)
            .map((c) => SearchResult(channel: c, tabIndex: 3)),
      ];
      _notify();
    });
  }

  void search(String query) {
    filteredContent = query.isEmpty
        ? List<Channel>.from(_sourceForTab())
        : _sourceForTab()
            .where((item) => item.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
    _notify();
  }

  void filterByCategory(String catId) {
    if (selectedCategoryId == catId) return;
    selectedCategoryId = catId;
    filteredContent = catId == '0'
        ? List<Channel>.from(_sourceForTab())
        : _sourceForTab().where((item) => item.categoryId == catId).toList();
    _applySort();
    _notify();
  }

  List<Channel> _sourceForTab() {
    if (currentTab == 1) return allLive;
    if (currentTab == 2) return allMovies;
    return allSeries;
  }

  void setSortOrder(String order) {
    _sortOrder = order;
    _applySort();
    _notify();
  }

  void _applySort() {
    if (_sortOrder == 'az') {
      // [FIX-CRASH] Copie défensive : filteredContent peut être modifié par
      // _prefetchInBackground() concurrent → RangeError dans .sort() en place
      // "Not in inclusive range 0..13: 14"
      final copy = List<Channel>.from(filteredContent)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      filteredContent = copy;
    } else if (_sortOrder == 'za') {
      final copy = List<Channel>.from(filteredContent)
        ..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      filteredContent = copy;
    }
  }

  Future<void> fetchSeriesDetails(int seriesId) async {
    isLoadingSeriesInfo = true;
    currentSeriesInfo = {};
    _notify();
    currentSeriesInfo = await _api.getSeriesInfo(seriesId);
    isLoadingSeriesInfo = false;
    _notify();
  }

  void setCurrentTab(int index) { currentTab = index; }

  String getStreamUrl(Channel channel, {int? tabIndex}) {
    if (sourceType == SourceType.m3u && channel.streamUrl.isNotEmpty) {
      return channel.streamUrl;
    }
    final tab = tabIndex ?? currentTab;
    final id  = channel.streamId.toString();
    final ext = channel.containerExtension;
    if (tab == 1) return '$baseUrl/live/$username/$password/$id.ts';
    if (tab == 2) return '$baseUrl/movie/$username/$password/$id.$ext';
    return '';
  }

  String getEpisodeStreamUrl(Map<String, dynamic> episode) {
    final id  = episode['id'].toString();
    final ext = episode['container_extension']?.toString() ?? 'mp4';
    return '$baseUrl/series/$username/$password/$id.$ext';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORIQUE
  // ─────────────────────────────────────────────────────────────────────────

  void _loadHistory() {
    try {
      final raw = UserStorage.get<List>('watch_history', defaultValue: []);
      watchHistory = raw.whereType<Map>()
          .map((m) => HistoryEntry.fromMap(m))
          .toList()
        ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    } catch (e) {
      dev.log('[History] load error: $e');
      watchHistory = [];
    }
  }

  void _saveHistory() {
    try {
      UserStorage.put('watch_history', watchHistory.map((e) => e.toMap()).toList());
    } catch (e) { dev.log('[History] save error: $e'); }
  }

  void addToHistory({
    required String streamUrl, required String title,
    required String streamIcon, required int tabIndex, required int streamId,
  }) {
    watchHistory.removeWhere((e) => e.streamId == streamId && e.tabIndex == tabIndex);
    watchHistory.insert(0, HistoryEntry(
      streamUrl: streamUrl, title: title, streamIcon: streamIcon,
      tabIndex: tabIndex, streamId: streamId, watchedAt: DateTime.now(),
    ));
    if (watchHistory.length > _maxHistoryEntries) {
      watchHistory = watchHistory.take(_maxHistoryEntries).toList();
    }
    _saveHistory();
    _notify();
  }

  void updateHistoryPosition({
    required int streamId, required int tabIndex,
    required int positionSeconds, int totalDurationSeconds = 0,
  }) {
    if (tabIndex == 1) return;
    final idx = watchHistory.indexWhere(
        (e) => e.streamId == streamId && e.tabIndex == tabIndex);
    if (idx == -1) return;
    watchHistory[idx] = watchHistory[idx].copyWith(
      positionSeconds: positionSeconds,
      totalDurationSeconds: totalDurationSeconds,
      watchedAt: DateTime.now(),
    );
    // [PERF-ANR] Pas de _notify() ici — la position n'est pas affichée
    // en temps réel dans l'UI. Évite un rebuild complet à chaque update player.
    _saveHistory();
  }

  int getResumePosition(int streamId, int tabIndex) {
    try {
      return watchHistory
          .firstWhere((e) => e.streamId == streamId && e.tabIndex == tabIndex)
          .positionSeconds;
    } catch (_) { return 0; }
  }

  void clearHistory() {
    watchHistory = [];
    _saveHistory();
    _notify();
  }

  void removeFromHistory(int streamId, int tabIndex) {
    watchHistory.removeWhere((e) => e.streamId == streamId && e.tabIndex == tabIndex);
    _saveHistory();
    _notify();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FAVORIS
  // ─────────────────────────────────────────────────────────────────────────

  void _loadFavorites() {
    try {
      final raw = UserStorage.get<List>('favorites', defaultValue: []);
      favorites = raw.whereType<Map>()
          .map((m) => FavoriteEntry.fromMap(m))
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      // [PERF] Rebuild le Set O(1)
      _favoriteKeys
        ..clear()
        ..addAll(favorites.map((e) => '${e.streamId}_${e.tabIndex}'));

      // Démarrer le checker de streams morts sur les favoris LIVE
      DeadStreamChecker.start(
        getFavorites: () => favorites
            .where((f) => f.tabIndex == 1)
            .map((f) => {'streamUrl': f.streamUrl, 'tabIndex': f.tabIndex})
            .toList(),
      );
    } catch (e) {
      dev.log('[Favorites] load error: $e');
      favorites = [];
      _favoriteKeys.clear();
    }
  }

  void _saveFavorites() {
    try {
      UserStorage.put('favorites', favorites.map((e) => e.toMap()).toList());
    } catch (e) { dev.log('[Favorites] save error: $e'); }
  }

  // [PERF] O(1) au lieu de O(n) — appelé dans chaque itemBuilder de la grid
  bool isFavorite(int streamId, int tabIndex) =>
      _favoriteKeys.contains('${streamId}_$tabIndex');

  bool toggleFavorite(Channel channel, int tabIndex) {
    final alreadyFav = isFavorite(channel.streamId, tabIndex);
    final key = '${channel.streamId}_$tabIndex';
    if (alreadyFav) {
      favorites.removeWhere(
          (e) => e.streamId == channel.streamId && e.tabIndex == tabIndex);
      _favoriteKeys.remove(key);
    } else {
      favorites.insert(0, FavoriteEntry(
        streamId: channel.streamId, tabIndex: tabIndex, title: channel.name,
        streamIcon: channel.streamIcon,
        streamUrl: getStreamUrl(channel, tabIndex: tabIndex),
        containerExtension: channel.containerExtension,
        addedAt: DateTime.now(),
      ));
      _favoriteKeys.add(key);
    }
    _saveFavorites();
    _notify();
    return !alreadyFav;
  }

  void removeFavorite(int streamId, int tabIndex) {
    favorites.removeWhere((e) => e.streamId == streamId && e.tabIndex == tabIndex);
    _favoriteKeys.remove('${streamId}_$tabIndex');
    _saveFavorites();
    _notify();
  }

  void clearFavorites() {
    favorites = [];
    _favoriteKeys.clear();
    _saveFavorites();
    _notify();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGOUT
  // ─────────────────────────────────────────────────────────────────────────

  // [FIX-CRASH] Flag pour éviter notifyListeners() après dispose()
  // Protège les callbacks asynchrones tardifs (_prefetchInBackground,
  // _refreshUserInfo) qui peuvent arriver après que le provider est détruit.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _searchDebounce?.cancel();
    DeadStreamChecker.stop();
    _api.dispose(); // [PERF] Ferme le client HTTP
    super.dispose();
  }

  // Wrapper sécurisé — remplace tous les notifyListeners() directs
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> logout() async {
    _searchDebounce?.cancel();

    isAuthenticated = false;
    allLive = []; allMovies = []; allSeries = [];
    _liveCategories = []; _vodCategories = []; _seriesCategories = [];
    filteredContent = []; categories = []; currentSeriesInfo = {};
    errorMessage = ''; currentTab = 0;
    isGlobalSearchActive = false; globalSearchResults = []; currentSearchQuery = '';
    userInfo = {}; sourceType = SourceType.xtream;
    _hiddenCategories = {'live': {}, 'vod': {}, 'series': {}};
    _categoryOrder    = {'live': [], 'vod': [], 'series': []};
    selectedCategoryId = '0'; _sortOrder = 'default';
    watchHistory = []; favorites = []; _favoriteKeys.clear();
    // [FIX v4.3] Reset isInitializing pour que le prochain _loadSavedCredentials()
    // (déclenché par _listenAuthState au re-login) passe bien le gate isInitializing.
    isInitializing = false;
    // [FIX-CRASH] Reset des locks pour le prochain login
    _isLoadingTab = false;
    _isPrefetching = false;
    _pendingTab = null;

    _api.reset(); // [FIX-v13] Recrée le client HTTP — dispose() le ferme définitivement
    await UserStorage.closeCurrentBox();

    Hive.box('settings').deleteAll([
      'server_url', 'username', 'password', 'm3u_url', 'source_type',
    ]);

    _notify();
  }
}