// lib/ui/screens/lang_disclaimer_screen.dart
//
// Arich Player — Language + Disclaimer Screen v2.0
// ─────────────────────────────────────────────────────────────────────────────
// TOUT PREMIER écran — avant onboarding, avant setup :
//   1. Détection automatique langue système (Platform.localeName)
//   2. Sélecteur de langue plein écran style Apple Setup / Netflix
//   3. Disclaimer légal intégré, grand format, signé Arich
//   4. Checkbox accept + bouton Continuer débloqué
//   5. Layout responsive : mobile portrait / mobile paysage / TV
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';

const kLangDisclaimerDone = 'lang_disclaimer_done';

// ── Détection automatique langue depuis le système ────────────────────────────
String detectSystemLanguage() {
  try {
    final locale = Platform.localeName; // ex: "fr_FR", "en_US", "ar_DZ"
    final parts  = locale.split('_');
    final lang   = parts.first.toLowerCase();
    const supported = ['fr', 'en', 'ar', 'es', 'de'];
    if (supported.contains(lang)) return lang;

    // Fallback par région
    final region = parts.length > 1 ? parts.last.toUpperCase() : '';
    if (['FR','BE','CH','CA','MA','DZ','TN','SN','CI','LU','MC'].contains(region)) return 'fr';
    if (['SA','AE','EG','IQ','JO','KW','LB','LY','QA','SY','YE','DZ','MA','TN','OM','BH'].contains(region)) return 'ar';
    if (['ES','MX','AR','CO','CL','PE','VE','EC','GT','CU','BO','DO','HN','PY','SV','NI','CR','PA','UY'].contains(region)) return 'es';
    if (['DE','AT','CH','LI','LU'].contains(region)) return 'de';
  } catch (_) {}
  return 'fr';
}

// ═════════════════════════════════════════════════════════════════════════════
class LangDisclaimerScreen extends StatefulWidget {
  const LangDisclaimerScreen({super.key});
  @override State<LangDisclaimerScreen> createState() => _LangDisclaimerState();
}

class _LangDisclaimerState extends State<LangDisclaimerScreen>
    with TickerProviderStateMixin {

  late AnimationController _bgCtrl;
  bool _accepted = false;
  bool _showDisclaimer = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))
      ..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lp = context.read<LanguageProvider>();
      if (!lp.languageChosen) {
        final detected = detectSystemLanguage();
        if (detected != lp.currentCode) lp.setLanguage(detected);
      }
    });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onContinue() {
    if (!_accepted) {
      // Scroll vers disclaimer si pas encore accepté
      setState(() => _showDisclaimer = true);
      return;
    }
    final lp = context.read<LanguageProvider>();
    lp.markLanguageChosen();
    final box = Hive.box('settings');
    box.put('disclaimer_seen', true);
    box.put(kLangDisclaimerDone, true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lp   = context.watch<LanguageProvider>();
    final l    = lp.l10n;
    final size = MediaQuery.sizeOf(context);
    final isTV = size.width > 900;
    final isLandscape = size.width > size.height;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(children: [
        // ── Fond animé ────────────────────────────────────────────────────
        SizedBox.expand(child: RepaintBoundary(
          child: AnimatedBuilder(animation: _bgCtrl, builder: (_, __) =>
              CustomPaint(painter: _OrbPainter(_bgCtrl.value, size)))),
        ),

        // ── Contenu ───────────────────────────────────────────────────────
        SafeArea(
          child: isTV
              ? _TVLayout(
                  l: l, lp: lp,
                  accepted: _accepted,
                  onAccept: (v) => setState(() => _accepted = v),
                  onContinue: _onContinue,
                )
              : isLandscape
                  ? _LandscapeLayout(
                      l: l, lp: lp,
                      accepted: _accepted,
                      onAccept: (v) => setState(() => _accepted = v),
                      onContinue: _onContinue,
                      showDisclaimer: _showDisclaimer,
                    )
                  : _PortraitLayout(
                      l: l, lp: lp,
                      accepted: _accepted,
                      onAccept: (v) => setState(() => _accepted = v),
                      onContinue: _onContinue,
                      showDisclaimer: _showDisclaimer,
                    ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PORTRAIT LAYOUT
// ═════════════════════════════════════════════════════════════════════════════
class _PortraitLayout extends StatefulWidget {
  final AppL10n l;
  final LanguageProvider lp;
  final bool accepted, showDisclaimer;
  final ValueChanged<bool> onAccept;
  final VoidCallback onContinue;
  const _PortraitLayout({
    required this.l, required this.lp,
    required this.accepted, required this.onAccept,
    required this.onContinue, required this.showDisclaimer,
  });
  @override State<_PortraitLayout> createState() => _PortraitLayoutState();
}
class _PortraitLayoutState extends State<_PortraitLayout> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_PortraitLayout old) {
    super.didUpdateWidget(old);
    if (widget.showDisclaimer && !old.showDisclaimer) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic);
        }
      });
    }
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header ──
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(children: [
          Image.asset('assets/logo.png', height: 28, fit: BoxFit.contain),
        ]).animate().fadeIn(duration: 400.ms),
      ),

      Expanded(child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Titre ──
          _TitleSection(l: widget.l, isTV: false, currentCode: widget.lp.currentCode),
          const SizedBox(height: 32),

          // ── Sélecteur langue ──
          _LangGrid(l: widget.l, lp: widget.lp, isTV: false),
          const SizedBox(height: 32),

          // ── Disclaimer ──
          _DisclaimerCard(
            l: widget.l,
            accepted: widget.accepted,
            onAccept: widget.onAccept,
            isTV: false,
          ),
          const SizedBox(height: 16),
        ]),
      )),

      // ── Bouton ──
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: _ContinueButton(
          l: widget.l, accepted: widget.accepted,
          onTap: widget.onContinue,
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LANDSCAPE LAYOUT
// ═════════════════════════════════════════════════════════════════════════════
class _LandscapeLayout extends StatelessWidget {
  final AppL10n l;
  final LanguageProvider lp;
  final bool accepted, showDisclaimer;
  final ValueChanged<bool> onAccept;
  final VoidCallback onContinue;
  const _LandscapeLayout({
    required this.l, required this.lp,
    required this.accepted, required this.onAccept,
    required this.onContinue, required this.showDisclaimer,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Gauche : lang selector
        Expanded(flex: 5, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/logo.png', height: 24, fit: BoxFit.contain)
                .animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 20),
            _TitleSection(l: l, isTV: false, currentCode: lp.currentCode),
            const SizedBox(height: 20),
            Expanded(child: SingleChildScrollView(
              child: _LangGrid(l: l, lp: lp, isTV: false),
            )),
            const SizedBox(height: 16),
            _ContinueButton(l: l, accepted: accepted, onTap: onContinue),
          ],
        )),
        const SizedBox(width: 28),
        // Droite : disclaimer
        Expanded(flex: 4, child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 44),
            _DisclaimerCard(
              l: l, accepted: accepted,
              onAccept: onAccept, isTV: false,
            ),
          ]),
        )),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TV LAYOUT
// ═════════════════════════════════════════════════════════════════════════════
class _TVLayout extends StatelessWidget {
  final AppL10n l;
  final LanguageProvider lp;
  final bool accepted;
  final ValueChanged<bool> onAccept;
  final VoidCallback onContinue;
  const _TVLayout({
    required this.l, required this.lp,
    required this.accepted, required this.onAccept,
    required this.onContinue,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 5, child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/logo.png', height: 38, fit: BoxFit.contain)
                .animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 36),
            _TitleSection(l: l, isTV: true, currentCode: lp.currentCode),
            const SizedBox(height: 36),
            _LangGrid(l: l, lp: lp, isTV: true),
            const SizedBox(height: 40),
            _ContinueButton(l: l, accepted: accepted, onTap: onContinue),
          ],
        )),
        const SizedBox(width: 64),
        Expanded(flex: 4, child: _DisclaimerCard(
          l: l, accepted: accepted,
          onAccept: onAccept, isTV: true,
        )),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// COMPOSANTS PARTAGÉS
// ═════════════════════════════════════════════════════════════════════════════

// ── Titre section ─────────────────────────────────────────────────────────────
class _TitleSection extends StatelessWidget {
  final AppL10n l;
  final bool isTV;
  final String currentCode;
  const _TitleSection({required this.l, required this.isTV, required this.currentCode});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Globe icon + titre
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: isTV ? 48 : 40, height: isTV ? 48 : 40,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
              color: AppTheme.violet.withOpacity(0.4),
              blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Icon(Icons.language_rounded, color: Colors.white,
              size: isTV ? 24 : 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: ShaderMask(
          shaderCallback: (b) => AppTheme.gradientHorizontal
              .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          child: Text(l.t('lang_pick_title'),
            style: GoogleFonts.rajdhani(
              fontSize: isTV ? 42 : 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.0,
            )),
        )),
      ]).animate().fadeIn(duration: 500.ms).slideX(begin: -0.04, end: 0),
      const SizedBox(height: 10),
      Text(l.t('lang_pick_subtitle'),
        style: GoogleFonts.inter(
          fontSize: isTV ? 14 : 12,
          color: Colors.white38,
          height: 1.4,
        )).animate(delay: 80.ms).fadeIn(duration: 400.ms),
      const SizedBox(height: 12),
      // Badge "Détecté automatiquement"
      _DetectedBadge(l: l, code: currentCode)
          .animate(delay: 160.ms).fadeIn(duration: 400.ms),
    ]);
  }
}

class _DetectedBadge extends StatelessWidget {
  final AppL10n l;
  final String code;
  const _DetectedBadge({required this.l, required this.code});

  @override
  Widget build(BuildContext context) {
    final flag = AppL10n.languages
        .firstWhere((e) => e.$3 == code, orElse: () => AppL10n.languages.first).$2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.gps_fixed_rounded, color: AppTheme.success, size: 11),
        const SizedBox(width: 5),
        Text('$flag  ${l.t('lang_auto_detected')}',
          style: GoogleFonts.inter(
            color: AppTheme.success, fontSize: 11,
            fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Grille de langues ─────────────────────────────────────────────────────────
class _LangGrid extends StatelessWidget {
  final AppL10n l;
  final LanguageProvider lp;
  final bool isTV;
  const _LangGrid({required this.l, required this.lp, required this.isTV});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: AppL10n.languages.asMap().entries.map((e) {
        final lang     = e.value;
        final selected = lp.currentCode == lang.$3;
        return _LangTile(
          flag: lang.$2, name: lang.$1, code: lang.$3,
          selected: selected, isTV: isTV,
          delay: e.key * 55,
          onTap: () => context.read<LanguageProvider>().setLanguage(lang.$3),
        );
      }).toList(),
    );
  }
}

class _LangTile extends StatefulWidget {
  final String flag, name, code;
  final bool selected, isTV;
  final int delay;
  final VoidCallback onTap;
  const _LangTile({required this.flag, required this.name, required this.code,
      required this.selected, required this.isTV, required this.delay,
      required this.onTap});
  @override State<_LangTile> createState() => _LangTileState();
}
class _LangTileState extends State<_LangTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_)   => setState(() { _pressed = false; widget.onTap(); }),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
          transformAlignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: widget.isTV ? 15 : 12),
          decoration: BoxDecoration(
            gradient: widget.selected ? LinearGradient(colors: [
              AppTheme.violet.withOpacity(0.20),
              AppTheme.red.withOpacity(0.08),
            ]) : null,
            color: widget.selected ? null : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? AppTheme.violet.withOpacity(0.55)
                  : Colors.white.withOpacity(0.07),
              width: widget.selected ? 1.5 : 1),
            boxShadow: widget.selected ? [BoxShadow(
              color: AppTheme.violet.withOpacity(0.15),
              blurRadius: 12, offset: const Offset(0, 3))
            ] : [],
          ),
          child: Row(children: [
            // Emoji flag
            Text(widget.flag, style: TextStyle(fontSize: widget.isTV ? 22 : 18)),
            const SizedBox(width: 14),
            // Nom
            Expanded(child: Text(widget.name,
              style: GoogleFonts.inter(
                color: widget.selected ? Colors.white : Colors.white54,
                fontSize: widget.isTV ? 16 : 14,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400))),
            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                gradient: widget.selected ? AppTheme.gradientPrimary : null,
                color: widget.selected ? null : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.selected
                      ? Colors.transparent
                      : Colors.white.withOpacity(0.18),
                  width: 1.5)),
              child: widget.selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                  : null),
          ]),
        ),
      ).animate(delay: Duration(milliseconds: widget.delay))
          .fadeIn(duration: 300.ms)
          .slideX(begin: -0.05, end: 0, curve: Curves.easeOutCubic),
    );
  }
}

// ── Disclaimer card ───────────────────────────────────────────────────────────
class _DisclaimerCard extends StatelessWidget {
  final AppL10n l;
  final bool accepted, isTV;
  final ValueChanged<bool> onAccept;
  const _DisclaimerCard({
    required this.l, required this.accepted,
    required this.onAccept, required this.isTV,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.all(isTV ? 28 : 22),
      decoration: BoxDecoration(
        color: accepted
            ? AppTheme.success.withOpacity(0.05)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accepted
              ? AppTheme.success.withOpacity(0.35)
              : AppTheme.violet.withOpacity(0.18),
          width: 1.5),
        boxShadow: [
          BoxShadow(
            color: (accepted ? AppTheme.success : AppTheme.violet).withOpacity(0.08),
            blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [

        // ── Header ──
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icône
          Container(
            width: isTV ? 42 : 36, height: isTV ? 42 : 36,
            decoration: BoxDecoration(
              gradient: accepted
                  ? const LinearGradient(colors: [AppTheme.success, Color(0xFF25A244)])
                  : AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [BoxShadow(
                color: (accepted ? AppTheme.success : AppTheme.violet).withOpacity(0.35),
                blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Icon(
              accepted ? Icons.verified_rounded : Icons.gavel_rounded,
              color: Colors.white, size: isTV ? 20 : 17),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('disclaimer_title'),
              style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: isTV ? 20 : 16,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            // Séparateur gradient
            Container(height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  accepted
                      ? AppTheme.success.withOpacity(0.5)
                      : AppTheme.violet.withOpacity(0.4),
                  Colors.transparent,
                ]))),
          ])),
        ]),

        const SizedBox(height: 16),

        // ── Corps du disclaimer ──
        Text(l.t('disclaimer_body'),
          style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.55),
            fontSize: isTV ? 13 : 12,
            height: 1.65)),

        const SizedBox(height: 4),

        // Signature
        Align(alignment: Alignment.centerRight,
          child: Text('— Arich Player',
            style: GoogleFonts.inter(
              color: AppTheme.violet.withOpacity(0.6),
              fontSize: 11, fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500))),

        const SizedBox(height: 18),

        // ── Séparateur ──
        Container(height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.08),
              Colors.transparent,
            ]))),
        const SizedBox(height: 16),

        // ── Checkbox accepter ──
        GestureDetector(
          onTap: () => onAccept(!accepted),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Custom checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isTV ? 26 : 22, height: isTV ? 26 : 22,
              decoration: BoxDecoration(
                gradient: accepted ? AppTheme.gradientPrimary : null,
                color: accepted ? null : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: accepted
                      ? AppTheme.violet
                      : Colors.white.withOpacity(0.22),
                  width: 1.5),
                boxShadow: accepted ? [BoxShadow(
                  color: AppTheme.violet.withOpacity(0.4),
                  blurRadius: 8)] : [],
              ),
              child: accepted
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('disclaimer_accept'),
              style: GoogleFonts.inter(
                color: accepted ? Colors.white : Colors.white60,
                fontSize: isTV ? 13 : 12,
                fontWeight: accepted ? FontWeight.w600 : FontWeight.w400))),
          ]),
        ),
      ]),
    ).animate().fadeIn(delay: 250.ms, duration: 400.ms)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

// ── Bouton Continuer ──────────────────────────────────────────────────────────
class _ContinueButton extends StatefulWidget {
  final AppL10n l;
  final bool accepted;
  final VoidCallback onTap;
  const _ContinueButton({required this.l, required this.accepted, required this.onTap});
  @override State<_ContinueButton> createState() => _ContinueButtonState();
}
class _ContinueButtonState extends State<_ContinueButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.accepted ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
          transformAlignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: widget.accepted
                ? AppTheme.gradientPrimary
                : LinearGradient(colors: [
                    AppTheme.violet.withOpacity(0.5),
                    AppTheme.red.withOpacity(0.4),
                  ]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.accepted ? [
              BoxShadow(
                color: AppTheme.violet.withOpacity(0.45),
                blurRadius: 20, offset: const Offset(0, 6)),
            ] : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.l.t('lang_pick_btn'),
              style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ]),
        ),
      ),
    ).animate(delay: 400.ms).fadeIn(duration: 400.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BACKGROUND PAINTER — orbs flottants
// ═════════════════════════════════════════════════════════════════════════════
class _OrbPainter extends CustomPainter {
  final double p;
  final Size screen;
  const _OrbPainter(this.p, this.screen);

  @override
  void paint(Canvas canvas, Size s) {
    final orbs = [
      (fx: 0.12, fy: 0.18, r: 0.55, c: AppTheme.violet,    op: 0.08),
      (fx: 0.88, fy: 0.78, r: 0.45, c: AppTheme.red,       op: 0.06),
      (fx: 0.50, fy: 0.45, r: 0.38, c: AppTheme.secondary, op: 0.04),
    ];
    for (final o in orbs) {
      final cx = s.width  * (o.fx + math.sin(p * math.pi * 2) * 0.06);
      final cy = s.height * (o.fy + math.cos(p * math.pi * 2) * 0.04);
      final r  = s.shortestSide * o.r;
      canvas.drawCircle(Offset(cx, cy),
        r,
        Paint()
          ..color = o.c.withOpacity(o.op)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90));
    }
  }

  @override bool shouldRepaint(_OrbPainter o) => o.p != p;
}