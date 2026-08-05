// lib/ui/screens/splash_screen.dart
// ARICH Player — Splash Screen v5.3
// ─────────────────────────────────────────────────────────────────────────────
// v5.2 — Fix crash OAuth : navigation différée au retour au premier plan
//   • [FIX-OAUTH-4] WidgetsBindingObserver ajouté : _pendingOAuthNav stocke
//     la destination quand signedIn arrive en arrière-plan. Dès que
//     didChangeAppLifecycleState → resumed, _flushPendingNav() navigue.
//     Sans ce fix : _go() appelé pendant que l'écran Google est au premier plan
//     → Navigator.pushReplacement sur contexte invisible → crash silencieux
//     → "Lost connection to device".
//
// v5.1 — Fix reconnexion Google OAuth :
//   • [FIX-OAUTH-1] _navigateNext : suppression de la vérification expiresAt+5min
//     qui rejetait les sessions OAuth fraîches → remplacé par session != null
//   • [FIX-OAUTH-2] _startRealLoading : délai 800ms → 1800ms pour laisser
//     Supabase terminer le parsing du hash OAuth avant _navigateNext
//   • [FIX-OAUTH-3] onAuthStateChange écouté dès le splash (_authSub) :
//     si la session arrive pendant l'animation → navigation immédiate vers
//     HomeScreen sans attendre le délai. _authSub.cancel() dans dispose().
// ─────────────────────────────────────────────────────────────────────────────
//   • [DA]   Fond : mesh gradient animé 3 orbs + grain statique (CustomPainter)
//   • [DA]   Logo : ring double gradient + glow pulse + scale-in élastique
//   • [DA]   Titre : lettres staggerées avec reveal masque SlideTransition
//   • [DA]   Sous-titre : séparateurs animés + texte fade letterSpacing
//   • [DA]   Progress bar : track glass + fill gradient violet→rouge + dot pulsant
//   • [DA]   Badge version : glassmorphism pill top-right
//   • [DA]   Disclaimer dialog : redesigné glass premium + bouton gradient
//   • [PERF] 6 AnimationControllers, tous dispose() corrects
//   • [PERF] RepaintBoundary sur chaque CustomPainter
//   • [LOGIC] Flow navigation 100% identique à v4 (guard, Supabase, Hive)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../../services/device_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart' show OnboardingScreen, kOnboardingDone;
import 'setup_screen.dart' show SetupScreen, kSetupDone;
import 'profile_picker_screen.dart';
import 'lang_disclaimer_screen.dart' show LangDisclaimerScreen, kLangDisclaimerDone;
import '../../providers/profile_provider.dart';
import '../../providers/license_provider.dart';
import '../../ui/widgets/license_gate.dart';
import '../../main.dart' show kAppVersion;
import '../../services/app_update_service.dart';

// ─── Particle model ──────────────────────────────────────────────────────────
class _Particle {
  final double x, y, size, speed, angle, rotSpeed, opacity;
  final int type;
  final bool isViolet;
  const _Particle({
    required this.x, required this.y, required this.size, required this.speed,
    required this.angle, required this.rotSpeed, required this.type,
    required this.isViolet, required this.opacity,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Controllers ────────────────────────────────────────────────────────────
  late AnimationController _masterCtrl;   // orchestration globale 3.8s
  late AnimationController _orbCtrl;      // orbs fond — 7s repeat
  late AnimationController _pulseCtrl;    // pulse logo + scan — 2s repeat
  late AnimationController _glitchCtrl;   // glitch lettres — 60ms
  late AnimationController _particleCtrl; // particules — 6s repeat
  late AnimationController _loaderCtrl;   // loader spinner — 2s repeat

  // ── State ──────────────────────────────────────────────────────────────────
  bool   _showLoader     = false;
  int    _loadStep       = 0;
  bool   _animDone       = false;
  double _realProgress   = 0.0;
  bool   _navigationDone = false;

  // [FIX-OAUTH-4] Destination en attente quand signedIn arrive en arrière-plan.
  // Flush dès que l'app repasse au premier plan (resumed).
  Widget? _pendingOAuthNav;

  // [FIX OAUTH] Écoute la session Supabase pendant le splash.
  // Si Google OAuth redirige vers l'app et que la session est établie
  // AVANT que _navigateNext soit appelé, on navigue immédiatement vers HomeScreen
  // sans attendre le délai du splash.
  late final StreamSubscription<AuthState> _authSub;

  final List<_Particle> _particles = [];
  final math.Random _rng = math.Random(42);

  static const _letters = ['A','R','I','C','H',' ','P','L','A','Y','E','R'];
  static const _loadMessages = [
    'Chargement core...',
    'Connexion Supabase...',
    'Ressources TMDB...',
    'Prêt ✓',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // [FIX-OAUTH-4]
    _initParticles();
    _initControllers();
    _startAnimations();
    _startRealLoading();

    // [FIX OAUTH] Écouter onAuthStateChange dès le splash.
    // [FIX-OAUTH-4] Si l'app est en arrière-plan quand signedIn arrive
    // (écran Google encore visible), on stocke la destination dans
    // _pendingOAuthNav et on navigue dans didChangeAppLifecycleState → resumed.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn && !_navigationDone) {
        debugPrint('[OAuth] signedIn event détecté — session établie');
        _pendingOAuthNav = const HomeScreen();

        final appState = WidgetsBinding.instance.lifecycleState;
        if (appState == AppLifecycleState.resumed) {
          // App au premier plan : tenter une navigation immédiate uniquement
          // si l'animation splash est terminée, sinon on garde en pending.
          if (_animDone) {
            debugPrint('[OAuth] App resumed + anim done → navigation HomeScreen');
            _flushPendingNav();
          } else {
            debugPrint('[OAuth] Splash animation en cours — navigation différée');
          }
        } else {
          // App en arrière-plan (écran Google) → stocker et différer
          debugPrint('[OAuth] App en arrière-plan — navigation différée');
        }
      }
    });
  }

  void _initParticles() {
    for (int i = 0; i < 20; i++) {
      _particles.add(_Particle(
        x: _rng.nextDouble(), y: _rng.nextDouble(),
        size: _rng.nextDouble() * 6 + 1.5,
        speed: _rng.nextDouble() * 0.3 + 0.08,
        angle: _rng.nextDouble() * math.pi * 2,
        rotSpeed: (_rng.nextDouble() - 0.5) * 0.5,
        type: _rng.nextInt(3),
        isViolet: _rng.nextBool(),
        opacity: _rng.nextDouble() * 0.2 + 0.03,
      ));
    }
  }

  void _initControllers() {
    _orbCtrl      = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);
    _pulseCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _glitchCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 60));
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _loaderCtrl   = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _masterCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
  }

  void _startAnimations() {
    _masterCtrl.addListener(_onMasterTick);
    _masterCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() { _animDone = true; _showLoader = true; });
        _flushPendingNav();
        _startFlow();
      }
    });
    _masterCtrl.forward();
  }

  void _startRealLoading() async {
    await Future.wait([_checkSupabase(), _checkHive(), _checkTmdb()]);
    if (mounted) {
      setState(() => _realProgress = 1.0);
      // Délai légèrement plus long pour laisser Supabase terminer le traitement
      // du deep link OAuth (hash parsing + session creation) avant _navigateNext.
      // 1200ms → 1800ms : couvre les cas où le deep link arrive juste avant la fin du splash.
      Future.delayed(const Duration(milliseconds: 1800), _forceNavigate);
    }
  }

  Future<void> _checkSupabase() async {
    try {
      await Supabase.instance.client.auth.getUser();
      if (mounted) setState(() => _loadStep = 1);
    } catch (e) {
      debugPrint('[Splash] Supabase: $e');
      // Session locale expirée ou invalide → purger pour forcer le re-login.
      // Sans ce signOut, currentSession renvoie encore l'ancienne session
      // en cache et _navigateNext croit à tort que l'user est connecté.
      final errStr = e.toString();
      if (errStr.contains('token is expired') ||
          errStr.contains('bad_jwt') ||
          errStr.contains('invalid JWT') ||
          errStr.contains('refresh_token_not_found')) {
        try {
          await Supabase.instance.client.auth.signOut();
          debugPrint('[Splash] Session expirée purgée → redirect login');
        } catch (_) {}
      }
    }
  }

  Future<void> _checkHive() async {
    try {
      await Hive.box('settings').get('pref_theme');
      if (mounted) setState(() => _loadStep = 0);
    } catch (_) {}
  }

  Future<void> _checkTmdb() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _loadStep = 2);
  }

  void _onMasterTick() {
    final t = _masterCtrl.value;
    final newStep = (t * 4).floor().clamp(0, 3);
    if (newStep != _loadStep && mounted) setState(() => _loadStep = newStep);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // [FIX-OAUTH-4]
    _authSub.cancel(); // [FIX OAUTH]
    _masterCtrl.dispose();
    _orbCtrl.dispose();
    _pulseCtrl.dispose();
    _glitchCtrl.dispose();
    _particleCtrl.dispose();
    _loaderCtrl.dispose();
    super.dispose();
  }

  // [FIX-OAUTH-4] Flush la navigation différée dès que l'app revient au premier plan
  // [FIX-OAUTH-5] Ajouter un délai minimal pour garantir que le context est stable
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Délai minimal pour que le build tree soit stabilisé après resume
      Future.delayed(const Duration(milliseconds: 100), _flushPendingNav);
    }
  }

  void _flushPendingNav() {
    final target = _pendingOAuthNav;
    if (target != null && mounted && _animDone && !_navigationDone) {
      _navigationDone = true;
      _pendingOAuthNav = null;
      debugPrint('[OAuth] App resumed → navigation vers ${target.runtimeType}');
      _go(target);
    }
  }

  // ── Flow navigation (identique v4) ─────────────────────────────────────────
  Future<void> _startFlow() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final box = Hive.box('settings');

    // ── ÉTAPE 0 : Langue + Disclaimer (TOUT PREMIER, 1er lancement uniquement) ──
    final langDisclaimerDone = box.get(kLangDisclaimerDone, defaultValue: false) as bool;
    if (!langDisclaimerDone) {
      await _navigate(const LangDisclaimerScreen());
      if (!mounted) return;
    }

    // Disclaimer legacy (migration : si l'ancienne clé est absente mais la nouvelle présente)
    // Plus besoin d'afficher le popup — géré par LangDisclaimerScreen
    final disclaimerSeen = box.get('disclaimer_seen', defaultValue: false) as bool;
    if (!disclaimerSeen && langDisclaimerDone) {
      // Marquer comme vu (migration utilisateurs existants sans LangDisclaimerScreen)
      box.put('disclaimer_seen', true);
    }
    if (!disclaimerSeen && !langDisclaimerDone) {
      // Ancien flow (ne devrait plus arriver après LangDisclaimerScreen)
      box.put('disclaimer_seen', true);
      Future.delayed(Duration.zero, () => _requestPermissions());
    }
    final setupDone = box.get(kSetupDone, defaultValue: false) as bool;
    if (!setupDone && mounted) await _navigate(const SetupScreen());
    final onboardingDone = box.get(kOnboardingDone, defaultValue: false) as bool;
    if (!onboardingDone && mounted) {
      // [FIX-ONBOARDING] On pousse l'onboarding et on attend que l'user
      // le termine. Le marquage kOnboardingDone est fait dans OnboardingScreen
      // lui-même (bouton Terminer) — pas ici, pour éviter de le sauter
      // si l'user ferme l'app pendant l'onboarding.
      await _navigate(const OnboardingScreen());
      // Relire la valeur après retour — si l'onboarding a été complété
      // il a lui-même écrit la clé. Sinon on continue quand même.
    }
    if (mounted) _navigateNext();
  }

  Future<void> _navigate(Widget screen) async {
    await Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  Future<void> _showDisclaimerPopup() =>
      showDialog(context: context, barrierDismissible: false,
          builder: (_) => const _DisclaimerDialog());

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid || Platform.operatingSystem == 'tizen') {
      final status = await Permission.notification.request();
      Future.delayed(Duration.zero, () =>
          Hive.box('settings').put('pref_notifications', status.isGranted));
    }
  }

  Future<void> _navigateNext() async {
    if (_navigationDone || !mounted) return;
    _navigationDone = true;

    final session = Supabase.instance.client.auth.currentSession;
    // currentSession retourne la session locale même si le token est expiré.
    // On vérifie l'expiration réelle via expiresAt (epoch secondes).
    // Un token expiré depuis plus de 60s est considéré invalide.
    final hasValidSession = session != null &&
        (session.expiresAt == null ||
            session.expiresAt! >
                (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60);

    if (!hasValidSession) {
      // [FIX-OAUTH] Le callback onAuthSuccess est appelé DEPUIS AuthScreen.
      // On ne peut pas utiliser le contexte du SplashScreen ici (déjà remplacé).
      // Solution : AuthScreen appelle onAuthSuccess → on pousse HomeScreen
      // via pushAndRemoveUntil qui nettoie toute la pile proprement.
     // [FIX-OAUTH-CONTEXT] Résoudre le NavigatorState ICI, pendant que le context
      // SplashScreen est encore valide. Après _go() → pushReplacement, le SplashScreen
      // est disposé et Navigator.of(context) depuis la closure levait un FlutterError
      // "Looking up a deactivated widget's ancestor" → silencieusement catchée → pas de navigation.
      final rootNav = Navigator.of(context, rootNavigator: true);
      _go(AuthScreen(onAuthSuccess: () {
        rootNav.pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LicenseGate(child: HomeScreen()),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
          (_) => false,
        );
      }));
      return;
    }

    // Initialiser les profils
    final profileProv = context.read<ProfileProvider>();
    profileProv.init();

    // ── Vérification licence ──────────────────────────────────────────────
    // Lance le check en background — LicenseGate bloquera si invalide.
    // On n'attend pas la réponse pour ne pas ralentir le démarrage.
    final licenseProv = context.read<LicenseProvider>();
    unawaited(licenseProv.init());

    // Si plusieurs profils → afficher le picker, sinon HomeScreen direct
    if (profileProv.count > 1) {
      _go(ProfilePickerScreen(
        onProfileSelected: () {
          Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LicenseGate(child: HomeScreen()),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ));
        },
      ));
    } else {
      _go(_UpdateGate(child: const LicenseGate(child: HomeScreen())));
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Hive.box('settings').put('last_splash_at', DateTime.now().toIso8601String());
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 800),
    ));
  }

  void _forceNavigate() {
    // [FIX-ONBOARDING] Ne court-circuite PAS _startFlow.
    // _startFlow est déclenché par _masterCtrl (statusListener completed).
    // _forceNavigate est appelé par _startRealLoading → sert uniquement
    // à s'assurer que la navigation a lieu si _startFlow s'est terminé
    // avant que _realProgress atteigne 1.0 (cas réseau lent).
    // On n'appelle _navigateNext() que si _animDone = true, garantissant
    // que _startFlow a eu le temps de vérifier onboarding/setup.
    if (mounted && _realProgress == 1.0 && _animDone) _navigateNext();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(fit: StackFit.expand, children: [

        // ── Fond : mesh gradient 3 orbs animés ─────────────────────────────
        RepaintBoundary(child: AnimatedBuilder(
          animation: _orbCtrl,
          builder: (_, __) => CustomPaint(
            painter: _MeshPainter(t: _orbCtrl.value),
            size: Size.infinite,
          ),
        )),

        // ── Grain statique ─────────────────────────────────────────────────
        RepaintBoundary(child: CustomPaint(
          painter: _GrainPainter(seed: 42),
          size: Size.infinite,
        )),

        // ── Particules ─────────────────────────────────────────────────────
        RepaintBoundary(child: AnimatedBuilder(
          animation: _particleCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ParticlePainter(particles: _particles, progress: _particleCtrl.value),
            size: Size.infinite,
          ),
        )),

        // ── Scan line ──────────────────────────────────────────────────────
        RepaintBoundary(child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ScanPainter(progress: _pulseCtrl.value),
            size: Size.infinite,
          ),
        )),

        // ── Contenu central ────────────────────────────────────────────────
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildLogo(),
          const SizedBox(height: 40),
          _buildTitle(),
          const SizedBox(height: 18),
          _buildTagline(),
        ])),

        // ── Loader bas ─────────────────────────────────────────────────────
        if (_showLoader)
          Positioned(bottom: 56, left: 0, right: 0,
            child: Center(child: _buildLoader())),

        // ── Version badge ──────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          right: 20,
          child: _buildVersionBadge()),
      ]),
    );
  }

  // ── Logo ───────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_masterCtrl, _pulseCtrl]),
      builder: (_, __) {
        final appearT = (_masterCtrl.value * 2.5).clamp(0.0, 1.0);
        final scaleT  = Curves.elasticOut.transform(
            (_masterCtrl.value * 1.8).clamp(0.0, 1.0));
        final pulse   = _pulseCtrl.value;

        return Opacity(
          opacity: appearT,
          child: Transform.scale(
            scale: 0.3 + 0.7 * scaleT,
            child: Stack(alignment: Alignment.center, children: [

              // Glow extérieur diffus
              Container(
                width: 148, height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.violet.withOpacity(0.35 * pulse),
                      blurRadius: 60, spreadRadius: 8),
                    BoxShadow(
                      color: AppTheme.red.withOpacity(0.18 * pulse),
                      blurRadius: 40, spreadRadius: 4),
                  ],
                ),
              ),

              // Ring extérieur gradient violet→rouge
              Container(
                width: 136, height: 136,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppTheme.violet, AppTheme.red]),
                ),
              ),

              // Ring intérieur — gap sombre
              Container(
                width: 128, height: 128,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppTheme.background),
              ),

              // Ring intérieur accent — plus fin
              Container(
                width: 124, height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [
                      AppTheme.violet.withOpacity(0.6),
                      AppTheme.red.withOpacity(0.4)]),
                ),
              ),

              // Logo image
              ClipOval(child: SizedBox(
                width: 118, height: 118,
                child: Image.asset('assets/logo.png', fit: BoxFit.cover),
              )),

              // Reflet en haut
              Positioned(
                top: 18, left: 28,
                child: Container(
                  width: 30, height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [Colors.white.withOpacity(0.25), Colors.transparent])),
                )),
            ]),
          ),
        );
      },
    );
  }

  // ── Titre lettres staggerées ───────────────────────────────────────────────
  Widget _buildTitle() {
    return AnimatedBuilder(
      animation: _masterCtrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_letters.length, (i) {
            if (_letters[i] == ' ') return const SizedBox(width: 14);

            // Chaque lettre a un délai croissant
            final delay = i * 0.07;
            final raw   = (_masterCtrl.value - delay) / 0.4;
            final t     = Curves.easeOutBack.transform(raw.clamp(0.0, 1.0));
            final opacity = raw.clamp(0.0, 1.0);

            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - t)),
                child: ShaderMask(
                  shaderCallback: (bounds) => AppTheme.gradientHorizontal
                      .createShader(Rect.fromLTWH(0, 0, 320, 60)),
                  child: Text(
                    _letters[i],
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 5,
                      height: 1,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // ── Tagline ────────────────────────────────────────────────────────────────
  Widget _buildTagline() {
    return AnimatedBuilder(
      animation: _masterCtrl,
      builder: (_, child) {
        final t = ((_masterCtrl.value - 0.75) / 0.25).clamp(0.0, 1.0);
        return Opacity(opacity: t, child: child);
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Séparateur gauche violet
        AnimatedBuilder(
          animation: _masterCtrl,
          builder: (_, __) {
            final t = ((_masterCtrl.value - 0.75) / 0.25).clamp(0.0, 1.0);
            return Container(
              width: 28 * t, height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, AppTheme.violet.withOpacity(0.6)])),
            );
          },
        ),
        const SizedBox(width: 14),
        Text(
          context.read<LanguageProvider>().l10n.t('tagline'),
          style: const TextStyle(
            fontSize: 11, color: AppTheme.textMuted,
            fontWeight: FontWeight.w400, letterSpacing: 3.0,
          ),
        ),
        const SizedBox(width: 14),
        // Séparateur droit rouge
        AnimatedBuilder(
          animation: _masterCtrl,
          builder: (_, __) {
            final t = ((_masterCtrl.value - 0.75) / 0.25).clamp(0.0, 1.0);
            return Container(
              width: 28 * t, height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.red.withOpacity(0.6), Colors.transparent])),
            );
          },
        ),
      ]),
    );
  }

  // ── Loader progress + message ──────────────────────────────────────────────
  Widget _buildLoader() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Barre progress premium
      SizedBox(
        width: 180,
        child: Stack(children: [
          // Track glass
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Fill gradient animé
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            widthFactor: _realProgress.clamp(0.0, 1.0),
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientHorizontal,
                borderRadius: BorderRadius.circular(2),
                boxShadow: AppTheme.glowViolet(),
              ),
            ),
          ),
          // Dot pulsant à la tête de la barre
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final prog = _realProgress.clamp(0.0, 1.0);
              if (prog <= 0) return const SizedBox.shrink();
              return Positioned(
                left: 180 * prog - 5,
                top: -3,
                child: Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.violet.withOpacity(0.5 + _pulseCtrl.value * 0.5),
                        blurRadius: 8, spreadRadius: 1),
                    ],
                  ),
                ),
              );
            },
          ),
        ]),
      ),
      const SizedBox(height: 16),
      // Message chargement
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          key: ValueKey(_loadStep),
          _loadMessages[_loadStep.clamp(0, _loadMessages.length - 1)],
          style: const TextStyle(
            fontSize: 10, color: AppTheme.textMuted,
            letterSpacing: 1.8, fontWeight: FontWeight.w400,
          ),
        ),
      ),
    ]);
  }

  // ── Version badge ──────────────────────────────────────────────────────────
  Widget _buildVersionBadge() {
    return AnimatedBuilder(
      animation: _masterCtrl,
      builder: (_, child) {
        final t = ((_masterCtrl.value - 0.7) / 0.3).clamp(0.0, 1.0);
        return Opacity(opacity: t, child: child);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.gradientHorizontal,
                  boxShadow: [BoxShadow(
                      color: AppTheme.violet.withOpacity(0.6), blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 6),
              Text('v$kAppVersion',
                style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═════════════════════════════════════════════════════════════════════════════

/// Mesh gradient : 3 orbs colorés qui se déplacent doucement
class _MeshPainter extends CustomPainter {
  final double t;
  const _MeshPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    void orb(double cx, double cy, double r, Color color) {
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..shader = RadialGradient(
          colors: [color, Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    final w = size.width, h = size.height;
    // Orb violet haut-gauche
    orb(w * (0.15 + t * 0.12), h * (0.08 + t * 0.10),
        w * 0.55, AppTheme.violet.withOpacity(0.09));
    // Orb rouge bas-droit
    orb(w * (0.80 - t * 0.10), h * (0.72 + t * 0.08),
        w * 0.50, AppTheme.red.withOpacity(0.06));
    // Orb bleu milieu
    orb(w * (0.55 + t * 0.06), h * (0.40 - t * 0.08),
        w * 0.35, AppTheme.secondary.withOpacity(0.04));
  }

  @override bool shouldRepaint(_MeshPainter o) => o.t != t;
}

/// Grain statique (ne redessine jamais)
class _GrainPainter extends CustomPainter {
  final int seed;
  const _GrainPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.012);
    final rng = math.Random(seed);
    for (int i = 0; i < 600; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        0.6, paint);
    }
  }

  @override bool shouldRepaint(_) => false;
}

/// Scan line cinématique
class _ScanPainter extends CustomPainter {
  final double progress;
  const _ScanPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final scanY = (math.sin(progress * math.pi * 2) * 0.5 + 0.5) * size.height;
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent,
        AppTheme.violet.withOpacity(0.055),
        AppTheme.red.withOpacity(0.035),
        Colors.transparent,
      ]).createShader(Rect.fromLTWH(0, scanY - 50, size.width, 100));
    canvas.drawRect(Rect.fromLTWH(0, scanY - 50, size.width, 100), paint);
  }

  @override bool shouldRepaint(_ScanPainter o) => o.progress != progress;
}

/// Particules triangulaires flottantes
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  const _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t  = (progress * p.speed + p.angle / (2 * math.pi)) % 1.0;
      final px = (p.x + math.cos(p.angle) * t * 0.2) % 1.0 * size.width;
      final py = (p.y + math.sin(p.angle) * t * 0.2) % 1.0 * size.height;
      final paint = Paint()
        ..color = (p.isViolet ? AppTheme.violet : AppTheme.red).withOpacity(p.opacity)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(progress * p.rotSpeed * 2 * math.pi);
      if (p.type == 0) {
        final path = Path()
          ..moveTo(0, -p.size)
          ..lineTo(p.size * 0.7, p.size * 0.4)
          ..lineTo(-p.size * 0.7, p.size * 0.4)
          ..close();
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  @override bool shouldRepaint(_ParticlePainter o) => o.progress != progress;
}

// ═════════════════════════════════════════════════════════════════════════════
// DISCLAIMER DIALOG — redesign glass premium
// ═════════════════════════════════════════════════════════════════════════════
class _DisclaimerDialog extends StatelessWidget {
  const _DisclaimerDialog();

  @override
  Widget build(BuildContext context) {
    final isTV   = context.isTV;
    final l10n   = context.read<LanguageProvider>().l10n;
    final isTizen = Platform.operatingSystem == 'tizen';

    Widget inner = Container(
      padding: EdgeInsets.all(isTV ? 36 : 28),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isTizen ? 0.97 : 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.violet.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(color: AppTheme.violet.withOpacity(0.20),
              blurRadius: 40, spreadRadius: 0),
          BoxShadow(color: Colors.black.withOpacity(0.5),
              blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Icône shield avec ring gradient
        Stack(alignment: Alignment.center, children: [
          Container(
            width: isTV ? 72 : 60, height: isTV ? 72 : 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.gradientHorizontal,
            ),
          ),
          Container(
            width: isTV ? 66 : 54, height: isTV ? 66 : 54,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF0A0A14)),
          ),
          Icon(Icons.shield_rounded, color: AppTheme.violet, size: isTV ? 32 : 26),
        ]),

        SizedBox(height: isTV ? 24 : 18),

        // Titre
        ShaderMask(
          shaderCallback: (b) => AppTheme.gradientHorizontal
              .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          child: Text(l10n.t('disclaimer_title'),
            style: TextStyle(color: Colors.white,
                fontSize: isTV ? 24 : 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
        ),

        SizedBox(height: isTV ? 20 : 14),

        // Séparateur gradient
        Container(height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent, AppTheme.violet.withOpacity(0.4),
              AppTheme.red.withOpacity(0.3), Colors.transparent,
            ]))),

        SizedBox(height: isTV ? 20 : 14),

        // Corps
        Flexible(child: SingleChildScrollView(
          child: Text(l10n.t('disclaimer_body'),
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: isTV ? 15 : 13, height: 1.65),
            textAlign: TextAlign.center),
        )),

        SizedBox(height: isTV ? 28 : 22),

        // Bouton accepter
        _DisclaimerButton(isTV: isTV, label: l10n.t('disclaimer_accept')),
      ]),
    );

    if (!isTizen) {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: inner));
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: isTV ? 600 : 380,
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: inner.animate().fadeIn(duration: 300.ms).scale(
            begin: const Offset(0.92, 0.92), end: const Offset(1, 1),
            duration: 350.ms, curve: Curves.easeOutBack),
      ),
    );
  }
}

class _DisclaimerButton extends StatefulWidget {
  final bool isTV;
  final String label;
  const _DisclaimerButton({required this.isTV, required this.label});
  @override State<_DisclaimerButton> createState() => _DisclaimerButtonState();
}

class _DisclaimerButtonState extends State<_DisclaimerButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: widget.isTV ? 60 : 52,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientHorizontal,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _focused ? AppTheme.glowViolet() : AppTheme.softShadow(),
            border: _focused
                ? Border.all(color: Colors.white.withOpacity(0.45), width: 2)
                : null,
          ),
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(widget.label,
              style: TextStyle(color: Colors.white,
                  fontSize: widget.isTV ? 17 : 15,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ])),
        ),
      ),
    );
  }
}

/// Vérifie les mises à jour obligatoires au premier frame après navigation.
class _UpdateGate extends StatefulWidget {
  final Widget child;
  const _UpdateGate({required this.child});
  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdateService.enforceIfNeeded(context, kAppVersion);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}