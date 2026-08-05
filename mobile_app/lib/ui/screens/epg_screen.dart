// lib/ui/screens/epg_screen.dart
//
// Arich Player — EpgScreen v2 AAA
//
// Nouveautés v2 :
// [D1] AppBar glassmorphism avec backdrop filter + gradient accent bottom border
// [D2] Skeleton loading premium (shimmer animate repeat)
// [D3] Sidebar chaînes : left accent 3px gradient si programme en cours
// [D4] Timeline header : gradient de fond + heure courante surligné violet glow
// [D5] Program cells : gradient violet→transparent pour isNow, badge EN COURS
//      pill gradient, progress bar gradient violet→red
// [D6] Ligne "Maintenant" : gradient red→transparent + losange animé en haut
// [D7] Corner cell : gradient premium + jour/date stylisés
// [D8] Popup : header gradient, progress track gradient violet→red + glow
// [D9] Empty state illustré avec icon pill gradient
// Logique métier 100% préservée
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../core/l10n.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/language_provider.dart';
import '../../models/channel.dart';
import 'player_screen.dart';
import '../widgets/focusable_ink.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const double _kChannelWidth = 140.0;
const double _kRowHeight    = 64.0;
const double _kHeaderHeight = 48.0;
const double _kHourWidth    = 200.0;
const double _kMinuteWidth  = _kHourWidth / 60.0;

// ─────────────────────────────────────────────────────────────────────────────
// Modèles EPG
// ─────────────────────────────────────────────────────────────────────────────

class _EpgProgram {
  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  _EpgProgram({
    required this.title,
    this.description,
    required this.start,
    required this.end,
  });

  Duration get duration => end.difference(start);
  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }
  double get progress {
    if (!isNow) return 0;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return elapsed / duration.inSeconds;
  }
}

class _EpgChannel {
  final Channel channel;
  final List<_EpgProgram> programs;
  _EpgChannel({required this.channel, required this.programs});
}

// ─────────────────────────────────────────────────────────────────────────────
// EpgScreen
// ─────────────────────────────────────────────────────────────────────────────

class EpgScreen extends StatefulWidget {
  const EpgScreen({super.key});
  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  final ScrollController _verticalCtrl   = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();
  final ScrollController _headerCtrl     = ScrollController();

  bool _isLoading = true;
  List<_EpgChannel> _channels = [];
  Timer?  _refreshTimer;
  String  _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  late DateTime _dayStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dayStart = DateTime(now.year, now.month, now.day);

    _horizontalCtrl.addListener(() {
      if (_headerCtrl.hasClients &&
          _headerCtrl.offset != _horizontalCtrl.offset) {
        _headerCtrl.jumpTo(_horizontalCtrl.offset);
      }
    });

    _loadEpg();

    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    _headerCtrl.dispose();
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEpg() async {
    setState(() => _isLoading = true);
    final provider = context.read<IptvProvider>();
    final liveChannels = provider.allLive;

    if (liveChannels.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final limited = liveChannels.take(20).toList();
    final favIds  = provider.favorites.map((c) => c.streamId).toSet();

    limited.sort((a, b) {
      final aFav = favIds.contains(a.streamId) ? 0 : 1;
      final bFav = favIds.contains(b.streamId) ? 0 : 1;
      return aFav.compareTo(bFav);
    });

    final results = await Future.wait(
      limited.map((ch) async {
        List<_EpgProgram> programs = [];
        try {
          final epgData = await provider.api.getShortEpg(ch.streamId);
          final listings = epgData['epg_listings'] as List? ?? [];
          for (final item in listings) {
            try {
              final start = _parseXtreamDate(item['start'] as String);
              final end   = _parseXtreamDate(item['end']   as String);
              final title = _decodeEpgTitle(item['title'] as String? ?? '');
              final desc  = _decodeEpgTitle(item['description'] as String? ?? '');
              programs.add(_EpgProgram(
                title: title,
                description: desc.isNotEmpty ? desc : null,
                start: start,
                end: end,
              ));
            } catch (_) {}
          }
        } catch (_) {}

        if (programs.isEmpty) programs = _generatePlaceholderPrograms();
        return _EpgChannel(channel: ch, programs: programs);
      }),
    );

    if (mounted) {
      setState(() {
        _channels  = results;
        _isLoading = false;
      });
      Future.delayed(const Duration(milliseconds: 300), _scrollToNow);
    }
  }

  List<_EpgProgram> _generatePlaceholderPrograms() {
    final now      = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final List<_EpgProgram> progs = [];
    var t = dayStart;
    while (t.isBefore(dayStart.add(const Duration(hours: 24)))) {
      final end = t.add(const Duration(hours: 1));
      progs.add(_EpgProgram(title: context.read<LanguageProvider>().l10n.t('epg_now'), description: null, start: t, end: end));
      t = end;
    }
    return progs;
  }

  DateTime _parseXtreamDate(String raw) {
    final s = raw.trim();
    final xmltvRe = RegExp(r'^(\d{14})\s*([+-]\d{4})?$');
    final m = xmltvRe.firstMatch(s);
    if (m != null) {
      final digits = m.group(1)!;
      if (digits.length < 14) {
        return DateTime.now();
      }
      final year   = int.parse(digits.substring(0, 4));
      final month  = int.parse(digits.substring(4, 6));
      final day    = int.parse(digits.substring(6, 8));
      final hour   = int.parse(digits.substring(8, 10));
      final minute = int.parse(digits.substring(10, 12));
      final second = int.parse(digits.substring(12, 14));
      final tz = m.group(2) ?? '+0000';
      if (tz.length < 5) {
        return DateTime.utc(year, month, day, hour, minute, second).toLocal();
      }
      final tzSign  = tz[0] == '-' ? -1 : 1;
      final tzHours = int.parse(tz.substring(1, 3));
      final tzMins  = int.parse(tz.substring(3, 5));
      final tzOffset = Duration(hours: tzHours, minutes: tzMins) * tzSign;
      return DateTime.utc(year, month, day, hour, minute, second)
          .subtract(tzOffset)
          .toLocal();
    }
    final shortRe = RegExp(r'^(\d{8})\s+(\d{6})$');
    final sm = shortRe.firstMatch(s);
    if (sm != null) {
      final date = sm.group(1)!;
      final time = sm.group(2)!;
      if (date.length < 8 || time.length < 6) {
        return DateTime.now();
      }
      return DateTime.utc(
        int.parse(date.substring(0, 4)), int.parse(date.substring(4, 6)),
        int.parse(date.substring(6, 8)), int.parse(time.substring(0, 2)),
        int.parse(time.substring(2, 4)), int.parse(time.substring(4, 6)),
      ).toLocal();
    }
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  String _decodeEpgTitle(String raw) {
    if (raw.isEmpty) return raw;
    final looksB64 = !raw.contains(' ')
        && raw.length > 4
        && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(raw);
    if (looksB64) {
      try {
        final bytes   = base64Decode(raw);
        final decoded = utf8.decode(bytes, allowMalformed: true).trim();
        if (decoded.isNotEmpty && !decoded.contains('\x00')) return decoded;
      } catch (_) {}
      try {
        return String.fromCharCodes(base64Decode(raw)).trim();
      } catch (_) {}
    }
    return raw.trim();
  }

  String _formatRemaining(_EpgProgram prog) {
    final remaining = prog.end.difference(DateTime.now());
    if (remaining.isNegative) return '';
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (h > 0) return '-${h}h${m.toString().padLeft(2, '0')}';
    return '-${m}min';
  }

  void _scrollToNow() {
    if (!_horizontalCtrl.hasClients) return;
    final now = DateTime.now();
    final minutesSinceDayStart = now.difference(_dayStart).inMinutes;
    final offset = (minutesSinceDayStart * _kMinuteWidth) - 100;
    _horizontalCtrl.animateTo(
      offset.clamp(0, _horizontalCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  double get _nowOffset {
    final now = DateTime.now();
    return now.difference(_dayStart).inMinutes * _kMinuteWidth;
  }

  List<_EpgChannel> get _filteredChannels {
    if (_searchQuery.isEmpty) return _channels;
    final q = _searchQuery.toLowerCase();
    return _channels.where((c) => c.channel.name.toLowerCase().contains(q)).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final isTV = context.isTV;

    return TvBackHandler(
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(children: [
          _buildAppBar(isTV),
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _channels.isEmpty
                    ? _buildEmpty()
                    : _buildGuide(),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D1] APP BAR AAA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAppBar(bool isTV) {
    final topPad = MediaQuery.of(context).padding.top;
    final usesBlur = !Platform.isLinux &&
        Platform.operatingSystem != 'tizen';

    Widget bar = Container(
      height: 56 + topPad,
      padding: EdgeInsets.only(top: topPad, left: 12, right: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(usesBlur ? 0.55 : 0.85),
        border: Border(
          bottom: BorderSide(
            color: Colors.transparent,
            width: 0,
          ),
        ),
      ),
      child: Row(children: [
        // Bouton retour
        if (!isTV)
          FocusableInk(
            onTap: () => Navigator.pop(context),
            borderRadius: 10,
            focusColor: AppTheme.violet,
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.09)),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 18),
            ),
          ),

        // Icône pill gradient + titre
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(9),
            boxShadow: AppTheme.glowViolet(intensity: 0.4, blur: 12),
          ),
          child: const Icon(Icons.calendar_view_week_rounded,
              color: Colors.white, size: 16),
        ),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.read<LanguageProvider>().l10n.t('epg_title'),
              style: TextStyle(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            Text(
              _channels.isEmpty ? 'Chargement…' : '${_channels.length} chaînes',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3), fontSize: 9,
                letterSpacing: 0.5)),
          ],
        ),

        const Spacer(),

        // Champ recherche
        Flexible(
          child: Container(
            height: 34,
            constraints: const BoxConstraints(maxWidth: 160),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: context.read<LanguageProvider>().l10n.t('epg_search'),
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.28), fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.28), size: 15),
                suffixIcon: _searchQuery.isNotEmpty
                    ? FocusableInk(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        borderRadius: 8,
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.35), size: 15),
                      )
                    : null,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Bouton Live gradient
        FocusableInk(
          onTap: _scrollToNow,
          borderRadius: 9,
          focusColor: AppTheme.violet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(9),
              boxShadow: AppTheme.glowViolet(intensity: 0.3, blur: 12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.white.withOpacity(0.8), blurRadius: 4)],
                ),
              ).animate(onPlay: (c) => c.repeat())
               .fade(begin: 1, end: 0.3, duration: 800.ms),
              SizedBox(width: 5),
              Text(context.read<LanguageProvider>().l10n.t('epg_live_badge'),
                style: TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            ]),
          ),
        ),

        const SizedBox(width: 6),

        // Bouton refresh
        FocusableInk(
          onTap: _loadEpg,
          borderRadius: 9,
          focusColor: AppTheme.violet,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withOpacity(0.09)),
            ),
            child: const Icon(Icons.refresh_rounded,
                color: AppTheme.textSecondary, size: 17),
          ),
        ),
      ]),
    );

    // Gradient bottom border accent
    return Stack(clipBehavior: Clip.none, children: [
      if (usesBlur)
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: bar,
          ),
        )
      else
        bar,
      // Accent line gradient
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              AppTheme.violet.withOpacity(0.5),
              AppTheme.red.withOpacity(0.3),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D2] SKELETON LOADING
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Row(children: [
      // Sidebar skeleton
      SizedBox(
        width: _kChannelWidth,
        child: Column(children: [
          _buildCornerCell(),
          Expanded(
            child: ListView.separated(
              itemCount: 8,
              separatorBuilder: (_, __) => Container(
                height: 1,
                color: Colors.white.withOpacity(0.03)),
              itemBuilder: (_, i) => Container(
                height: _kRowHeight,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(9)),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .shimmer(duration: 1200.ms,
                       color: Colors.white.withOpacity(0.04)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 9,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4)),
                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                         .shimmer(duration: 1200.ms,
                             color: Colors.white.withOpacity(0.04)),
                        const SizedBox(height: 6),
                        Container(
                          height: 7, width: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4)),
                        ).animate(onPlay: (c) => c.repeat(reverse: true))
                         .shimmer(duration: 1400.ms,
                             color: Colors.white.withOpacity(0.03)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),

      Container(width: 1, color: Colors.white.withOpacity(0.05)),

      // Grille skeleton
      Expanded(
        child: Column(children: [
          // Header skeleton
          Container(
            height: _kHeaderHeight,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
          ),
          // Rows skeleton
          Expanded(
            child: ListView.separated(
              itemCount: 8,
              separatorBuilder: (_, __) => Container(
                height: 1,
                color: Colors.white.withOpacity(0.03)),
              itemBuilder: (_, i) => Container(
                height: _kRowHeight,
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 10),
                child: Row(children: [
                  ...List.generate(3, (j) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6)),
                    ).animate(onPlay: (c) => c.repeat(reverse: true))
                     .shimmer(
                         duration: Duration(milliseconds: 1200 + j * 200),
                         color: Colors.white.withOpacity(0.03)),
                  )),
                ]),
              ),
            ),
          ),
        ]),
      ),
    ]).animate().fadeIn(duration: 300.ms);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D9] EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.glowViolet(intensity: 0.3, blur: 24),
          ),
          child: const Icon(Icons.tv_off_rounded,
              color: Colors.white, size: 32),
        ),
        SizedBox(height: 20),
        Text(context.read<LanguageProvider>().l10n.t('epg_no_program'),
          style: TextStyle(
            color: Colors.white, fontSize: 16,
            fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text(context.read<LanguageProvider>().l10n.t('epg_add_playlist'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4), fontSize: 13)),
      ]),
    ).animate().fadeIn().slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GUIDE PRINCIPAL
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGuide() {
    final filtered = _filteredChannels;

    return Row(children: [
      // ── Sidebar chaînes (fixe) ─────────────────────────────────────────
      SizedBox(
        width: _kChannelWidth,
        child: Column(children: [
          _buildCornerCell(),
          Expanded(
            child: ListView.builder(
              controller: _verticalCtrl,
              itemCount: filtered.length,
              itemExtent: _kRowHeight,
              itemBuilder: (_, i) => _buildChannelCell(filtered[i]),
            ),
          ),
        ]),
      ),

      Container(
        width: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white.withOpacity(0.07),
              Colors.white.withOpacity(0.07),
              Colors.transparent,
            ],
          ),
        ),
      ),

      // ── Zone timeline + grille ─────────────────────────────────────────
      Expanded(
        child: Column(children: [
          SizedBox(
            height: _kHeaderHeight,
            child: SingleChildScrollView(
              controller: _headerCtrl,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: _buildTimelineHeader(),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) {
                if (notif is ScrollUpdateNotification &&
                    notif.metrics.axis == Axis.horizontal) {
                  if (_headerCtrl.hasClients) {
                    final target = _horizontalCtrl.offset.clamp(
                        0.0, _headerCtrl.position.maxScrollExtent);
                    if ((_headerCtrl.offset - target).abs() > 0.5) {
                      _headerCtrl.jumpTo(target);
                    }
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _horizontalCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 24 * _kHourWidth,
                  child: Stack(children: [
                    ListView.builder(
                      controller: _verticalCtrl,
                      itemCount: filtered.length,
                      itemExtent: _kRowHeight,
                      itemBuilder: (_, i) => _buildProgramRow(filtered[i]),
                    ),
                    _buildNowLine(),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D7] CORNER CELL AAA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCornerCell() {
    final now = DateTime.now();
    return Container(
      width: _kChannelWidth,
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.violet.withOpacity(0.18),
            AppTheme.background.withOpacity(0.9),
          ],
        ),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.06)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (b) => AppTheme.gradientHorizontal
                .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: Text(
              _dayName(now.weekday).toUpperCase(),
              style: const TextStyle(
                color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${now.day}/${now.month}',
            style: const TextStyle(
              color: Colors.white, fontSize: 14,
              fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
        ]),
      ),
    );
  }

  String _dayName(int weekday) {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return days[(weekday - 1) % 7];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D3] CHANNEL CELL AAA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChannelCell(_EpgChannel epgCh) {
    final ch     = epgCh.channel;
    final isFav  = context.read<IptvProvider>().isFavorite(ch.streamId, 1);
    final nowProg = epgCh.programs.where((p) => p.isNow).firstOrNull;
    final hasNow  = nowProg != null;

    return FocusableInk(
      onTap: () => _playChannel(ch),
      borderRadius: 0,
      focusColor: AppTheme.violet,
      child: Container(
        height: _kRowHeight,
        width: _kChannelWidth,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.025),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.03)),
            right: BorderSide(color: Colors.white.withOpacity(0.06)),
            left: BorderSide(
              color: hasNow
                  ? AppTheme.violet.withOpacity(0.7)
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 10),
          child: Row(children: [
            // Logo
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: isFav
                    ? AppTheme.glowViolet(intensity: 0.22, blur: 8) : null,
              ),
              child: ch.streamIcon.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: ch.streamIcon,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.live_tv_rounded,
                          color: AppTheme.textMuted, size: 18),
                      ),
                    )
                  : const Icon(Icons.live_tv_rounded,
                      color: AppTheme.textMuted, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ch.name,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (hasNow) ...[
                    const SizedBox(height: 2),
                    Text(
                      nowProg.title,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 9, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Container(
                            height: 2,
                            child: Stack(children: [
                              Container(color: Colors.white.withOpacity(0.07)),
                              FractionallySizedBox(
                                widthFactor: nowProg.progress.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.gradientHorizontal,
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatRemaining(nowProg),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 8),
                      ),
                    ]),
                  ] else if (isFav) ...[
                    const SizedBox(height: 2),
                    ShaderMask(
                      shaderCallback: (b) => AppTheme.gradientPrimary
                          .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D4] TIMELINE HEADER AAA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimelineHeader() {
    final nowHour = DateTime.now().hour;
    return SizedBox(
      width: 24 * _kHourWidth,
      height: _kHeaderHeight,
      child: Stack(children: [
        // Fond gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.violet.withOpacity(0.06),
                Colors.black.withOpacity(0.3),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: List.generate(24, (h) {
              final isNowHour = h == nowHour;
              return SizedBox(
                width: _kHourWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: isNowHour
                        ? AppTheme.violet.withOpacity(0.1)
                        : Colors.transparent,
                    border: Border(
                      right: BorderSide(
                          color: Colors.white.withOpacity(0.04))),
                  ),
                  padding: const EdgeInsets.only(left: 10),
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    if (isNowHour) ...[
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.violet,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: AppTheme.violet.withOpacity(0.6),
                            blurRadius: 4)],
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${h.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                        color: isNowHour
                            ? Colors.white
                            : AppTheme.textMuted,
                        fontSize: isNowHour ? 12 : 11,
                        fontWeight: isNowHour
                            ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
        ),
        // Indicateur "maintenant" dans le header
        Positioned(
          left: _nowOffset - 1,
          top: 0, bottom: 0,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.red,
                  AppTheme.red.withOpacity(0.2),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROGRAM ROW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProgramRow(_EpgChannel epgCh) {
    return SizedBox(
      height: _kRowHeight,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.03)),
            ),
          ),
        ),
        ...epgCh.programs.map((prog) {
          final left  = prog.start.difference(_dayStart).inMinutes * _kMinuteWidth;
          final width = prog.duration.inMinutes * _kMinuteWidth;
          if (left > 24 * _kHourWidth || left + width < 0) {
            return const SizedBox.shrink();
          }
          return Positioned(
            left: left.clamp(0.0, 24 * _kHourWidth),
            top: 4, bottom: 4,
            width: width.clamp(4.0, 24 * _kHourWidth - left),
            child: _ProgramCell(
              program: prog,
              onTap: () => _showProgramPopup(prog, epgCh.channel),
            ),
          );
        }),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [D6] LIGNE "MAINTENANT" AAA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNowLine() {
    return Positioned(
      left: _nowOffset,
      top: 0, bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          child: Stack(clipBehavior: Clip.none, children: [
            // Trait gradient
            Container(
              width: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.red,
                    AppTheme.red.withOpacity(0.3),
                  ],
                ),
              ),
            ),
            // Losange animé en haut
            Positioned(
              top: -1,
              left: -5,
              child: Transform.rotate(
                angle: 0.785, // 45°
                child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.red,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.red.withOpacity(0.7),
                        blurRadius: 8, spreadRadius: 1),
                    ],
                  ),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
               .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3),
                   duration: 900.ms, curve: Curves.easeInOut)
               .then()
               .fade(begin: 1, end: 0.6, duration: 900.ms),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POPUP PROGRAMME
  // ─────────────────────────────────────────────────────────────────────────

  void _showProgramPopup(_EpgProgram prog, Channel ch) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProgramPopup(
        program: prog,
        channel: ch,
        onWatch: () {
          Navigator.pop(context);
          _playChannel(ch);
        },
      ),
    );
  }

  void _playChannel(Channel ch) {
    final url = context.read<IptvProvider>().getStreamUrl(ch, tabIndex: 1);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: url,
        title: ch.name,
        streamIcon: ch.streamIcon,
        streamId: ch.streamId,
        tabIndex: 1,
      ),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [D5] PROGRAM CELL AAA
// ─────────────────────────────────────────────────────────────────────────────

class _ProgramCell extends StatefulWidget {
  final _EpgProgram program;
  final VoidCallback onTap;
  const _ProgramCell({required this.program, required this.onTap});
  @override
  State<_ProgramCell> createState() => _ProgramCellState();
}

class _ProgramCellState extends State<_ProgramCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final prog   = widget.program;
    final isNow  = prog.isNow;
    final isPast = prog.end.isBefore(DateTime.now());

    Color bgColor;
    Color borderColor;
    double borderWidth;

    if (isNow) {
      bgColor     = AppTheme.violet.withOpacity(0.18);
      borderColor = AppTheme.violet.withOpacity(0.55);
      borderWidth = 1.5;
    } else if (isPast) {
      bgColor     = Colors.white.withOpacity(0.025);
      borderColor = Colors.white.withOpacity(0.04);
      borderWidth = 1;
    } else {
      bgColor     = AppTheme.surfaceHigh.withOpacity(0.8);
      borderColor = Colors.white.withOpacity(0.07);
      borderWidth = 1;
    }

    if (_hovered) {
      bgColor     = AppTheme.violet.withOpacity(0.2);
      borderColor = AppTheme.violet.withOpacity(0.45);
      borderWidth = 1.5;
    }

    return FocusableInk(
      onTap: widget.onTap,
      borderRadius: 6,
      focusColor: AppTheme.violet,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: isNow
                ? [BoxShadow(
                    color: AppTheme.violet.withOpacity(0.18),
                    blurRadius: 10)]
                : [],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(children: [
            // [D5] Barre de progression gradient si en cours
            if (isNow)
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: prog.progress *
                    (prog.duration.inMinutes * _kMinuteWidth - 4),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.violet.withOpacity(0.4),
                        AppTheme.red.withOpacity(0.15),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(5),
                      bottomLeft: Radius.circular(5),
                    ),
                  ),
                ),
              ),

            // Contenu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prog.title,
                    style: TextStyle(
                      color: isPast
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: isNow
                          ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  if (prog.duration.inMinutes > 45) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${_fmt(prog.start)} – ${_fmt(prog.end)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(isPast ? 0.18 : 0.38),
                        fontSize: 9),
                    ),
                  ],
                ],
              ),
            ),

            // [D5] Badge "EN COURS" pill gradient
            if (isNow)
              Positioned(
                top: 3, right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientHorizontal,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [BoxShadow(
                      color: AppTheme.red.withOpacity(0.3),
                      blurRadius: 4)],
                  ),
                  child: const Text('●',
                    style: TextStyle(
                      color: Colors.white, fontSize: 7,
                      fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// [D8] PROGRAMME POPUP AAA
// ─────────────────────────────────────────────────────────────────────────────

class _ProgramPopup extends StatelessWidget {
  final _EpgProgram program;
  final Channel     channel;
  final VoidCallback onWatch;

  const _ProgramPopup({
    required this.program,
    required this.channel,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final isNow = program.isNow;
    String fmt(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isNow
              ? AppTheme.violet.withOpacity(0.45)
              : Colors.white.withOpacity(0.09),
          width: isNow ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.65), blurRadius: 50),
          if (isNow)
            BoxShadow(
              color: AppTheme.violet.withOpacity(0.18),
              blurRadius: 60, spreadRadius: -10),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle pill gradient
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientHorizontal,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Logo chaîne
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  boxShadow: isNow
                      ? AppTheme.glowViolet(intensity: 0.28, blur: 18) : null,
                ),
                child: channel.streamIcon.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: CachedNetworkImage(
                            imageUrl: channel.streamIcon,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.live_tv_rounded,
                              color: AppTheme.textMuted, size: 26)),
                      )
                    : const Icon(Icons.live_tv_rounded,
                        color: AppTheme.textMuted, size: 26),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(channel.name,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.42),
                      fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(program.title,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (isNow) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppTheme.gradientHorizontal,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: AppTheme.glowRed(
                              intensity: 0.3, blur: 8),
                        ),
                        child: Text(context.read<LanguageProvider>().l10n.t('epg_on_air'),
                          style: TextStyle(
                            color: Colors.white, fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.access_time_rounded,
                        color: Colors.white.withOpacity(0.3), size: 12),
                    const SizedBox(width: 4),
                    Text('${fmt(program.start)} – ${fmt(program.end)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('${program.duration.inMinutes} min',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 10)),
                    ),
                  ]),
                ]),
              ),
            ]),

            // [D8] Barre de progression gradient violet→red
            if (isNow) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 5,
                  child: Stack(children: [
                    Container(
                      color: Colors.white.withOpacity(0.07)),
                    FractionallySizedBox(
                      widthFactor: program.progress.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.gradientHorizontal,
                          boxShadow: [BoxShadow(
                            color: AppTheme.violet.withOpacity(0.4),
                            blurRadius: 6)],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],

            // Description
            if (program.description != null &&
                program.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.07),
                    Colors.transparent,
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                program.description!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13, height: 1.55),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 20),

            // Bouton regarder
            FocusableInk(
              onTap: onWatch,
              autofocus: true,
              borderRadius: 14,
              focusColor: AppTheme.violet,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientHorizontal,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.violet.withOpacity(0.38),
                      blurRadius: 24, offset: const Offset(0, 6)),
                    BoxShadow(
                      color: AppTheme.violet.withOpacity(0.2),
                      blurRadius: 48, spreadRadius: 2),
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(isNow ? 'Regarder en direct' : 'Regarder',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.06, end: 0);
  }
}