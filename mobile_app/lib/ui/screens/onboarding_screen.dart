// lib/ui/screens/onboarding_screen.dart
// Arich Player — Onboarding Screen v3.1
// 5 pages de présentation cinématiques — niveau Netflix / Apple TV+
// Page 1 — Bienvenue + écran TV illustré
// Page 2 — Direct & Live TV
// Page 3 — Films & Séries
// Page 4 — Multi-écran, PiP, EPG
// Page 5 — Ajouter sa playlist + CTA
//
// [FIX v3.1] Palette privée (_kViolet, _kRed, _kBlue…) supprimée —
//   toutes les couleurs migrent vers AppTheme (règle absolue : jamais
//   de hex hardcodé hors AppTheme).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../widgets/add_playlist_sheet.dart';
import 'auth_screen.dart';

const kOnboardingDone = 'onboarding_done';

// ─── Couleurs page par page — toutes issues d'AppTheme ───────────────────────
// Accent par page : violet, red, secondary(blue), success(teal), gold
const _kPageAccents = <Color>[
  AppTheme.violet,
  AppTheme.red,
  AppTheme.secondary,
  AppTheme.success,
  AppTheme.gold,
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {

  final PageController _pageCtrl = PageController();
  int _page = 0;
  static const int _totalPages = 5;

  late final AnimationController _bgCtrl;
  late final AnimationController _particleCtrl;

  final List<_BGParticle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();

    for (int i = 0; i < 16; i++) {
      _particles.add(_BGParticle(
        x:        _rng.nextDouble(),
        y:        _rng.nextDouble(),
        size:     _rng.nextDouble() * 3 + 1,
        speed:    _rng.nextDouble() * 0.2 + 0.05,
        opacity:  _rng.nextDouble() * 0.15 + 0.03,
        isViolet: _rng.nextBool(),
      ));
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 420),
        curve:    Curves.easeOutCubic);
    }
  }

  void _skip() => _complete();

  Future<void> _complete() async {
    await Hive.box('settings').put(kOnboardingDone, true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder:        (_, a, __) => const AuthScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
        transitionDuration: const Duration(milliseconds: 550),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLand = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(children: [

        // ── Fond animé ──────────────────────────────────────────────────────
        Positioned.fill(child: RepaintBoundary(child: AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) {
            final t  = _bgCtrl.value;
            final c1 = _kPageAccents[_page % _kPageAccents.length];
            final c2 = _kPageAccents[(_page + 1) % _kPageAccents.length];
            final color = Color.lerp(c1, c2, t * 0.3)!;
            return Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(sin(t * pi) * 0.6 - 0.2, -0.5),
                  radius: 1.6,
                  colors: [color.withOpacity(0.1), AppTheme.background],
                  stops: const [0.0, 0.6],
                ),
              ),
            );
          },
        ))),

        // ── Particules ──────────────────────────────────────────────────────
        Positioned.fill(child: RepaintBoundary(child: AnimatedBuilder(
          animation: _particleCtrl,
          builder: (_, __) => CustomPaint(
            painter: _OnboardParticlePainter(
                particles: _particles, progress: _particleCtrl.value),
            size: Size.infinite,
          ),
        ))),

        // ── Pages ───────────────────────────────────────────────────────────
        PageView(
          controller:    _pageCtrl,
          onPageChanged: (p) => setState(() => _page = p),
          physics:       const BouncingScrollPhysics(),
          children: [
            _Page1Welcome(isLand: isLand, onNext: _next, onSkip: _skip),
            _Page2Live(isLand: isLand, onNext: _next),
            _Page3Content(isLand: isLand, onNext: _next),
            _Page4Features(isLand: isLand, onNext: _next),
            _Page5Playlist(isLand: isLand, onDone: _complete),
          ],
        ),

        // ── Nav bas ──────────────────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomNav(isLand),
        ),
      ]),
    );
  }

  Widget _buildBottomNav(bool isLand) {
    final isLast    = _page == _totalPages - 1;
    final accent    = isLast ? AppTheme.gold   : AppTheme.violet;
    final accentEnd = isLast ? const Color(0xFFFF9F43) : AppTheme.red;

    return Container(
      padding: EdgeInsets.fromLTRB(28, 12, 28, isLand ? 16 : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, AppTheme.background.withOpacity(0.9)]),
      ),
      child: Row(children: [
        // Dots indicateurs
        Row(children: List.generate(_totalPages, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(right: 6),
          width:  _page == i ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            gradient: _page == i
                ? const LinearGradient(colors: [AppTheme.violet, AppTheme.red])
                : null,
            color:           _page == i ? null : Colors.white.withOpacity(0.16),
            borderRadius:    BorderRadius.circular(3),
          ),
        ))),
        const Spacer(),

        // Bouton "Passer"
        if (!isLast)
          GestureDetector(
            onTap: _skip,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(context.read<LanguageProvider>().l10n.t('onboarding_skip'), style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),

        // Bouton Suivant / Commencer
        GestureDetector(
          onTap: isLast ? _complete : _next,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height:  44,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accentEnd]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(
                color:      accent.withOpacity(0.4),
                blurRadius: 16)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(isLast ? 'Commencer' : 'Suivant', style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Icon(
                isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                color: Colors.white, size: 17),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE 1 — BIENVENUE
// ══════════════════════════════════════════════════════════════════════════════
class _Page1Welcome extends StatelessWidget {
  final bool isLand;
  final VoidCallback onNext, onSkip;
  const _Page1Welcome({required this.isLand, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment:  MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo + titre
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient:     AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 16)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/logo.png', fit: BoxFit.cover)),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (b) => AppTheme.gradientHorizontal
                .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: const Text('Arich Player', style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
        ]).animate().fadeIn(duration: 500.ms),
        SizedBox(height: 20),

        _LangPicker(),
        SizedBox(height: 20),

        Text(context.read<LanguageProvider>().l10n.t('onboarding_tagline'), style: TextStyle(
          color:      Colors.white,
          fontSize:   isLand ? 32 : 36,
          fontWeight: FontWeight.w900,
          height: 1.1, letterSpacing: -0.8))
            .animate(delay: 150.ms).fadeIn(duration: 500.ms).slideY(begin: 0.06),
        SizedBox(height: 14),

        Text(context.read<LanguageProvider>().l10n.t('onboarding_sub'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 14, height: 1.55))
              .animate(delay: 280.ms).fadeIn(duration: 400.ms),
        const SizedBox(height: 16),
      ],
    );

    final visual = _TVIllustration();

    if (isLand) {
      return SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 80),
        child: Row(children: [
          Expanded(flex: 5, child: SingleChildScrollView(child: content)),
          Expanded(flex: 4, child: visual),
        ]),
      ));
    }
    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 90),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 160, child: visual),
        const SizedBox(height: 20),
        content,
      ]),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE 2 — DIRECT & LIVE
// ══════════════════════════════════════════════════════════════════════════════
class _Page2Live extends StatelessWidget {
  final bool isLand;
  final VoidCallback onNext;
  const _Page2Live({required this.isLand, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _OnboardPage(
      isLand: isLand,
      accent: AppTheme.red,
      emoji:  '📡',
      title:  'Direct\nen continu',
      desc:   'Des milliers de chaînes en direct — HD, FHD et 4K. Sport, news, cinéma, local. Partout dans le monde.',
      visual: _LiveVisual(),
      stats: const [
        _Stat('HD / 4K', 'Qualité'),
        _Stat('150+',    'Pays'),
        _Stat('EPG',     'Guide TV'),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE 3 — FILMS & SÉRIES
// ══════════════════════════════════════════════════════════════════════════════
class _Page3Content extends StatelessWidget {
  final bool isLand;
  final VoidCallback onNext;
  const _Page3Content({required this.isLand, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _OnboardPage(
      isLand: isLand,
      accent: AppTheme.violet,
      emoji:  '🎬',
      title:  'Films &\nSéries',
      desc:   'Connectez votre serveur pour accéder à vos films VOD et séries. Affiches HD, synopsis TMDB, navigation fluide.',
      visual: _ContentVisual(),
      stats: const [
        _Stat('VOD',    'Catalogue'),
        _Stat('4K HDR', 'Qualité max'),
        _Stat('TMDB',   'Métadonnées'),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE 4 — FONCTIONNALITÉS AVANCÉES
// ══════════════════════════════════════════════════════════════════════════════
class _Page4Features extends StatelessWidget {
  final bool isLand;
  final VoidCallback onNext;
  const _Page4Features({required this.isLand, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return _OnboardPage(
      isLand: isLand,
      accent: AppTheme.success,
      emoji:  '⚡',
      title:  'Fonctions\npremium',
      desc:   'PiP, multi-écran, téléchargement offline, EPG interactif, contrôle parental — tout ce dont vous avez besoin.',
      visual: _FeaturesVisual(),
      stats: const [
        _Stat('PiP',     'Multi-fenêtre'),
        _Stat('EPG',     'Guide TV'),
        _Stat('Offline', 'Téléchargement'),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE 5 — PLAYLIST
// ══════════════════════════════════════════════════════════════════════════════
class _Page5Playlist extends StatelessWidget {
  final bool isLand;
  final VoidCallback onDone;
  const _Page5Playlist({required this.isLand, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final types = [
      (Icons.stream_rounded,   AppTheme.violet,    'Xtream Codes',  'Serveur · Utilisateur · Mot de passe'),
      (Icons.list_alt_rounded, AppTheme.secondary, 'Lien M3U',      'URL directe de votre playlist M3U'),
      (Icons.folder_rounded,   AppTheme.success,   'Fichier local', 'Importer un fichier .m3u depuis l\'appareil'),
    ];

    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, isLand ? 12 : 24, 24, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🚀', style: TextStyle(fontSize: 40))
            .animate().scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1),
              duration: 500.ms, curve: Curves.elasticOut),
        SizedBox(height: 16),
        Text(context.read<LanguageProvider>().l10n.t('onboarding_ready'), style: TextStyle(
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
          letterSpacing: -0.4, height: 1.1))
            .animate(delay: 100.ms).fadeIn(duration: 400.ms).slideY(begin: 0.06),
        SizedBox(height: 8),
        Text(context.read<LanguageProvider>().l10n.t('onboarding_connect'),
          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13.5, height: 1.5))
            .animate(delay: 200.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: 24),

        ...types.asMap().entries.map((e) {
          final f = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => showAddPlaylistSheet(context),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border:       Border.all(color: f.$2.withOpacity(0.2))),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color:        f.$2.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                    child: Icon(f.$1, color: f.$2, size: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.$3, style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(f.$4, style: TextStyle(
                        color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
                    ]),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: f.$2.withOpacity(0.5),
                    size: 14,
                  ),
                ]),
              ),
            ).animate(delay: Duration(milliseconds: 250 + e.key * 80))
             .fadeIn(duration: 350.ms).slideX(begin: 0.04, end: 0),
          );
        }),
      ]),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TEMPLATE PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _Stat {
  final String value, label;
  const _Stat(this.value, this.label);
}

class _OnboardPage extends StatelessWidget {
  final bool   isLand;
  final Color  accent;
  final String emoji, title, desc;
  final Widget visual;
  final List<_Stat> stats;
  const _OnboardPage({required this.isLand, required this.accent,
    required this.emoji, required this.title, required this.desc,
    required this.visual, required this.stats});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment:  MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 32))
            .animate().scale(begin: const Offset(0.4, 0.4), end: const Offset(1, 1),
              duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
          letterSpacing: -0.6, height: 1.1))
            .animate(delay: 120.ms).fadeIn(duration: 400.ms).slideY(begin: 0.06),
        const SizedBox(height: 8),
        Text(desc, style: TextStyle(
          color: Colors.white.withOpacity(0.45), fontSize: 13.5, height: 1.55))
            .animate(delay: 220.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: 14),

        // Stats pills
        Row(children: stats.map((s) => Expanded(child: Container(
          margin:  const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:        accent.withOpacity(0.09),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: accent.withOpacity(0.2))),
          child: Column(children: [
            Text(s.value, style: TextStyle(
              color: accent, fontSize: 18, fontWeight: FontWeight.w900)),
            Text(s.label, style: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ]),
        ))).toList())
            .animate(delay: 350.ms).fadeIn(duration: 350.ms),
        const SizedBox(height: 80),
      ],
    );

    if (isLand) {
      return SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 80),
        child: Row(children: [
          Expanded(flex: 5, child: SingleChildScrollView(child: content)),
          Expanded(flex: 4, child: Padding(
            padding: const EdgeInsets.only(left: 20), child: visual)),
        ]),
      ));
    }
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 120, child: visual),
        const SizedBox(height: 20),
        Expanded(child: SingleChildScrollView(child: content)),
      ]),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VISUELS ILLUSTRÉS
// ══════════════════════════════════════════════════════════════════════════════

class _TVIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF14103A), Color(0xFF0A0818)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.violet.withOpacity(0.3), width: 2),
            boxShadow: [
              BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 30),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(children: [
              Positioned.fill(child: RepaintBoundary(child: CustomPaint(
                  painter: _ScreenContentPainter()))),
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                    stops: const [0, 0.5])),
              )),
              Positioned(bottom: 12, left: 14, right: 14, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 8, width: 100,
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 5),
                  Container(height: 5, width: 70,
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3))),
                ],
              )),
              // Badge LIVE
              Positioned(top: 10, left: 10, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.red, borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, color: Colors.white, size: 6),
                  SizedBox(width: 4),
                  Text(context.read<LanguageProvider>().l10n.t('multi_live_badge'), style: TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ]),
              )),
            ]),
          ),
        ),
        // Glow reflet
        Positioned(
          bottom: -16, left: 20, right: 20,
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [AppTheme.violet.withOpacity(0.35), Colors.transparent]),
            ),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 600.ms, delay: 100.ms)
        .slideY(begin: 0.08, end: 0));
  }
}

class _LiveVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final channels = [
      ('📺', 'TF1',      AppTheme.red),
      ('⚽', 'Sport+',   AppTheme.secondary),
      ('🎬', 'Ciné+',    AppTheme.violet),
      ('📰', 'BFM',      AppTheme.success),
      ('🌍', 'France 24',AppTheme.gold),
      ('🎵', 'MTV',      AppTheme.warning),
    ];
    return GridView.builder(
      physics:   const NeverScrollableScrollPhysics(), shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
        childAspectRatio: 1.5),
      itemCount: channels.length,
      itemBuilder: (_, i) {
        final ch = channels[i];
        return Container(
          decoration: BoxDecoration(
            color:        ch.$3.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: ch.$3.withOpacity(0.25))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(ch.$1, style: const TextStyle(fontSize: 18)),
            Text(ch.$2, style: TextStyle(
              color: Colors.white.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ).animate(delay: Duration(milliseconds: 100 + i * 60))
         .fadeIn(duration: 300.ms).scale(begin: const Offset(0.85, 0.85));
      },
    );
  }
}

class _ContentVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      (AppTheme.violet,    0.9),
      (AppTheme.secondary, 0.7),
      (AppTheme.red,       0.8),
      (AppTheme.success,   0.65),
      (AppTheme.gold,      0.75),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.end,
      children: items.asMap().entries.map((e) {
        final item = e.value;
        return Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            height: 100 * item.$2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [item.$1.withOpacity(0.6), item.$1.withOpacity(0.2)]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: item.$1.withOpacity(0.3))),
            child: Center(child: Icon(Icons.movie_rounded,
                color: item.$1.withOpacity(0.6), size: 20)),
          ).animate(delay: Duration(milliseconds: 100 + e.key * 70))
           .fadeIn(duration: 300.ms).slideY(begin: 0.3, end: 0),
        ));
      }).toList());
  }
}

class _FeaturesVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      (Icons.picture_in_picture_rounded, AppTheme.success,   'PiP'),
      (Icons.grid_view_rounded,          AppTheme.secondary, 'Multi'),
      (Icons.download_rounded,           AppTheme.violet,    'Offline'),
      (Icons.calendar_today_rounded,     AppTheme.gold,      'EPG'),
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: features.asMap().entries.map((e) {
        final f = e.value;
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color:        f.$2.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: f.$2.withOpacity(0.3)),
              boxShadow: [BoxShadow(color: f.$2.withOpacity(0.2), blurRadius: 12)],
            ),
            child: Icon(f.$1, color: f.$2, size: 24)),
          const SizedBox(height: 6),
          Text(f.$3, style: TextStyle(
            color: Colors.white.withOpacity(0.6), fontSize: 10,
            fontWeight: FontWeight.w600)),
        ]).animate(delay: Duration(milliseconds: 100 + e.key * 80))
          .fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCREEN CONTENT PAINTER — contenu simulé sur l'écran TV
// ══════════════════════════════════════════════════════════════════════════════
class _ScreenContentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = AppTheme.background);

    final bands = [AppTheme.surface, AppTheme.surfaceHigh, AppTheme.surface];
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * i / 3, size.width, size.height / 3),
        Paint()..color = bands[i]);
    }

    final glow = Paint()
      ..color      = AppTheme.violet.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(
      Offset(size.width * 0.6, size.height * 0.4), size.width * 0.25, glow);

    final glow2 = Paint()
      ..color      = AppTheme.red.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.6), size.width * 0.18, glow2);
  }

  @override bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
// LANG PICKER
// ══════════════════════════════════════════════════════════════════════════════
class _LangPicker extends StatelessWidget {
  const _LangPicker();

  @override
  Widget build(BuildContext context) {
    final langProvider = context.watch<LanguageProvider>();
    final current      = langProvider.currentCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.read<LanguageProvider>().l10n.t('lang_pick_title'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: AppL10n.languages.map((lang) {
              final selected = current == lang.$3;
              return GestureDetector(
                onTap: () => langProvider.setLanguage(lang.$3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin:  const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.violet.withOpacity(0.25)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? AppTheme.violet.withOpacity(0.7)
                          : Colors.white.withOpacity(0.1),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(lang.$2, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(lang.$1,
                      style: TextStyle(
                        color:      selected ? Colors.white : Colors.white54,
                        fontSize:   12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ).animate(delay: 100.ms).fadeIn(duration: 400.ms);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PARTICLES
// ══════════════════════════════════════════════════════════════════════════════
class _BGParticle {
  final double x, y, size, speed, opacity;
  final bool   isViolet;
  const _BGParticle({required this.x, required this.y, required this.size,
    required this.speed, required this.opacity, required this.isViolet});
}

class _OnboardParticlePainter extends CustomPainter {
  final List<_BGParticle> particles;
  final double progress;
  const _OnboardParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t   = (progress * p.speed) % 1.0;
      final px  = p.x * size.width;
      final py  = ((p.y + t * 0.3) % 1.0) * size.height;
      final col = (p.isViolet ? AppTheme.violet : AppTheme.red)
          .withOpacity(p.opacity * (1 - t * 0.5));
      canvas.drawCircle(Offset(px, py), p.size, Paint()..color = col);
    }
  }

  @override bool shouldRepaint(_OnboardParticlePainter o) => o.progress != progress;
}