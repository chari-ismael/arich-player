// lib/ui/screens/setup_screen.dart
// Arich Player — Setup Screen v3 ULTRA PREMIUM
// Configuration initiale : 4 étapes cinématiques niveau Apple
// 1. Bienvenue + brand reveal
// 2. Choisir son thème
// 3. Orientation
// 4. Qualité par défaut
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/theme_provider.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../widgets/add_playlist_sheet.dart';

const String kForceLandscape = 'force_landscape';
const String kSetupDone      = 'setup_screen_done';
const String kPrefTheme      = 'pref_theme';

Future<void> applyOrientationPreference() async {
  final box   = Hive.box('settings');
  final force = box.get(kForceLandscape, defaultValue: true) as bool;
  await SystemChrome.setPreferredOrientations(force
      ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : DeviceOrientation.values);
}

// ─── Palette ─────────────────────────────────────────────────────────────────
const _kViolet  = Color(0xFF7C5CFC);
const _kVioletL = Color(0xFF9B7BFF);
const _kRed     = Color(0xFFFF2D55);
const _kGold    = Color(0xFFE8B84B);
const _kBlue    = Color(0xFF3D8EFF);
const _kTeal    = Color(0xFF00D4AA);
const _kBg      = Color(0xFF07070F);
const _kCard    = Color(0xFF0E0E1C);
const _kBorder  = Color(0xFF1C1C2E);

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────
  int    _step            = 0;
  String _themeKey        = 'dark';
  bool   _forceLandscape  = true;
  String _quality         = 'auto';
  static const _totalSteps = 5;

  // ── Controllers ─────────────────────────────────────────────────────────
  late final AnimationController _pageCtrl;
  late final AnimationController _bgCtrl;
  late final AnimationController _progressCtrl;

  late Animation<double> _pageFade;
  late Animation<Offset>  _pageSlide;

  @override
  void initState() {
    super.initState();

    _pageCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _bgCtrl   = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _pageFade  = CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOut);
    _pageSlide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOutCubic));

    _pageCtrl.forward();
    _progressCtrl.animateTo(1 / _totalSteps, duration: const Duration(milliseconds: 600));

    final box       = Hive.box('settings');
    _themeKey       = box.get(kPrefTheme,      defaultValue: 'dark') as String;
    _forceLandscape = box.get(kForceLandscape, defaultValue: true)   as bool;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_step < _totalSteps - 1) {
      // Sauvegarder si thème
      if (_step == 1) await context.read<ThemeProvider>().setTheme(_themeKey);

      await _pageCtrl.reverse();
      setState(() => _step++);
      _pageCtrl.forward(from: 0);
      _progressCtrl.animateTo(
        (_step + 1) / _totalSteps,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _finish();
    }
  }

  Future<void> _prevStep() async {
    if (_step == 0) return;
    await _pageCtrl.reverse();
    setState(() => _step--);
    _pageCtrl.forward(from: 0);
    _progressCtrl.animateTo(
      (_step + 1) / _totalSteps,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final box = Hive.box('settings');
    await box.put(kForceLandscape, _forceLandscape);
    await box.put(kPrefTheme, _themeKey);
    await box.put('pref_stream_quality', _quality);
    await applyOrientationPreference();
    await box.put(kSetupDone, true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isTV   = context.isTV;
    final isLand = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(fit: StackFit.expand, children: [
        // Fond animé
        _AnimatedBg(ctrl: _bgCtrl, themeKey: _themeKey),

        SafeArea(child: Column(children: [
          // ── Header ────────────────────────────────────────────────────────
          _buildHeader(isTV),

          // ── Contenu page ──────────────────────────────────────────────────
          Expanded(child: FadeTransition(
            opacity: _pageFade,
            child: SlideTransition(
              position: _pageSlide,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isTV ? 64 : isLand ? 48 : 28,
                  vertical: 16,
                ),
                child: Center(child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTV ? 640 : 440),
                  child: _buildStep(isTV),
                )),
              ),
            ),
          )),

          // ── Footer nav ────────────────────────────────────────────────────
          _buildFooter(isTV),
        ])),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isTV) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, isTV ? 20 : 14, 24, 0),
      child: Column(children: [
        Row(children: [
          // Logo petit
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kViolet, _kVioletL]),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: _kViolet.withOpacity(0.4), blurRadius: 10)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [_kVioletL, _kRed]).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: const Text('Arich Player', style: TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
          const Spacer(),
          // Step indicator
          Text('${ _step + 1} / $_totalSteps', style: TextStyle(
            color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 14),
        // Barre de progression
        AnimatedBuilder(
          animation: _progressCtrl,
          builder: (_, __) => ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progressCtrl.value,
              minHeight: 2.5,
              backgroundColor: Colors.white.withOpacity(0.07),
              valueColor: const AlwaysStoppedAnimation(_kViolet),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Étapes ────────────────────────────────────────────────────────────────
  Widget _buildStep(bool isTV) {
    return switch (_step) {
      0 => _StepWelcome(isTV: isTV),
      1 => _StepTheme(
          isTV: isTV, current: _themeKey,
          onChanged: (k) { setState(() => _themeKey = k); context.read<ThemeProvider>().setTheme(k); }),
      2 => _StepOrientation(
          isTV: isTV, forceLandscape: _forceLandscape,
          onChanged: (v) => setState(() => _forceLandscape = v)),
      3 => _StepQuality(
          isTV: isTV, quality: _quality,
          onChanged: (v) => setState(() => _quality = v)),
      4 => _StepPlaylist(isTV: isTV, onAddPlaylist: () => showAddPlaylistSheet(context)),
      _ => const SizedBox.shrink(),
    };
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isTV) {
    final isLast = _step == _totalSteps - 1;
    final labels = ['Continuer', 'Suivant', 'Suivant', 'Suivant', 'Terminer !'];
    final icons  = [
      Icons.arrow_forward_rounded,
      Icons.arrow_forward_rounded,
      Icons.arrow_forward_rounded,
      Icons.arrow_forward_rounded,
      Icons.rocket_launch_rounded,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, isTV ? 24 : 20),
      child: Row(children: [
        // Bouton retour
        if (_step > 0)
          GestureDetector(
            onTap: _prevStep,
            child: Container(
              height: 50, width: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white54, size: 20),
            ),
          ).animate().fadeIn(duration: 250.ms),
        if (_step > 0) const SizedBox(width: 12),

        // Bouton principal
        Expanded(child: GestureDetector(
          onTap: _nextStep,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: isLast
                  ? [_kGold, const Color(0xFFFF9F43)]
                  : [const Color(0xFF6040E8), _kViolet, _kVioletL]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color: (isLast ? _kGold : _kViolet).withOpacity(0.35),
                blurRadius: 18, offset: const Offset(0, 4))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(labels[_step], style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Icon(icons[_step], color: Colors.white, size: 18),
            ]),
          ),
        )),

        // Skip (étapes 0-2 seulement)
        if (!isLast) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _finish,
            child: Container(
              height: 50, width: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Icon(Icons.skip_next_rounded,
                  color: Colors.white.withOpacity(0.3), size: 20),
            ),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉTAPE 0 — BIENVENUE
// ══════════════════════════════════════════════════════════════════════════════
class _StepWelcome extends StatelessWidget {
  final bool isTV;
  const _StepWelcome({required this.isTV});

  @override
  Widget build(BuildContext context) {
    const features = [
      (Icons.live_tv_rounded,       Color(0xFFFF2D55), 'Direct',     'Chaînes en direct HD/FHD'),
      (Icons.movie_rounded,         Color(0xFF7C5CFC), 'Films',      'Milliers de films VOD'),
      (Icons.tv_rounded,            Color(0xFF00B4D8), 'Séries',     'Series complètes'),
      (Icons.picture_in_picture_rounded, Color(0xFFE8B84B), 'PiP', 'Multi-fenêtre'),
      (Icons.download_rounded,      Color(0xFF00D4AA), 'Offline',    'Téléchargement'),
      (Icons.grid_view_rounded,     Color(0xFFFF9F43), 'Multi-écran','2 streams simultanés'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),

      // Brand
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFAA80FF), Color(0xFFFF2D55)],
          ).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          child: Text(context.read<LanguageProvider>().l10n.t('setup_welcome'), style: TextStyle(
            color: Colors.white, fontSize: isTV ? 40 : 32,
            fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5)),
        ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05),
        SizedBox(height: 8),
        Text(context.read<LanguageProvider>().l10n.t('setup_welcome_sub'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.45), fontSize: isTV ? 15 : 13, height: 1.5)),
      ]),

      const SizedBox(height: 16),

      // Feature grid
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
          childAspectRatio: 2.8,
        ),
        itemCount: features.length,
        itemBuilder: (_, i) {
          final f = features[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Row(children: [
              Container(width: 30, height: 30,
                decoration: BoxDecoration(
                  color: f.$2.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(f.$1, color: f.$2, size: 15)),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(f.$3, style: const TextStyle(
                    color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  Text(f.$4, style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 9.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              )),
            ]),
          ).animate(delay: Duration(milliseconds: 80 + i * 50))
           .fadeIn(duration: 300.ms)
           .slideY(begin: 0.06, end: 0);
        },
      ),
      const SizedBox(height: 12),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉTAPE 1 — THÈME
// ══════════════════════════════════════════════════════════════════════════════
class _StepTheme extends StatelessWidget {
  final bool isTV;
  final String current;
  final ValueChanged<String> onChanged;
  const _StepTheme({required this.isTV, required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final themes = [
      _ThemeDef(
        key:        'dark',
        name:       'Cinéma Noir',
        desc:       'Noir OLED profond · Violet · Contrastes forts · Idéal en sombre',
        emoji:      '🎬',
        gradient:   [const Color(0xFF07070F), const Color(0xFF14103A)],
        accent:     _kViolet,
        tag:        'RECOMMANDÉ',
      ),
      _ThemeDef(
        key:        'soft',
        name:       'Nuit Douce',
        desc:       'Bleu nuit · Indigo doux · Couleurs apaisantes · Confort visuel',
        emoji:      '🌙',
        gradient:   [const Color(0xFF1A1A2E), const Color(0xFF2A2660)],
        accent:     const Color(0xFF6C63FF),
        tag:        'DOUX',
      ),
      _ThemeDef(
        key:        'blue',
        name:       'Nuit Bleue',
        desc:       'Bleu profond · Accent bleu électrique · Style moderne',
        emoji:      '💎',
        gradient:   [const Color(0xFF060B1A), const Color(0xFF0D1B3E)],
        accent:     _kBlue,
        tag:        '',
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 8),
      Text(context.read<LanguageProvider>().l10n.t('setup_visual'), style: TextStyle(
        color: Colors.white, fontSize: isTV ? 26 : 22,
        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      SizedBox(height: 4),
      Text(context.read<LanguageProvider>().l10n.t('setup_visual_sub'),
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5)),
      const SizedBox(height: 22),

      ...themes.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ThemeOptionCard(
          def: e.value, isSelected: current == e.value.key,
          onTap: () => onChanged(e.value.key),
          delay: e.key * 80,
        ),
      )),
      const SizedBox(height: 8),
    ]);
  }
}

class _ThemeDef {
  final String key, name, desc, emoji, tag;
  final List<Color> gradient;
  final Color accent;
  const _ThemeDef({
    required this.key, required this.name, required this.desc,
    required this.emoji, required this.gradient, required this.accent,
    required this.tag,
  });
}

class _ThemeOptionCard extends StatelessWidget {
  final _ThemeDef def;
  final bool isSelected;
  final VoidCallback onTap;
  final int delay;
  const _ThemeOptionCard({required this.def, required this.isSelected,
    required this.onTap, required this.delay});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: def.gradient),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? def.accent : def.accent.withOpacity(0.15),
            width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: def.accent.withOpacity(0.28), blurRadius: 20)]
              : [],
        ),
        child: Row(children: [
          Text(def.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(def.name, style: const TextStyle(
                color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              if (def.tag.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: def.accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(def.tag, style: TextStyle(
                    color: def.accent, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(def.desc, style: TextStyle(
              color: Colors.white.withOpacity(0.45), fontSize: 11, height: 1.4),
              maxLines: 2),
          ])),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isSelected ? def.accent : Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? def.accent : Colors.white.withOpacity(0.15))),
            child: isSelected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : null),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: delay))
     .fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉTAPE 2 — ORIENTATION
// ══════════════════════════════════════════════════════════════════════════════
class _StepOrientation extends StatelessWidget {
  final bool isTV, forceLandscape;
  final ValueChanged<bool> onChanged;
  const _StepOrientation({required this.isTV, required this.forceLandscape, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 8),
      Text(context.read<LanguageProvider>().l10n.t('setup_orientation'), style: TextStyle(
        color: Colors.white, fontSize: isTV ? 26 : 22,
        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      SizedBox(height: 4),
      Text(context.read<LanguageProvider>().l10n.t('setup_orientation_sub'),
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5)),
      SizedBox(height: 24),

      _OrientCard(
        icon: Icons.stay_current_landscape_rounded,
        title: context.read<LanguageProvider>().l10n.t('setup_landscape_forced'),
        desc: 'Toujours en mode paysage — recommandé pour TV et tablettes. Meilleure expérience de visionnage.',
        badge: '⭐ RECOMMANDÉ',
        badgeColor: _kGold,
        isSelected: forceLandscape,
        accent: _kViolet,
        delay: 0,
        onTap: () => onChanged(true),
      ),
      SizedBox(height: 12),
      _OrientCard(
        icon: Icons.screen_rotation_rounded,
        title: context.read<LanguageProvider>().l10n.t('setup_auto_rotation'),
        desc: 'S\'adapte à l\'orientation de votre appareil — idéal pour smartphone.',
        badge: 'FLEXIBLE',
        badgeColor: _kBlue,
        isSelected: !forceLandscape,
        accent: _kBlue,
        delay: 80,
        onTap: () => onChanged(false),
      ),
      const SizedBox(height: 12),
    ]);
  }
}

class _OrientCard extends StatelessWidget {
  final IconData icon;
  final String title, desc, badge;
  final Color badgeColor, accent;
  final bool isSelected;
  final VoidCallback onTap;
  final int delay;
  const _OrientCard({required this.icon, required this.title, required this.desc,
    required this.badge, required this.badgeColor, required this.isSelected,
    required this.accent, required this.onTap, required this.delay});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.09) : _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? accent.withOpacity(0.5) : _kBorder,
            width: isSelected ? 1.5 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: accent.withOpacity(0.2), blurRadius: 16)] : [],
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: isSelected ? accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? accent.withOpacity(0.4) : Colors.transparent)),
            child: Icon(icon, color: isSelected ? accent : Colors.white38, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(title, style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(badge, style: TextStyle(
                  color: badgeColor, fontSize: 8, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 11.5, height: 1.5),
              maxLines: 2),
          ])),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isSelected ? 1 : 0,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 13)),
          ),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: delay))
     .fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉTAPE 3 — QUALITÉ
// ══════════════════════════════════════════════════════════════════════════════
class _StepQuality extends StatelessWidget {
  final bool isTV;
  final String quality;
  final ValueChanged<String> onChanged;
  const _StepQuality({required this.isTV, required this.quality, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      _QualDef(key: 'auto',  label: context.read<LanguageProvider>().l10n.t('setup_quality_auto'), desc: context.read<LanguageProvider>().l10n.t('setup_quality_auto_desc'), icon: Icons.auto_awesome_rounded,    color: _kTeal,   tag: context.read<LanguageProvider>().l10n.t('setup_recommended')),
      _QualDef(key: 'FHD',   label: '1080p FHD',     desc: 'Full HD — nécessite 15 Mbps minimum',       icon: Icons.hd_rounded,              color: _kViolet, tag: 'MEILLEURE QUALITÉ'),
      _QualDef(key: 'HD',    label: '720p HD',        desc: 'Haute définition — 5 Mbps minimum',         icon: Icons.hd_outlined,             color: _kBlue,   tag: ''),
      _QualDef(key: 'SD',    label: '480p SD',        desc: 'Définition standard — connexion lente',     icon: Icons.sd_rounded,              color: Colors.white30, tag: 'ÉCONOME'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 8),
      Text(context.read<LanguageProvider>().l10n.t('setup_quality'), style: TextStyle(
        color: Colors.white, fontSize: isTV ? 26 : 22,
        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      SizedBox(height: 4),
      Text(context.read<LanguageProvider>().l10n.t('setup_quality_sub'),
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5)),
      const SizedBox(height: 22),

      ...options.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _QualityCard(
          def: e.value,
          isSelected: quality == e.value.key,
          onTap: () => onChanged(e.value.key),
          delay: e.key * 60,
        ),
      )),
      const SizedBox(height: 8),
    ]);
  }
}

class _QualDef {
  final String key, label, desc, tag;
  final IconData icon;
  final Color color;
  const _QualDef({required this.key, required this.label, required this.desc,
    required this.icon, required this.color, required this.tag});
}

class _QualityCard extends StatelessWidget {
  final _QualDef def;
  final bool isSelected;
  final VoidCallback onTap;
  final int delay;
  const _QualityCard({required this.def, required this.isSelected,
    required this.onTap, required this.delay});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? def.color.withOpacity(0.08) : _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? def.color.withOpacity(0.45) : _kBorder,
            width: isSelected ? 1.5 : 1)),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: isSelected ? def.color.withOpacity(0.15) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(11)),
            child: Icon(def.icon, color: isSelected ? def.color : Colors.white38, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(def.label, style: const TextStyle(
                color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              if (def.tag.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: def.color.withOpacity(0.12), borderRadius: BorderRadius.circular(3)),
                  child: Text(def.tag, style: TextStyle(
                    color: def.color, fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
              ],
            ]),
            const SizedBox(height: 2),
            Text(def.desc, style: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 11)),
          ])),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isSelected ? 1 : 0,
            child: Icon(Icons.check_circle_rounded, color: def.color, size: 20)),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: delay))
     .fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ÉTAPE 4 — AJOUTER UNE PLAYLIST
// ══════════════════════════════════════════════════════════════════════════════
class _StepPlaylist extends StatelessWidget {
  final bool isTV;
  final VoidCallback onAddPlaylist;
  const _StepPlaylist({required this.isTV, required this.onAddPlaylist});

  @override
  Widget build(BuildContext context) {
    final types = [
      (
        Icons.stream_rounded,
        _kViolet,
        'Xtream Codes',
        'Serveur · Utilisateur · Mot de passe',
      ),
      (
        Icons.list_alt_rounded,
        _kBlue,
        'Lien M3U',
        'URL directe de votre playlist M3U',
      ),
      (
        Icons.folder_rounded,
        _kTeal,
        'Fichier local',
        'Importer un fichier .m3u depuis l\'appareil',
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 8),
      ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFFAA80FF), _kRed],
        ).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
        child: Text(
          context.read<LanguageProvider>().l10n.t('onboarding_ready'),
          style: TextStyle(
            color: Colors.white,
            fontSize: isTV ? 28 : 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
      ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05),
      SizedBox(height: 6),
      Text(
        context.read<LanguageProvider>().l10n.t('onboarding_connect'),
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 12.5,
          height: 1.5,
        ),
      ).animate(delay: 100.ms).fadeIn(duration: 350.ms),
      const SizedBox(height: 24),

      // Bouton principal "Ajouter une playlist"
      GestureDetector(
        onTap: onAddPlaylist,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6040E8), _kViolet, _kVioletL],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _kViolet.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              context.read<LanguageProvider>().l10n.t('settings_add_playlist'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      ).animate(delay: 150.ms).fadeIn(duration: 400.ms).slideY(begin: 0.06),

      const SizedBox(height: 20),
      Text(
        'ou choisissez un type :',
        style: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ).animate(delay: 200.ms).fadeIn(duration: 300.ms),
      const SizedBox(height: 12),

      // Cards de type cliquables
      ...types.asMap().entries.map((e) {
        final f = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: onAddPlaylist,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: f.$2.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: f.$2.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(f.$1, color: f.$2, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.$3,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        f.$4,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: f.$2.withOpacity(0.5),
                  size: 14,
                ),
              ]),
            ),
          ).animate(delay: Duration(milliseconds: 250 + e.key * 70))
           .fadeIn(duration: 300.ms)
           .slideX(begin: 0.04, end: 0),
        );
      }),

      const SizedBox(height: 8),
      // Note : peut être ignorée
      Center(
        child: Text(
          'Vous pourrez aussi en ajouter plus tard dans les réglages',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.2),
            fontSize: 10.5,
          ),
        ),
      ).animate(delay: 500.ms).fadeIn(duration: 350.ms),
      const SizedBox(height: 12),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ANIMATED BACKGROUND
// ══════════════════════════════════════════════════════════════════════════════
class _AnimatedBg extends StatelessWidget {
  final AnimationController ctrl;
  final String themeKey;
  const _AnimatedBg({required this.ctrl, required this.themeKey});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value;
        final accent = themeKey == 'blue'
            ? _kBlue : themeKey == 'soft'
                ? const Color(0xFF6C63FF) : _kViolet;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(sin(t * pi) * 0.4 - 0.3, cos(t * pi) * 0.3 - 0.2),
              radius: 1.4,
              colors: [
                accent.withOpacity(0.07 + t * 0.04),
                _kBg,
              ],
              stops: const [0.0, 0.65],
            ),
          ),
        );
      },
    );
  }
}