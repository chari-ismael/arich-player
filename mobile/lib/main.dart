// lib/main.dart
// ARICH Player v2.1.0
// ─────────────────────────────────────────────────────────────────────────────
// Tizen v2 :
//   • Init image cache uniquement sur Android (Tizen RAM limitée)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/iptv_provider.dart';
import 'providers/language_provider.dart';
import 'providers/mini_player_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/license_provider.dart';
import 'services/download_service.dart';
import 'services/device_service.dart';
import 'services/tmdb_service.dart';
import 'ui/screens/splash_screen.dart';
import 'core/tv_layout.dart';
import 'core/tizen_key_mapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
const String kAppVersion = '2.1.0';
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

// Détection Tizen centralisée (évite Platform.operatingSystem partout)
bool get _isTizen =>
    !kIsWeb && Platform.operatingSystem == 'tizen';

// ─────────────────────────────────────────────────────────────────────────────
final _downloadService = DownloadService();

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _initSystemUI();
      await _runApp();
    },
    (error, stack) => debugPrint('🔴 [CRASH] Unhandled: $error\n$stack'),
  );
}

Future<void> _runApp() async {
  // Cache image : taille réduite sur Tizen (RAM ~1.5GB partagée)
  if (!kIsWeb) {
    _configureImageCache();
  }

  await Future.wait([
    _initStorage(),
    _initSupabase(),
  ], eagerError: true);

  // Deep links OAuth — non supporté sur Tizen (pas de navigateur externe)
  if (!kIsWeb && !_isTizen) {
    await _initDeepLinks();
  }

  unawaited(_initAsyncServices());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => IptvProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => MiniPlayerProvider()),
        ChangeNotifierProvider<DownloadService>.value(value: _downloadService),
      ],
      child: const ArichIptvApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DEEP LINKS — Android uniquement (app_links non compatible Tizen)
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _initDeepLinks() async {
  final appLinks = AppLinks();

  try {
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      debugPrint('[OAuth] Cold start deep link: $initialUri');
      await _handleDeepLink(initialUri);
    }
  } catch (e) {
    debugPrint('[OAuth] getInitialLink error: $e');
  }

  appLinks.uriLinkStream.listen(
    (uri) {
      debugPrint('[OAuth] Warm start deep link: $uri');
      _handleDeepLink(uri);
    },
    onError: (e) => debugPrint('[OAuth] uriLinkStream error: $e'),
  );
}

Future<void> _handleDeepLink(Uri uri) async {
  debugPrint('[OAuth] Deep link reçu: $uri');
  
  if (!uri.toString().contains('com.arich.iptv')) {
    debugPrint('[OAuth] Deep link ignoré (pas com.arich.iptv)');
    return;
  }
  
  try {
    debugPrint('[OAuth] Traitement du deep link...');
    await Supabase.instance.client.auth.getSessionFromUrl(uri);
    debugPrint('[OAuth] Session créée depuis deep link ');
    
    // [NEW] Vérifier que la session est bien établie
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      debugPrint('[OAuth]  currentSession valide: ${session.user.email}');
      
      // Notifier l'auth screen que la session est prête
      if (globalNavigatorKey.currentContext != null) {
        ScaffoldMessenger.of(globalNavigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Connexion Google réussie !', style: GoogleFonts.poppins()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      debugPrint('[OAuth]  currentSession est NULL après getSessionFromUrl');
      
      // Attendre un peu et revérifier
      await Future.delayed(const Duration(seconds: 2));
      final retrySession = Supabase.instance.client.auth.currentSession;
      if (retrySession != null) {
        debugPrint('[OAuth]  Session trouvée après délai: ${retrySession.user.email}');
      } else {
        debugPrint('[OAuth]  Aucune session même après délai');
      }
    }
  } catch (e) {
    if (e.toString().contains('flow_state_not_found') ||
        e.toString().contains('code verifier')) {
      debugPrint('[OAuth] flow_state déjà consommé — session probablement OK');
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        debugPrint('[OAuth] Aucune session après flow_state_not_found');
      } else {
        debugPrint('[OAuth]  Session valide malgré flow_state_not_found: ${session.user.email}');
      }
    } else {
      debugPrint('[OAuth] getSessionFromUrl error: $e');
      
      // Afficher l'erreur à l'utilisateur
      if (globalNavigatorKey.currentContext != null) {
        ScaffoldMessenger.of(globalNavigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Erreur de connexion Google: ${e.toString()}', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM UI
// ─────────────────────────────────────────────────────────────────────────────
void _initSystemUI() {
  // Tizen : fullscreen immersif, pas d'edge-to-edge Android
  if (!kIsWeb && Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Orientation :
  //   Tizen TV → toujours paysage (pas de portrait sur une TV)
  //   Android  → portrait + paysage
  if (!kIsWeb) {
    if (_isTizen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE CACHE
// ─────────────────────────────────────────────────────────────────────────────
void _configureImageCache() {
  if (_isTizen) {
    // Tizen : RAM partagée avec le système TV → cache conservateur
    // Samsung TV 2019+ : ~1.5GB RAM, système prend ~800MB
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
    PaintingBinding.instance.imageCache.maximumSize = 200;
  } else {
    // Android : plus de RAM disponible
    PaintingBinding.instance.imageCache.maximumSizeBytes = 150 * 1024 * 1024; // 150MB
    PaintingBinding.instance.imageCache.maximumSize = 500;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STORAGE — Hive
// path_provider_tizen fournit automatiquement un chemin valide sur Tizen.
// Pas besoin de chemin custom — Hive.initFlutter() appelle path_provider.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _initStorage() async {
  try {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('favorites'),
    ]);
    debugPrint('[Storage] Hive initialisé ✓');
  } catch (e) {
    // Fallback : chemin temporaire si path_provider échoue sur Tizen ancien
    debugPrint('[Storage] Hive init error: $e — fallback in-memory');
    // On continue sans crash : les boxes seront vides mais l'app tourne
  }

  try {
    await TmdbService.init();
  } catch (e) {
    debugPrint('[Storage] TmdbService init error: $e');
  }

  try {
    await _downloadService.init();
  } catch (e) {
    debugPrint('[Storage] DownloadService init error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPABASE
// Sur Tizen : authFlowType.pkce fonctionne mais sans deep link pour le callback.
// L'auth se fait via QR code (tv_qr_login_service.dart) ou code manuel.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _initSupabase() async {
  await Supabase.initialize(
    url: 'https://aynucieohuowgkwyftiy.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF5bnVjaWVvaHVvd2drd3lmdGl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIyOTIxMDMsImV4cCI6MjA4Nzg2ODEwM30.H43CVcyzEuYBQfBIlkn16r5uk768isHr4DeLduo1ETk',
    authOptions: FlutterAuthClientOptions(
      // PKCE sur Android (avec deep link), implicit sur Tizen (pas de redirect)
      authFlowType: _isTizen ? AuthFlowType.implicit : AuthFlowType.pkce,
    ),
  );

  debugPrint('[Supabase] Initialisé ✓ — flow: ${_isTizen ? "implicit" : "pkce"}');
}

// ─────────────────────────────────────────────────────────────────────────────
// ASYNC SERVICES
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _initAsyncServices() async {
  // MediaKit : uniquement Android/Desktop (Tizen utilise TizenVideoPlayer)
  if (!kIsWeb && !_isTizen) {
    try {
      MediaKit.ensureInitialized();
      debugPrint('[MediaKit] Initialisé ✓');
    } catch (e) {
      debugPrint('[MediaKit] Init error: $e');
    }
  } else if (_isTizen) {
    debugPrint('[Player] Tizen → TizenVideoPlayer (video_player_tizen)');
  }

  // TVDetector — détecte Tizen TV + résolution 4K
  await TVDetector().init();
  debugPrint('[TVDetector] isTV=${TVDetector().isTV} isTizen=${TVDetector().isTizen} is4K=${TVDetector().is4K}');

  // TizenKeyMapper — écoute les touches télécommande Samsung
  // Init après TVDetector pour que isTizen soit connu
  if (TVDetector().isTizen) {
    TizenKeyMapper.instance.init();
    debugPrint('[TizenKeyMapper] Initialized ✓');
  }

  // DeviceService — tracking device (non bloquant)
  DeviceService.getOrCreate().catchError((e) =>
      debugPrint('[main] DeviceService: $e'));

  _trackAppLaunch();
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACKING
// ─────────────────────────────────────────────────────────────────────────────
void _trackAppLaunch() {
  try {
    final box = Hive.box('settings');
    final alreadyTracked =
        box.get('tracked_first_launch', defaultValue: false) as bool;

    final supabase = Supabase.instance.client;
    final now = DateTime.now().toIso8601String();
    final platform = _getPlatform();

    if (!alreadyTracked) {
      supabase.from('app_installs').insert({
        'platform': platform,
        'installed_at': now,
        'app_version': kAppVersion,
      }).catchError((e) => debugPrint('[tracking] install error: $e'));

      box.put('tracked_first_launch', true);
      box.put('install_date', now);
    }

    unawaited(supabase.from('app_sessions').insert({
      'platform': platform,
      'opened_at': now,
      'app_version': kAppVersion,
    }).catchError((e) {
      if (e.toString().contains('PGRST204')) {
        debugPrint('[tracking] app_sessions schema incomplete → skipped');
      } else {
        debugPrint('[tracking] session error: $e');
      }
    }));
  } catch (e) {
    debugPrint('[tracking] error: $e');
  }
}

String _getPlatform() {
  if (kIsWeb) return 'web';
  try {
    if (Platform.operatingSystem == 'tizen') return 'tizen';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
  } catch (_) {}
  return 'unknown';
}

// ─────────────────────────────────────────────────────────────────────────────
// APP WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class ArichIptvApp extends StatelessWidget {
  const ArichIptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, langProvider, _) => Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          key: ValueKey(themeProvider.themeKey),
          navigatorKey: globalNavigatorKey,
          title: 'ARICH Player',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.themeData,
          // Sur Tizen : désactiver le scroll physics qui peut causer des lag
          scrollBehavior: _isTizen
              ? const _TizenScrollBehavior()
              : const MaterialScrollBehavior(),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIZEN SCROLL BEHAVIOR
// Sur Samsung TV, le scroll doit répondre aux touches D-pad uniquement.
// On désactive les effets d'overscroll qui causent des jank.
// ─────────────────────────────────────────────────────────────────────────────
class _TizenScrollBehavior extends MaterialScrollBehavior {
  const _TizenScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    // Pas d'overscroll glow sur TV — chaque frame compte
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // ClampingScrollPhysics = pas de bounce, plus responsive aux touches TV
    return const ClampingScrollPhysics();
  }
}

// fin main.dart