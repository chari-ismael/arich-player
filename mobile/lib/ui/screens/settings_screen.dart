// lib/ui/screens/settings_screen.dart
// ARICH Player — Settings Screen v18 — REFONTE DESIGN COMPLÈTE
// ─────────────────────────────────────────────────────────────────────────────
// [v18] Refonte visuelle totale :
//   • Sidebar : gradient accent par section + avatar profil premium
//   • Cards : glassmorphism + border subtile
//   • Section header : icône large avec gradient + underline accent
//   • Rows : icône colorée + focus glow
//   • Toggles : animation fluide iOS-style
//   • Layout mobile : nav pills scrollable avec gradient actif
//   • Boutons : gradient premium + danger redesigné
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/theme_provider.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../models/playlist_account.dart';
import '../../core/tv_navigation.dart';
import '../../core/l10n.dart';
import '../../services/download_service.dart';
import 'downloads_screen.dart';
import '../../providers/language_provider.dart';
import '../widgets/parental_gate.dart';
import '../widgets/focusable_ink.dart';
import '../widgets/add_playlist_sheet.dart';
import 'login_screen.dart';
import 'license_screen.dart';
import 'profile_screen.dart';

const _kNotifs     = 'pref_notifications';
const _kAutoplay   = 'pref_autoplay';
const _kHideLive   = 'pref_hide_live';
const _kHideMovies = 'pref_hide_movies';
const _kHideSeries = 'pref_hide_series';
const _kForceLand  = 'pref_force_landscape';
const _kCacheImg   = 'pref_cache_images';
const _kQuality    = 'pref_stream_quality';

Future<void> _applyOrientation(bool force) async {
  await SystemChrome.setPreferredOrientations(force
      ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
         DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
}

class _T {
  static const bg        = AppTheme.background;
  static const surface   = AppTheme.surface;
  static const surfaceHi = AppTheme.surfaceHigh;
  static const violet    = AppTheme.violet;
  static const red       = AppTheme.red;
  static const blue      = AppTheme.secondary;
  static const green     = AppTheme.success;
  static const gold      = AppTheme.gold;
  static const orange    = Color(0xFFFF9F0A);
  static const cyan      = Color(0xFF32ADE6);
  static const textPri   = AppTheme.textPrimary;
  static const textSec   = AppTheme.textSecondary;
  static const textMut   = AppTheme.textMuted;
}

enum _Sec { profile, playlists, display, preferences, account, support, data }

extension _SecX on _Sec {
  String label(AppL10n l) => switch (this) {
    _Sec.profile     => l.t('settings_profile'),
    _Sec.playlists   => l.t('settings_playlists'),
    _Sec.display     => l.t('settings_display'),
    _Sec.preferences => l.t('settings_preferences'),
    _Sec.account     => l.t('settings_account'),
    _Sec.support     => l.t('settings_support'),
    _Sec.data        => l.t('settings_data'),
  };
  IconData get icon => switch (this) {
    _Sec.profile     => Icons.person_rounded,
    _Sec.playlists   => Icons.playlist_play_rounded,
    _Sec.display     => Icons.palette_rounded,
    _Sec.preferences => Icons.tune_rounded,
    _Sec.account     => Icons.manage_accounts_rounded,
    _Sec.support     => Icons.help_outline_rounded,
    _Sec.data        => Icons.storage_rounded,
  };
  Color get color => switch (this) {
    _Sec.profile     => _T.violet,
    _Sec.playlists   => _T.blue,
    _Sec.display     => _T.cyan,
    _Sec.preferences => _T.gold,
    _Sec.account     => _T.green,
    _Sec.support     => _T.red,
    _Sec.data        => _T.orange,
  };
  Color get color2 => switch (this) {
    _Sec.profile     => const Color(0xFFFF2D55),
    _Sec.playlists   => const Color(0xFF5AC8FA),
    _Sec.display     => const Color(0xFF5E5CE6),
    _Sec.preferences => const Color(0xFFFF9F0A),
    _Sec.account     => const Color(0xFF34C759),
    _Sec.support     => const Color(0xFFFF6B6B),
    _Sec.data        => const Color(0xFFFF6B00),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  _Sec _active = _Sec.profile;
  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  }

  @override
  void dispose() { _bgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l      = context.read<LanguageProvider>().l10n;
    final theme  = context.watch<ThemeProvider>();
    final isTV   = context.isTV;
    final sz     = MediaQuery.sizeOf(context);
    final useSide = isTV || sz.width > sz.height;

    return Scaffold(
      backgroundColor: AppTheme.backgroundForTheme(theme.themeKey),
      body: Stack(children: [
        SizedBox.expand(child: RepaintBoundary(
          child: AnimatedBuilder(animation: _bgCtrl,
            builder: (_, __) => CustomPaint(
              painter: _BgPainter(_bgCtrl.value, _active, theme.themeKey))))),
        SizedBox.expand(
          child: useSide
              ? _SideLayout(active: _active, onSelect: (s) => setState(() => _active = s),
                  l: l, isTV: isTV, content: _buildContent(_active, l, theme, isTV))
              : _MobileLayout(active: _active, onSelect: (s) => setState(() => _active = s),
                  l: l, content: _buildContent(_active, l, theme, false))),
      ]),
    );
  }

  Widget _buildContent(_Sec sec, AppL10n l, ThemeProvider t, bool isTV) => switch (sec) {
    _Sec.profile     => _ProfileSection(l: l, t: t),
    _Sec.playlists   => _PlaylistsSection(l: l, t: t),
    _Sec.display     => _DisplaySection(l: l, t: t),
    _Sec.preferences => _PrefsSection(l: l, t: t),
    _Sec.account     => _AccountSection(l: l, t: t, onRefresh: () => setState(() {})),
    _Sec.support     => _SupportSection(l: l, t: t),
    _Sec.data        => _DataSection(l: l, t: t),
  };
}

// ── Background ────────────────────────────────────────────────────────────────
class _BgPainter extends CustomPainter {
  final double p; final _Sec sec; final String themeKey;
  _BgPainter(this.p, this.sec, this.themeKey);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s,
        Paint()..color = AppTheme.backgroundForTheme(themeKey));
    for (final o in [
      (x: s.width * 0.08, y: s.height * 0.12, r: 220.0, op: 0.055),
      (x: s.width * 0.92, y: s.height * 0.72, r: 180.0, op: 0.035),
    ]) {
      canvas.drawCircle(
        Offset(o.x + math.sin(p * math.pi * 2) * 30,
               o.y + math.cos(p * math.pi * 2) * 20),
        o.r,
        Paint()..color = sec.color.withOpacity(o.op)
               ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70));
    }
  }
  @override bool shouldRepaint(_BgPainter o) => o.p != p || o.sec != sec || o.themeKey != themeKey;
}

// ── Side layout — sidebar icons-only style VSCode ─────────────────────────────
class _SideLayout extends StatelessWidget {
  final _Sec active; final ValueChanged<_Sec> onSelect;
  final AppL10n l; final bool isTV; final Widget content;
  const _SideLayout({required this.active, required this.onSelect,
      required this.l, required this.isTV, required this.content});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final initial = user?.email?.isNotEmpty == true ? user!.email![0].toUpperCase() : 'A';

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── Sidebar icons-only 64px ──────────────────────────────────────────
      Container(
        width: isTV ? 72 : 64,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          border: Border(right: BorderSide(
              color: active.color.withOpacity(0.15), width: 1))),
        child: Column(children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + (isTV ? 20 : 12)),

          // Logo / avatar en haut
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: user?.email ?? 'Arich Player',
              preferBelow: false,
              child: Container(
                width: isTV ? 40 : 34, height: isTV ? 40 : 34,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: AppTheme.violet.withOpacity(0.35), blurRadius: 10)]),
                child: Center(child: Text(initial, style: GoogleFonts.rajdhani(
                    fontSize: isTV ? 18 : 15, fontWeight: FontWeight.w700,
                    color: Colors.white))),
              ),
            ),
          ),

          Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.white.withOpacity(0.06)),

          // Items
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _Sec.values.length,
            itemBuilder: (_, i) {
              final sec = _Sec.values[i];
              final isActive = sec == active;
              return _IconSideItem(
                sec: sec, isActive: isActive, isTV: isTV,
                onTap: () => onSelect(sec),
              ).animate(delay: (i * 35).ms)
                  .fadeIn(duration: 240.ms)
                  .slideX(begin: -0.08, end: 0, curve: Curves.easeOutCubic);
            },
          )),

          // Back button en bas
          Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.white.withOpacity(0.06)),
          Padding(
            padding: EdgeInsets.only(bottom: isTV ? 20 : 14),
            child: Tooltip(
              message: 'Retour',
              preferBelow: false,
              child: FocusableInk(
                onTap: () => Navigator.maybePop(context),
                borderRadius: 10,
                child: Container(
                  width: isTV ? 40 : 34, height: isTV ? 40 : 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white38, size: 13),
                ),
              ),
            ),
          ),
        ]),
      ),

      // ── Indicateur actif (ligne colorée entre sidebar et contenu) ──────────
      Container(
        width: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, active.color, Colors.transparent],
          ),
        ),
      ),

      // ── Contenu ─────────────────────────────────────────────────────────
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header section actif
        _SectionHeader(sec: active, isTV: isTV, l: l),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(isTV ? 28 : 18, 8, isTV ? 28 : 18, 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                    begin: const Offset(0.02, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child),
            ),
            child: KeyedSubtree(key: ValueKey(active), child: content),
          ),
        )),
      ])),
    ]);
  }
}

// ── Icon sidebar item avec tooltip ────────────────────────────────────────────
class _IconSideItem extends StatefulWidget {
  final _Sec sec; final bool isActive, isTV;
  final VoidCallback onTap;
  const _IconSideItem({required this.sec, required this.isActive,
      required this.isTV, required this.onTap});
  @override State<_IconSideItem> createState() => _IconSideItemState();
}

class _IconSideItemState extends State<_IconSideItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final sec = widget.sec;
    final isActive = widget.isActive;
    final size = widget.isTV ? 38.0 : 34.0;
    final iconSize = widget.isTV ? 17.0 : 15.0;

    return Tooltip(
      message: sec.label(context.read<LanguageProvider>().l10n),
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: FocusableInk(
            onTap: widget.onTap,
            borderRadius: 12,
            focusColor: sec.color,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              height: size,
              decoration: BoxDecoration(
                gradient: isActive ? LinearGradient(colors: [
                  sec.color.withOpacity(0.22),
                  sec.color2.withOpacity(0.10),
                ]) : null,
                color: isActive ? null : (_focused
                    ? Colors.white.withOpacity(0.06) : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive
                      ? sec.color.withOpacity(0.45)
                      : _focused
                          ? sec.color.withOpacity(0.25)
                          : Colors.transparent,
                  width: isActive ? 1.5 : 1,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: sec.color.withOpacity(0.2),
                        blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Stack(alignment: Alignment.center, children: [
                if (isActive)
                  Positioned(left: 0, top: 8, bottom: 8,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [sec.color, sec.color2]),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [BoxShadow(
                            color: sec.color.withOpacity(0.6), blurRadius: 6)],
                      ),
                    ),
                  ),
                Icon(sec.icon, size: iconSize,
                  color: isActive ? sec.color : Colors.white38),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final _Sec sec; final bool isTV; final AppL10n l;
  const _SectionHeader({required this.sec, required this.l, this.isTV = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
        isTV ? 28 : 18,
        MediaQuery.paddingOf(context).top + (isTV ? 20 : 14),
        isTV ? 28 : 18,
        isTV ? 16 : 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(
          color: sec.color.withOpacity(0.15), width: 1))),
    child: Row(children: [
      // Icon pill gradient
      Container(
        width: isTV ? 36 : 30, height: isTV ? 36 : 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [sec.color.withOpacity(0.9), sec.color2.withOpacity(0.7)]),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [BoxShadow(
              color: sec.color.withOpacity(0.35), blurRadius: 10)]),
        child: Icon(sec.icon, color: Colors.white, size: isTV ? 17 : 14),
      ),
      const SizedBox(width: 12),
      ShaderMask(
        shaderCallback: (b) => LinearGradient(
            colors: [sec.color, sec.color2])
            .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
        child: Text(sec.label(l), style: GoogleFonts.rajdhani(
            fontSize: isTV ? 20 : 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5)),
      ),
    ]),
  );
}

// ── Mobile layout — pills + contenu épuré ────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  final _Sec active; final ValueChanged<_Sec> onSelect;
  final AppL10n l; final Widget content;
  const _MobileLayout({required this.active, required this.onSelect,
      required this.l, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: EdgeInsets.fromLTRB(
            10, MediaQuery.paddingOf(context).top + 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
              color: active.color.withOpacity(0.14), width: 1))),
        child: Row(children: [
          FocusableInk(
            onTap: () => Navigator.maybePop(context),
            borderRadius: 10,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white38, size: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Paramètres',
              style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: 0.4))),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          itemCount: _Sec.values.length,
          itemBuilder: (_, i) {
            final sec = _Sec.values[i];
            final isActive = sec == active;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FocusableInk(
                onTap: () => onSelect(sec),
                borderRadius: 20,
                focusColor: sec.color,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive ? sec.color.withOpacity(0.16) : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? sec.color.withOpacity(0.45) : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(sec.icon, size: 13, color: isActive ? sec.color : Colors.white38),
                    const SizedBox(width: 6),
                    Text(sec.label(l),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? Colors.white : Colors.white54,
                      )),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 28),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                  begin: const Offset(0.02, 0), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
              child: child),
          ),
          child: KeyedSubtree(
              key: ValueKey(active), child: content),
        ),
      )),
    ]);
  }
}

// ── Mobile drawer ─────────────────────────────────────────────────────────────
class _MobileDrawer extends StatelessWidget {
  final _Sec active; final dynamic user;
  final AppL10n l; final ValueChanged<_Sec> onSelect;
  const _MobileDrawer({required this.active, required this.user,
      required this.l, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final initial = user?.email?.isNotEmpty == true
        ? user!.email![0].toUpperCase() : 'A';
    final isTizen = Platform.operatingSystem == 'tizen';

    Widget inner = Container(
      width: 240,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isTizen ? 0.97 : 0.75),
        border: Border(right: BorderSide(
            color: active.color.withOpacity(0.2), width: 1)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24, offset: const Offset(4, 0))],
      ),
      child: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: AppTheme.violet.withOpacity(0.4), blurRadius: 10)]),
                child: Center(child: Text(initial, style: GoogleFonts.rajdhani(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Colors.white))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (b) => AppTheme.gradientHorizontal
                        .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                    child: Text('Arich Player', style: GoogleFonts.rajdhani(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: 1)),
                  ),
                  Text(user?.email ?? context.read<LanguageProvider>().l10n.t('not_authenticated'),
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                      overflow: TextOverflow.ellipsis),
                ],
              )),
            ]),
          ),
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 8),

          // Items
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _Sec.values.length,
            itemBuilder: (_, i) {
              final sec = _Sec.values[i];
              final isActive = sec == active;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: FocusableInk(
                  onTap: () => onSelect(sec),
                  borderRadius: 12,
                  focusColor: sec.color,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? sec.color.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? sec.color.withOpacity(0.35) : Colors.transparent,
                      ),
                    ),
                    child: Row(children: [
                      // Icon pill
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          gradient: isActive ? LinearGradient(colors: [
                            sec.color.withOpacity(0.9),
                            sec.color2.withOpacity(0.7),
                          ]) : null,
                          color: isActive ? null : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: isActive ? [BoxShadow(
                              color: sec.color.withOpacity(0.35),
                              blurRadius: 8)] : null,
                        ),
                        child: Icon(sec.icon, size: 13,
                            color: isActive ? Colors.white : Colors.white38),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(sec.label(l),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w600 : FontWeight.w400,
                          color: isActive ? Colors.white : Colors.white54),
                        overflow: TextOverflow.ellipsis,
                      )),
                      if (isActive)
                        Container(width: 6, height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: [sec.color, sec.color2]),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: sec.color.withOpacity(0.6),
                                blurRadius: 4)],
                          ),
                        ),
                    ]),
                  ),
                ),
              ).animate(delay: (i * 25).ms)
                  .fadeIn(duration: 200.ms)
                  .slideX(begin: -0.06, end: 0);
            },
          )),

          // Footer version
          Container(height: 1, color: Colors.white.withOpacity(0.05)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(children: [
              Container(width: 6, height: 6,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: AppTheme.violet.withOpacity(0.6), blurRadius: 4)])),
              const SizedBox(width: 7),
              Text('v2.1.0', style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.white24, letterSpacing: 0.5)),
            ]),
          ),
        ],
      )),
    );

    if (!isTizen) {
      inner = ClipRect(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: inner));
    }
    return inner;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BASE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String? title; final IconData? icon; final Color? color;
  final List<Widget> children; final EdgeInsets? padding;
  const _Card({this.title, this.icon, this.color,
      required this.children, this.padding});
  @override
  Widget build(BuildContext context) {
    final c = color ?? _T.violet;
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) ...[
          Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              if (icon != null) ...[
                Container(padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
                  child: Icon(icon, color: c, size: 12)),
                const SizedBox(width: 7),
              ],
              Expanded(child: Text(title!, style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: Colors.white70, letterSpacing: 0.3))),
            ])),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
        ],
        ...children,
      ]),
    );
  }
}

class _RowItem extends StatelessWidget {
  final IconData icon; final Color color; final String label;
  final String? subtitle; final Widget? trailing;
  final VoidCallback? onTap; final bool isLast;
  const _RowItem({required this.icon, required this.color, required this.label,
      this.subtitle, this.trailing, this.onTap, this.isLast = false});
  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(width: 33, height: 33,
          decoration: BoxDecoration(
            color: color.withOpacity(0.13), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.22))),
          child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 12),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: GoogleFonts.inter(fontSize: 11, color: _T.textSec)),
          ],
        ])),
        if (trailing != null) trailing!,
      ]),
    );
    if (!isLast) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        content,
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Divider(color: Colors.white.withOpacity(0.05), height: 1)),
      ]);
    }
    return onTap != null
        ? FocusableInk(onTap: onTap!, borderRadius: 0, child: content)
        : content;
  }
}

class _Toggle extends StatefulWidget {
  final bool value; final ValueChanged<bool> onChanged; final Color color;
  const _Toggle({required this.value, required this.onChanged, this.color = _T.violet});
  @override State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> with SingleTickerProviderStateMixin {
  late bool _v;
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _v = widget.value;
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 200), value: _v ? 1.0 : 0.0);
  }
  @override
  void didUpdateWidget(_Toggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _v = widget.value;
      _v ? _ctrl.forward() : _ctrl.reverse();
    }
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FocusableInk(
    onTap: () {
      final next = !_v;
      setState(() => _v = next);
      next ? _ctrl.forward() : _ctrl.reverse();
      widget.onChanged(next);
    },
    borderRadius: 13,
    focusColor: widget.color,
    child: AnimatedBuilder(animation: _ctrl, builder: (_, __) => Container(
      width: 46, height: 26,
      decoration: BoxDecoration(
        color: Color.lerp(
          Colors.white.withOpacity(0.1), widget.color.withOpacity(0.28), _ctrl.value),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Color.lerp(Colors.white.withOpacity(0.15),
              widget.color.withOpacity(0.6), _ctrl.value)!,
          width: 1.5),
        boxShadow: _v ? [BoxShadow(
            color: widget.color.withOpacity(0.22 * _ctrl.value), blurRadius: 8)] : []),
      child: Padding(padding: const EdgeInsets.all(3),
        child: Align(
          alignment: Alignment.lerp(
              Alignment.centerLeft, Alignment.centerRight, _ctrl.value)!,
          child: Container(width: 18, height: 18,
            decoration: BoxDecoration(
              color: Color.lerp(_T.textSec, Colors.white, _ctrl.value),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.25), blurRadius: 4,
                  offset: const Offset(0, 1))])))),
    )),
  );
}


class _Group extends StatelessWidget {
  final String label; final List<Widget> children; final Color? accentColor;
  const _Group({required this.label, required this.children, this.accentColor});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(children: [
          if (accentColor != null) ...[
            Container(width: 3, height: 12,
              decoration: BoxDecoration(
                color: accentColor!, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label.toUpperCase(), style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: accentColor?.withOpacity(0.7) ?? _T.textMut,
            letterSpacing: 1.2), overflow: TextOverflow.ellipsis)),
        ])),
      _Card(children: children),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTIONS
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t;
  const _ProfileSection({required this.l, required this.t});
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      if (user != null) ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _T.violet.withOpacity(0.15), _T.red.withOpacity(0.07), Colors.transparent],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _T.violet.withOpacity(0.25))),
          child: Row(children: [
            Container(width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _T.violet.withOpacity(0.5), blurRadius: 16)]),
              child: Center(child: Text(
                user.email?.isNotEmpty == true ? user.email![0].toUpperCase() : 'U',
                style: GoogleFonts.rajdhani(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)))),
            const SizedBox(width: 16),
            Expanded(child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.email ?? 'Utilisateur', style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: _T.violet.withOpacity(0.35), blurRadius: 6)]),
                child: Text(context.read<LanguageProvider>().l10n.t('settings_pro_member'), style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
            ])),
          ])).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 10),
        _Card(children: [
          _RowItem(icon: Icons.edit_rounded, color: _T.violet,
            label: context.read<LanguageProvider>().l10n.t('settings_edit_profile'), subtitle: context.read<LanguageProvider>().l10n.t('settings_edit_profile_desc'),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => const ProfileScreen(),
              transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c))),
            isLast: true),
        ]).animate(delay: 60.ms).fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
      ] else ...[
        _EmptyStateCard(
          icon: Icons.person_outline_rounded, color: Colors.white24,
          title: context.read<LanguageProvider>().l10n.t('not_authenticated'), subtitle: context.read<LanguageProvider>().l10n.t('settings_login_to_access'),
          btnLabel: context.read<LanguageProvider>().l10n.t('arich_signin'), btnIcon: Icons.login_rounded,
          onTap: () => Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LoginScreen(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)))),
      ],
    ]);
  }
}

class _PlaylistsSection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t;
  const _PlaylistsSection({required this.l, required this.t});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Consumer<PlaylistProvider>(builder: (_, pp, __) {
        final accounts = pp.accounts; // snapshot stable, évite les mutations concurrentes
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Liste vide ────────────────────────────────────────────────
            if (accounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.07))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.playlist_add_rounded,
                      color: _T.blue.withOpacity(0.5), size: 36),
                  const SizedBox(height: 10),
                  Text(
                    context.read<LanguageProvider>().l10n.t('no_playlists'),
                    style: GoogleFonts.inter(color: _T.textSec, fontSize: 13),
                    textAlign: TextAlign.center),
                ]))

            // ── Liste playlists ───────────────────────────────────────────
            // [FIX] RangeError : on construit la liste seulement si accounts
            // est non vide. isLast compare e.key avec accounts.length - 1
            // ce qui était -1 quand accounts était vide → crash.
            else
              _Group(
                label: context.read<LanguageProvider>().l10n.t('settings_playlists'),
                accentColor: _T.blue,
                children: List.generate(accounts.length, (i) {
                  final acc   = accounts[i];
                  final isAct = acc.id == pp.activeAccount?.id;
                  return _RowItem(
                    icon: isAct
                        ? Icons.check_circle_rounded
                        : Icons.playlist_play_rounded,
                    color:    isAct ? _T.green : _T.blue,
                    label:    acc.name,
                    subtitle: acc.type == PlaylistType.xtream
                        ? 'Xtream Codes' : 'M3U',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      _IconBtn(
                        icon: Icons.tune_rounded,
                        color: _T.violet,
                        onTap: () => showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _EditPlaylistSheet(account: acc))),
                      const SizedBox(width: 4),
                      _IconBtn(
                        icon: Icons.delete_outline_rounded,
                        color: _T.red,
                        onTap: () {
                          pp.remove(acc.id);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(context
                                .read<LanguageProvider>().l10n
                                .t('playlist_removed'))));
                        }),
                    ]),
                    onTap: () async {
                      // [FIX] setActive met à jour Hive, puis on recharge IptvProvider
                      pp.setActive(acc.id);
                      final iptv = context.read<IptvProvider>();
                      if (acc.type == PlaylistType.m3u) {
                        await iptv.loginM3u(acc.m3uUrl);
                      } else {
                        await iptv.login(acc.serverUrl, acc.username, acc.password);
                      }
                    },
                    // [FIX] isLast calculé sur la longueur réelle — jamais -1
                    isLast: i == accounts.length - 1,
                  );
                }),
              ),

            const SizedBox(height: 10),

            // ── Bouton ajouter ────────────────────────────────────────────
            // [FIX] Remplace l'ancien _AddPlaylistSheet cassé (formulaire
            // Xtream incomplet : username/password vides) par le nouveau
            // widget universel AddPlaylistSheet avec vrais champs.
            _GradientBtn(
              label: context.read<LanguageProvider>().l10n.t('add_playlist'),
              icon: Icons.add_rounded,
              gradient: LinearGradient(
                  colors: [_T.blue.withOpacity(0.8), _T.cyan.withOpacity(0.6)]),
              onTap: () => showAddPlaylistSheet(context),
            ).animate(delay: 70.ms).fadeIn(duration: 220.ms),
          ],
        );
      }),
    ]);
  }
}

class _DisplaySection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t;
  const _DisplaySection({required this.l, required this.t});
  static const _themes = [
    (key: 'dark',  name: 'Cinéma Noir',  desc: 'Noir OLED · Violet · Contrastes forts', emoji: '🎬'),
    (key: 'soft',  name: 'Nuit Douce',   desc: 'Bleu nuit · Indigo · Couleurs apaisantes', emoji: '🌙'),
    (key: 'blue',  name: 'Nuit Bleue',   desc: 'Bleu profond · Accent électrique', emoji: '💎'),
  ];
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('settings').listenable(),
    builder: (context, box, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      _Group(label: context.read<LanguageProvider>().l10n.t('theme'), accentColor: _T.cyan,
        children: _themes.asMap().entries.map((e) {
          final th = e.value;
          return Padding(
            padding: EdgeInsets.only(bottom: e.key < _themes.length - 1 ? 6 : 0),
            child: _ThemeCard(
              name: th.name, desc: th.desc, emoji: th.emoji,
              accent: AppTheme.accentForTheme(th.key),
              bg: AppTheme.backgroundForTheme(th.key),
              isActive: t.themeKey == th.key,
              onTap: () => t.setTheme(th.key)));
        }).toList()).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
      const SizedBox(height: 14),
      _Group(label: context.read<LanguageProvider>().l10n.t('settings_sections'), accentColor: _T.red, children: [
        _RowItem(icon: Icons.live_tv_rounded, color: _T.red,
          label: context.read<LanguageProvider>().l10n.t('settings_show_live'), subtitle: context.read<LanguageProvider>().l10n.t('settings_visible_in_nav'),
          trailing: _Toggle(
            value: !(box.get(_kHideLive, defaultValue: false) as bool), color: _T.red,
            onChanged: (v) async {
              await box.put(_kHideLive, !v);
              if (context.mounted) context.read<IptvProvider>().loadTabContent(1);
            })),
        _RowItem(icon: Icons.movie_rounded, color: _T.blue,
          label: context.read<LanguageProvider>().l10n.t('settings_show_movies'), subtitle: context.read<LanguageProvider>().l10n.t('settings_visible_in_nav'),
          trailing: _Toggle(
            value: !(box.get(_kHideMovies, defaultValue: false) as bool), color: _T.blue,
            onChanged: (v) async {
              await box.put(_kHideMovies, !v);
              if (context.mounted) context.read<IptvProvider>().loadTabContent(2);
            })),
        _RowItem(icon: Icons.tv_rounded, color: _T.cyan,
          label: context.read<LanguageProvider>().l10n.t('settings_show_series'), subtitle: context.read<LanguageProvider>().l10n.t('settings_visible_in_nav'),
          trailing: _Toggle(
            value: !(box.get(_kHideSeries, defaultValue: false) as bool), color: _T.cyan,
            onChanged: (v) async {
              await box.put(_kHideSeries, !v);
              if (context.mounted) context.read<IptvProvider>().loadTabContent(3);
            }),
          isLast: true),
      ]).animate(delay: 65.ms).fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
    ]));
}

class _PrefsSection extends StatefulWidget {
  final AppL10n l; final ThemeProvider t;
  const _PrefsSection({required this.l, required this.t});
  @override State<_PrefsSection> createState() => _PrefsSectionState();
}
class _PrefsSectionState extends State<_PrefsSection> {
  late String _quality;
  @override void initState() {
    super.initState();
    _quality = Hive.box('settings').get(_kQuality, defaultValue: 'auto') as String;
  }
  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    const qualities = ['auto', '360p', '720p', '1080p', '4K'];
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(),
      builder: (context, box, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 4),
        _Group(label: context.read<LanguageProvider>().l10n.t('settings_stream_quality'), accentColor: _T.gold, children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Wrap(spacing: 7, runSpacing: 7, children: qualities.map((q) {
              final isSel = q == _quality;
              return FocusableInk(
                onTap: () async { setState(() => _quality = q); await box.put(_kQuality, q); },
                borderRadius: 20,
                focusColor: _T.gold,
                child: AnimatedContainer(duration: 150.ms,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: isSel ? LinearGradient(colors: [
                      _T.gold.withOpacity(0.25), _T.orange.withOpacity(0.15)]) : null,
                    color: isSel ? null : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel ? _T.gold.withOpacity(0.6) : Colors.white.withOpacity(0.08),
                      width: isSel ? 1.5 : 1),
                    boxShadow: isSel
                        ? [BoxShadow(color: _T.gold.withOpacity(0.2), blurRadius: 8)] : []),
                  child: Text(q.toUpperCase(), style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                    color: isSel ? _T.gold : _T.textSec))));
            }).toList())),
        ]).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 14),
        _Group(label: context.read<LanguageProvider>().l10n.t('settings_other'), accentColor: _T.violet, children: [
          _RowItem(icon: Icons.screen_rotation_rounded, color: _T.gold,
            label: context.read<LanguageProvider>().l10n.t('settings_force_landscape'), subtitle: context.read<LanguageProvider>().l10n.t('settings_force_landscape_desc'),
            trailing: _Toggle(
              value: box.get(_kForceLand, defaultValue: false) as bool, color: _T.gold,
              onChanged: (v) async { await box.put(_kForceLand, v); await _applyOrientation(v); })),
          _RowItem(icon: Icons.notifications_rounded, color: _T.violet,
            label: context.read<LanguageProvider>().l10n.t('settings_notifications'), subtitle: context.read<LanguageProvider>().l10n.t('settings_notifications_desc'),
            trailing: _Toggle(
              value: box.get(_kNotifs, defaultValue: true) as bool,
              onChanged: (v) async {
                await box.put(_kNotifs, v);
                if (v) await Permission.notification.request();
              })),
          _RowItem(icon: Icons.play_circle_rounded, color: _T.green,
            label: context.read<LanguageProvider>().l10n.t('settings_autoplay'), subtitle: context.read<LanguageProvider>().l10n.t('settings_autoplay_desc'),
            trailing: _Toggle(
              value: box.get(_kAutoplay, defaultValue: true) as bool, color: _T.green,
              onChanged: (v) async => await box.put(_kAutoplay, v)),
            isLast: true),
        ]).animate(delay: 65.ms).fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 14),
        _Group(label: context.read<LanguageProvider>().l10n.t('settings_lang'), accentColor: _T.blue, children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Wrap(spacing: 7, runSpacing: 7, children: AppL10n.languages.map((lang) {
              final lp = context.watch<LanguageProvider>();
              final isSel = lp.currentCode == lang.$3;
              return FocusableInk(
                onTap: () => lp.setLanguage(lang.$3),
                borderRadius: 20,
                focusColor: _T.violet,
                child: AnimatedContainer(duration: 150.ms,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: isSel ? LinearGradient(colors: [
                      _T.violet.withOpacity(0.2), _T.blue.withOpacity(0.1)]) : null,
                    color: isSel ? null : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel ? _T.violet.withOpacity(0.5) : Colors.white.withOpacity(0.08),
                      width: isSel ? 1.5 : 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(lang.$2, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(lang.$1, style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                      color: isSel ? Colors.white : _T.textSec)),
                  ])));
            }).toList())),
        ]).animate(delay: 130.ms).fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
      ]));
  }
}

class _AccountSection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t; final VoidCallback onRefresh;
  const _AccountSection({required this.l, required this.t, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final user      = Supabase.instance.client.auth.currentUser;
    final box       = Hive.box('settings');
    final pinHash   = box.get('parental_pin_hash', defaultValue: '') as String;
    final pinEnabled = box.get('parental_enabled', defaultValue: false) as bool;
    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      if (user != null) ...[
        _Group(label: context.read<LanguageProvider>().l10n.t('email'), accentColor: _T.green, children: [
          _RowItem(icon: Icons.mail_outline_rounded, color: _T.green,
              label: user.email ?? 'N/A', isLast: true),
        ]).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 14),
        _Group(label: context.read<LanguageProvider>().l10n.t('settings_parental'), accentColor: _T.orange, children: [
          if (pinEnabled)
            _RowItem(
              icon: Icons.lock_rounded, color: _T.green,
              label: context.read<LanguageProvider>().l10n.t('settings_parental_active'), subtitle: context.read<LanguageProvider>().l10n.t('settings_manage_parental'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    _T.green.withOpacity(0.25), _T.green.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _T.green.withOpacity(0.4))),
                child: Text('ON', style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, color: _T.green))),
              onTap: () async {
                final ok = await showDialog<bool>(context: context,
                    builder: (_) => SettingsPinVerifyDialog(storedHash: pinHash)) ?? false;
                if (ok && context.mounted) {
                  await showModalBottomSheet<void>(context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _ParentalControlSheet());
                  onRefresh();
                }
              }, isLast: true)
          else
            _RowItem(
              icon: Icons.lock_open_rounded, color: _T.orange,
              label: context.read<LanguageProvider>().l10n.t('settings_setup_parental'), subtitle: context.read<LanguageProvider>().l10n.t('settings_parental_desc'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
              onTap: () async {
                await showDialog<void>(context: context,
                    builder: (_) => SettingsPinSetupDialog());
                onRefresh();
              }, isLast: true),
        ]).animate(delay: 65.ms).fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 20),
        _DangerBtn(label: context.read<LanguageProvider>().l10n.t('settings_logout'), icon: Icons.logout_rounded,
          onTap: () async {
            await Supabase.instance.client.auth.signOut();
            if (context.mounted)
              Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
          }).animate(delay: 110.ms).fadeIn(duration: 220.ms),
      ] else ...[
        _EmptyStateCard(
          icon: Icons.account_circle_outlined, color: Colors.white24,
          title: context.read<LanguageProvider>().l10n.t('not_authenticated'), subtitle: context.read<LanguageProvider>().l10n.t('settings_login_to_access'),
          btnLabel: context.read<LanguageProvider>().l10n.t('arich_signin'), btnIcon: Icons.login_rounded,
          onTap: () => Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LoginScreen(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)))),
      ],
    ]);
  }
}

class _SupportSection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t;
  const _SupportSection({required this.l, required this.t});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: 4),
    _Group(label: context.read<LanguageProvider>().l10n.t('settings_help'), accentColor: _T.red, children: [
      _RowItem(icon: Icons.help_outline_rounded, color: _T.red, label: context.read<LanguageProvider>().l10n.t('settings_faq'),
        trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white24, size: 14),
        onTap: () => launchUrl(Uri.parse('https://arich.fr/faq'))),
      _RowItem(icon: Icons.gavel_rounded, color: _T.orange, label: context.read<LanguageProvider>().l10n.t('settings_terms'),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
        onTap: () => Navigator.push(context, PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LicenseScreen(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c))),
        isLast: true),
    ]).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
    const SizedBox(height: 14),
    Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _T.violet.withOpacity(0.09), Colors.transparent],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.violet.withOpacity(0.18))),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary, borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(color: _T.violet.withOpacity(0.4), blurRadius: 12)]),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Arich Player', style: GoogleFonts.rajdhani(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('v2.1.0', style: GoogleFonts.inter(fontSize: 11, color: _T.textSec)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: _T.green.withOpacity(0.12), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _T.green.withOpacity(0.3))),
          child: Text(context.read<LanguageProvider>().l10n.t('settings_up_to_date'), style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: _T.green))),
      ])).animate(delay: 65.ms).fadeIn(duration: 220.ms),
  ]);
}

class _DataSection extends StatelessWidget {
  final AppL10n l; final ThemeProvider t;
  const _DataSection({required this.l, required this.t});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Hive.box('settings').listenable(),
    builder: (context, box, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Consumer<DownloadService>(builder: (context, dlSvc, _) {
        final completedCount = dlSvc.completed.length;
        final activeCount    = dlSvc.activeCount;
        final subtitle = activeCount > 0
            ? '$activeCount en cours · $completedCount disponible${completedCount > 1 ? 's' : ''}'
            : '$completedCount fichier${completedCount > 1 ? 's' : ''} offline';
        return _Group(label: context.read<LanguageProvider>().l10n.t('downloads_title'), accentColor: _T.violet, children: [
          _RowItem(icon: Icons.download_rounded, color: _T.violet,
            label: context.read<LanguageProvider>().l10n.t('settings_my_downloads'), subtitle: subtitle,
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, a, __) => const DownloadsScreen(),
              transitionsBuilder: (_, a, __, child) => FadeTransition(
                opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
              transitionDuration: const Duration(milliseconds: 280))),
            isLast: true),
        ]).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0);
      }),
      const SizedBox(height: 14),
      _Group(label: context.read<LanguageProvider>().l10n.t('settings_cache'), accentColor: _T.orange, children: [
        _RowItem(icon: Icons.image_rounded, color: _T.orange,
          label: context.read<LanguageProvider>().l10n.t('settings_cache_images'), subtitle: context.read<LanguageProvider>().l10n.t('settings_cache_images_desc'),
          trailing: _Toggle(
            value: box.get(_kCacheImg, defaultValue: true) as bool, color: _T.orange,
            onChanged: (v) async => await box.put(_kCacheImg, v)),
          isLast: true),
      ]).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
      const SizedBox(height: 14),
      _DangerBtn(label: context.read<LanguageProvider>().l10n.t('settings_clear_cache'), icon: Icons.delete_sweep_rounded,
        onTap: () async {
          await Hive.box('settings').clear();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.read<LanguageProvider>().l10n.t('settings_cache_cleared'))));
        }).animate(delay: 65.ms).fadeIn(duration: 220.ms),
    ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyStateCard extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, subtitle, btnLabel;
  final IconData btnIcon; final VoidCallback onTap;
  const _EmptyStateCard({required this.icon, required this.color,
      required this.title, required this.subtitle,
      required this.btnLabel, required this.btnIcon, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.07))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 42),
      const SizedBox(height: 12),
      Text(title, style: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
      const SizedBox(height: 5),
      Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _T.textSec),
          textAlign: TextAlign.center),
      const SizedBox(height: 18),
      _GradientBtn(label: btnLabel, icon: btnIcon,
          gradient: AppTheme.gradientPrimary, onTap: onTap),
    ]));
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 8,
    child: Container(padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22))),
      child: Icon(icon, color: color, size: 13)));
}

class _GradientBtn extends StatelessWidget {
  final String label; final IconData icon;
  final LinearGradient gradient; final VoidCallback onTap;
  const _GradientBtn({required this.label, required this.icon,
      required this.gradient, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 12,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        gradient: gradient, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: gradient.colors.first.withOpacity(0.3),
            blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
      ])));
}

class _AddBtn extends StatelessWidget {
  final String label; final Color color; final IconData icon; final VoidCallback onTap;
  const _AddBtn({required this.label, required this.color,
      required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 12,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 7),
        Text(label, style: GoogleFonts.inter(
            fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ])));
}

class _DangerBtn extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _DangerBtn({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 12,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: _T.red.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.red.withOpacity(0.28))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: _T.red, size: 15),
        const SizedBox(width: 7),
        Text(label, style: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w600, color: _T.red)),
      ])));
}

class _ThemeCard extends StatelessWidget {
  final String name, desc, emoji; final Color accent, bg;
  final bool isActive; final VoidCallback onTap;
  const _ThemeCard({required this.name, required this.desc, required this.emoji,
      required this.accent, required this.bg, required this.isActive, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 14,
    child: AnimatedContainer(duration: 200.ms,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: isActive ? LinearGradient(colors: [
          accent.withOpacity(0.12), accent.withOpacity(0.04), Colors.transparent],
          begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: isActive ? null : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? accent.withOpacity(0.5) : Colors.white.withOpacity(0.07),
          width: isActive ? 1.5 : 1),
        boxShadow: isActive
            ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 12)] : []),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(
            color: bg == Colors.black ? const Color(0xFF0A0A0A) : bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isActive ? accent.withOpacity(0.5) : Colors.white.withOpacity(0.1))),
          child: Stack(alignment: Alignment.center, children: [
            Positioned(top: 4, right: 4,
              child: Container(width: 9, height: 9,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.5), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 5)]))),
            Text(emoji, style: const TextStyle(fontSize: 18)),
          ])),
        const SizedBox(width: 13),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 2),
          Text(desc, style: GoogleFonts.inter(fontSize: 11, color: _T.textSec),
              overflow: TextOverflow.ellipsis),
        ])),
        AnimatedOpacity(opacity: isActive ? 1.0 : 0.0, duration: 200.ms,
          child: Container(width: 22, height: 22,
            decoration: BoxDecoration(
              color: accent, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 6)]),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 13))),
      ])));
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAYLIST SHEETS
// ─────────────────────────────────────────────────────────────────────────────
// [FIX] _AddPlaylistSheet supprimée — remplacée par le widget universel
// AddPlaylistSheet dans lib/ui/widgets/add_playlist_sheet.dart
// Appelé via showAddPlaylistSheet(context) dans _PlaylistsSection.

class _EditPlaylistSheet extends StatefulWidget {
  final PlaylistAccount account;
  const _EditPlaylistSheet({required this.account});
  @override State<_EditPlaylistSheet> createState() => _EditPlaylistSheetState();
}
class _EditPlaylistSheetState extends State<_EditPlaylistSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  @override void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.account.name);
    _urlCtrl  = TextEditingController(text: widget.account.displayUrl);
  }
  @override void dispose() { _nameCtrl.dispose(); _urlCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 22),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _T.violet.withOpacity(0.25), width: 1.5))),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientHorizontal,
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text(context.read<LanguageProvider>().l10n.t('settings_edit_playlist'), style: GoogleFonts.rajdhani(
            fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 14),
        _SheetField(ctrl: _nameCtrl, hint: context.read<LanguageProvider>().l10n.t('playlist_name'), icon: Icons.label_rounded),
        const SizedBox(height: 8),
        _SheetField(ctrl: _urlCtrl, hint: context.read<LanguageProvider>().l10n.t('playlist_url'), icon: Icons.link_rounded, readOnly: true),
        const SizedBox(height: 16),
        _GradientBtn(label: context.read<LanguageProvider>().l10n.t('save'), icon: Icons.save_rounded,
          gradient: AppTheme.gradientPrimary,
          onTap: () {
            final name = _nameCtrl.text.trim();
            if (name.isNotEmpty) context.read<PlaylistProvider>().rename(widget.account.id, name);
            Navigator.pop(context);
          }),
      ]));
  }
}

class _TypeBtn extends StatelessWidget {
  final String label; final bool isActive; final VoidCallback onTap;
  const _TypeBtn({required this.label, required this.isActive, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 10,
    child: AnimatedContainer(duration: 150.ms,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: isActive ? LinearGradient(colors: [
          _T.blue.withOpacity(0.2), _T.cyan.withOpacity(0.1)]) : null,
        color: isActive ? null : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? _T.blue.withOpacity(0.5) : Colors.white.withOpacity(0.08),
          width: isActive ? 1.5 : 1)),
      child: Center(child: Text(label, style: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        color: isActive ? Colors.white : _T.textSec)))));
}

class _SheetField extends StatelessWidget {
  final TextEditingController ctrl; final String hint;
  final IconData icon; final bool readOnly;
  const _SheetField({required this.ctrl, required this.hint,
      required this.icon, this.readOnly = false});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl, readOnly: readOnly,
    style: GoogleFonts.inter(fontSize: 13, color: readOnly ? _T.textSec : Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 13, color: _T.textSec),
      prefixIcon: Icon(icon, color: readOnly ? _T.textMut : _T.textSec, size: 16),
      suffixIcon: readOnly
          ? const Icon(Icons.lock_outline_rounded, color: _T.textMut, size: 13) : null,
      filled: true,
      fillColor: readOnly ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
              color: readOnly ? Colors.white.withOpacity(0.08) : _T.violet, width: 1.5))));
}

// ─────────────────────────────────────────────────────────────────────────────
// PARENTAL CONTROL
// ─────────────────────────────────────────────────────────────────────────────

class _ParentalControlSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _T.orange.withOpacity(0.25), width: 1.5))),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(
              color: _T.orange.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text(context.read<LanguageProvider>().l10n.t('settings_parental'), style: GoogleFonts.rajdhani(
            fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 16),
        _DangerBtn(label: context.read<LanguageProvider>().l10n.t('settings_pin_disable'), icon: Icons.lock_open_rounded,
          onTap: () async {
            await Hive.box('settings').delete('parental_pin_hash');
            await Hive.box('settings').put('parental_enabled', false);
            if (context.mounted) Navigator.pop(context);
          }),
      ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIN DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

class SettingsPinSetupDialog extends StatefulWidget {
  @override State<SettingsPinSetupDialog> createState() => _PinSetupState();
}
class _PinSetupState extends State<SettingsPinSetupDialog>
    with SingleTickerProviderStateMixin {
  String _cur = '', _confirm = '', _error = '';
  bool _confirming = false;
  static const _len = 4;
  late AnimationController _shake;
  late Animation<double> _shakeAnim;
  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(_shake);
  }
  @override void dispose() { _shake.dispose(); super.dispose(); }
  void _onKey(String d) {
    if ((_confirming ? _confirm : _cur).length >= _len) return;
    setState(() { _error = ''; if (_confirming) _confirm += d; else _cur += d; });
    if ((_confirming ? _confirm : _cur).length == _len) {
      if (_confirming) _finalize(); else setState(() => _confirming = true);
    }
  }
  void _onDelete() => setState(() {
    _error = '';
    if (_confirming) { if (_confirm.isNotEmpty) _confirm = _confirm.substring(0, _confirm.length - 1); }
    else { if (_cur.isNotEmpty) _cur = _cur.substring(0, _cur.length - 1); }
  });
  void _finalize() {
    if (_cur != _confirm) {
      _shake.forward(from: 0);
      setState(() {
        _error = context.read<LanguageProvider>().l10n.t('parental_pin_mismatch');
        _confirm = ''; _confirming = false;
      });
      return;
    }
    Hive.box('settings')
      ..put('parental_pin_hash', sha256.convert(utf8.encode(_cur)).toString())
      ..put('parental_enabled', true);
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88, maxWidth: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _T.violet.withOpacity(0.5), blurRadius: 16)]),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 24)),
            const SizedBox(height: 16),
            Text(_confirming ? context.read<LanguageProvider>().l10n.t('parental_pin_confirm') : context.read<LanguageProvider>().l10n.t('settings_pin_title'),
              style: GoogleFonts.rajdhani(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            AnimatedBuilder(animation: _shakeAnim,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(_shakeAnim.value, 0), child: child),
              child: _PinDots(pin: _confirming ? _confirm : _cur,
                  error: _error.isNotEmpty, color: _T.violet)),
            AnimatedSize(duration: 180.ms,
              child: _error.isEmpty ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_error, style: TextStyle(color: _T.red, fontSize: 12)))),
            const SizedBox(height: 22),
            _PinKeypad(onKey: _onKey, onDelete: _onDelete),
            const SizedBox(height: 14),
            TextButton(onPressed: () => Navigator.pop(context),
              child: Text(context.read<LanguageProvider>().l10n.t('cancel'), style: GoogleFonts.inter(color: _T.textSec))),
          ]))));
  }
}

class SettingsPinVerifyDialog extends StatefulWidget {
  final String storedHash;
  const SettingsPinVerifyDialog({super.key, required this.storedHash});
  @override State<SettingsPinVerifyDialog> createState() => _PinVerifyState();
}
class _PinVerifyState extends State<SettingsPinVerifyDialog>
    with SingleTickerProviderStateMixin {
  String _pin = '', _error = '';
  static const _len = 4;
  late AnimationController _shake;
  late Animation<double> _shakeAnim;
  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(_shake);
  }
  @override void dispose() { _shake.dispose(); super.dispose(); }
  void _onKey(String d) {
    if (_pin.length >= _len) return;
    setState(() { _error = ''; _pin += d; });
    if (_pin.length == _len) _verify();
  }
  void _onDelete() => setState(() {
    _error = '';
    if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
  });
  void _verify() {
    final hash = sha256.convert(utf8.encode(_pin)).toString();
    if (hash == widget.storedHash) { Navigator.pop(context, true); }
    else {
      _shake.forward(from: 0);
      setState(() {
        _error = context.read<LanguageProvider>().l10n.t('parental_pin_wrong');
        _pin = '';
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 320),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                color: _T.violet.withOpacity(0.12), shape: BoxShape.circle,
                border: Border.all(color: _T.violet.withOpacity(0.35), width: 1.5)),
              child: const Icon(Icons.lock_rounded, color: _T.violet, size: 24)),
            const SizedBox(height: 16),
            Text(context.read<LanguageProvider>().l10n.t('parental_enter_pin'),
              style: GoogleFonts.rajdhani(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            AnimatedBuilder(animation: _shakeAnim,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(_shakeAnim.value, 0), child: child),
              child: _PinDots(pin: _pin, error: _error.isNotEmpty, color: _T.violet)),
            AnimatedSize(duration: 180.ms,
              child: _error.isEmpty ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_error, style: TextStyle(color: _T.red, fontSize: 12)))),
            const SizedBox(height: 22),
            _PinKeypad(onKey: _onKey, onDelete: _onDelete),
            const SizedBox(height: 14),
            TextButton(onPressed: () => Navigator.pop(context),
              child: Text(context.read<LanguageProvider>().l10n.t('cancel'), style: GoogleFonts.inter(color: _T.textSec))),
          ]))));
  }
}

class _PinDots extends StatelessWidget {
  final String pin; final bool error; final Color color;
  const _PinDots({required this.pin, required this.error, required this.color});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(4, (i) {
      final filled = i < pin.length;
      return AnimatedContainer(
        duration: 120.ms,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        width: 16, height: 16,
        decoration: BoxDecoration(
          gradient: filled && !error
              ? LinearGradient(colors: [color, color.withOpacity(0.7)]) : null,
          color: error ? _T.red : filled ? null : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: error ? _T.red : filled ? color : Colors.white.withOpacity(0.2),
            width: 2),
          boxShadow: filled && !error
              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : []));
    }));
}

class _PinKeypad extends StatelessWidget {
  final void Function(String) onKey; final VoidCallback onDelete;
  const _PinKeypad({required this.onKey, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    const rows = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']];
    return Column(mainAxisSize: MainAxisSize.min,
      children: rows.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) {
          if (k.isEmpty) return const SizedBox(width: 80, height: 56);
          final isDel = k == '⌫';
          return SizedBox(width: 80, height: 56,
            child: FocusableInk(onTap: () => isDel ? onDelete() : onKey(k),
              borderRadius: 12,
              child: Container(margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDel ? 0.04 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.07))),
                child: Center(child: isDel
                    ? Icon(Icons.backspace_outlined, color: _T.textSec, size: 18)
                    : Text(k, style: GoogleFonts.rajdhani(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500))))));
        }).toList())).toList());
  }
}