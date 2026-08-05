// stats_screen.dart — Arich Player v1.2
// Écran Statistiques — créé from scratch Mars 2026
//
// v1.2 — Corrections imports et types :
//   - Import corrigé : ../../core/theme.dart (AppTheme)
//   - Import corrigé : ../../core/tv_layout.dart (context.isTV, context.tvSizes)
//   - Import corrigé : ../../providers/iptv_provider.dart (IptvProvider, HistoryEntry, SourceType)
//   - FocusableInk.borderRadius → double? (12.0 au lieu de BorderRadius.circular)
//   - totalDurationSeconds (num) → .toInt() partout
//   - dart:math importé pour fond animé

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/iptv_provider.dart';
import '../widgets/focusable_ink.dart';

// ─────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────

enum StatsTab { overview, topContent, history, account }

enum TimePeriod { today, week, month }

// ─────────────────────────────────────────────────────────────────
// COMPUTED MODELS
// ─────────────────────────────────────────────────────────────────

class DailyStats {
  final DateTime date;
  final int totalSeconds;
  DailyStats({required this.date, required this.totalSeconds});
}

class TopContent {
  final int streamId;
  final int tabIndex;
  final String title;
  final String streamIcon;
  final int totalSeconds;
  final int viewCount;

  TopContent({
    required this.streamId,
    required this.tabIndex,
    required this.title,
    required this.streamIcon,
    required this.totalSeconds,
    required this.viewCount,
  });
}

// ─────────────────────────────────────────────────────────────────
// STATS SCREEN
// ─────────────────────────────────────────────────────────────────

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with TickerProviderStateMixin {
  StatsTab _activeTab = StatsTab.overview;
  TimePeriod _period = TimePeriod.week;

  late AnimationController _bgController;
  late AnimationController _barController;

  // Computed from watchHistory
  List<DailyStats> _dailyStats = [];
  List<TopContent> _topLive = [];
  List<TopContent> _topMovies = [];
  List<TopContent> _topSeries = [];
  int _totalToday = 0;
  int _totalWeek = 0;
  int _totalMonth = 0;

  bool _computed = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Compute after first frame so provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _compute());
  }

  @override
  void dispose() {
    _bgController.dispose();
    _barController.dispose();
    super.dispose();
  }

  void _compute() {
    final provider = context.read<IptvProvider>();
    final history = provider.watchHistory;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);

    int totalToday = 0, totalWeek = 0, totalMonth = 0;
    for (final e in history) {
      final dur = e.totalDurationSeconds.toInt();
      if (e.watchedAt.isAfter(todayStart)) totalToday += dur;
      if (e.watchedAt.isAfter(weekStart)) totalWeek += dur;
      if (e.watchedAt.isAfter(monthStart)) totalMonth += dur;
    }

    // Daily stats — 7 derniers jours
    final Map<String, int> dayMap = {};
    for (int i = 6; i >= 0; i--) {
      final d = todayStart.subtract(Duration(days: i));
      dayMap['${d.year}-${d.month}-${d.day}'] = 0;
    }
    for (final e in history) {
      final key = '${e.watchedAt.year}-${e.watchedAt.month}-${e.watchedAt.day}';
      if (dayMap.containsKey(key)) {
        dayMap[key] = (dayMap[key] ?? 0) + e.totalDurationSeconds.toInt();
      }
    }
    final dailyStats = dayMap.entries.map((kv) {
      final parts = kv.key.split('-');
      return DailyStats(
        date: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
        totalSeconds: kv.value,
      );
    }).toList();

    // Top contents by streamId+tabIndex
    final Map<String, TopContent> map = {};
    for (final e in history) {
      final key = '${e.streamId}_${e.tabIndex}';
      if (map.containsKey(key)) {
        final ex = map[key]!;
        map[key] = TopContent(
          streamId: ex.streamId, tabIndex: ex.tabIndex,
          title: ex.title, streamIcon: ex.streamIcon,
          totalSeconds: ex.totalSeconds + e.totalDurationSeconds.toInt(),
          viewCount: ex.viewCount + 1,
        );
      } else {
        map[key] = TopContent(
          streamId: e.streamId, tabIndex: e.tabIndex,
          title: e.title, streamIcon: e.streamIcon,
          totalSeconds: e.totalDurationSeconds.toInt(), viewCount: 1,
        );
      }
    }
    final all = map.values.toList()
      ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));

    if (!mounted) return;
    setState(() {
      _dailyStats = dailyStats;
      _topLive    = all.where((c) => c.tabIndex == 1).take(10).toList();
      _topMovies  = all.where((c) => c.tabIndex == 2).take(10).toList();
      _topSeries  = all.where((c) => c.tabIndex == 3).take(10).toList();
      _totalToday = totalToday;
      _totalWeek  = totalWeek;
      _totalMonth = totalMonth;
      _computed   = true;
    });
    _barController.forward(from: 0);
  }

  String _fmt(int seconds) {
    if (seconds <= 0) return '0min';
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m}min';
  }

  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTV = context.isTV;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          RepaintBoundary(child: _AmbientBg(controller: _bgController)),
          SafeArea(
            child: isTV || isLandscape
                ? _buildLandscape(isTV)
                : _buildPortrait(),
          ),
        ],
      ),
    );
  }

  Widget _buildPortrait() {
    return Column(
      children: [
        _buildAppBar(),
        _buildTabBar(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: KeyedSubtree(
              key: ValueKey(_activeTab),
              child: _buildContent(false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape(bool isTV) {
    return Row(
      children: [
        _buildSidebar(isTV),
        Expanded(
          child: Column(
            children: [
              _buildAppBar(compact: true),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: KeyedSubtree(
                    key: ValueKey(_activeTab),
                    child: _buildContent(isTV),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20, vertical: compact ? 12 : 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.violet.withOpacity(0.25), width: 1),
        ),
      ),
      child: Row(
        children: [
          FocusableInk(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: 10.0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.violet.withOpacity(0.3)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (b) => AppTheme.gradientHorizontal.createShader(b),
            child: Text(
              'STATISTIQUES',
              style: GoogleFonts.rajdhani(
                fontSize: compact ? 20 : 24, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: 2,
              ),
            ),
          ),
          const Spacer(),
          if (_computed)
            Selector<IptvProvider, int>(
              selector: (_, p) => p.watchHistory.length,
              builder: (_, count, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientHorizontal,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.glowViolet(),
                ),
                child: Text('$count sessions',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.violet.withOpacity(0.15)),
      ),
      child: Row(
        children: StatsTab.values.map((tab) {
          final active = tab == _activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  gradient: active ? AppTheme.gradientHorizontal : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active ? AppTheme.glowViolet() : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_tabIcon(tab), size: 16, color: active ? Colors.white : AppTheme.textSecondary),
                    const SizedBox(height: 2),
                    Text(_tabLabel(tab),
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                            color: active ? Colors.white : AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSidebar(bool isTV) {
    return Container(
      width: isTV ? 200 : 176,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.85),
        border: Border(right: BorderSide(color: AppTheme.violet.withOpacity(0.2), width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          ...StatsTab.values.asMap().entries.map((entry) {
            final i = entry.key;
            final tab = entry.value;
            return ClipRect(
              child: _SidebarItem(
                label: _tabLabel(tab),
                icon: _tabIcon(tab),
                active: tab == _activeTab,
                isTV: isTV,
                autofocus: i == 0,
                onTap: () => setState(() => _activeTab = tab),
              ).animate().slideX(
                    begin: -0.3, end: 0,
                    delay: Duration(milliseconds: i.clamp(0, 8) * 40),
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOut,
                  ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContent(bool isTV) {
    if (!_computed) return const Center(child: _LoadingPulse());
    switch (_activeTab) {
      case StatsTab.overview:
        return _OverviewTab(
          period: _period,
          onPeriodChanged: (p) {
            setState(() => _period = p);
            _barController.forward(from: 0);
          },
          totalToday: _totalToday,
          totalWeek: _totalWeek,
          totalMonth: _totalMonth,
          dailyStats: _dailyStats,
          barController: _barController,
          fmt: _fmt,
          isTV: isTV,
        );
      case StatsTab.topContent:
        return _TopContentTab(
            topLive: _topLive, topMovies: _topMovies, topSeries: _topSeries,
            fmt: _fmt, isTV: isTV);
      case StatsTab.history:
        return _HistoryTab(fmt: _fmt, isTV: isTV);
      case StatsTab.account:
        return _AccountTab(isTV: isTV);
    }
  }

  String _tabLabel(StatsTab tab) {
    switch (tab) {
      case StatsTab.overview:   return 'Aperçu';
      case StatsTab.topContent: return 'Top';
      case StatsTab.history:    return 'Historique';
      case StatsTab.account:    return 'Compte';
    }
  }

  IconData _tabIcon(StatsTab tab) {
    switch (tab) {
      case StatsTab.overview:   return Icons.bar_chart_rounded;
      case StatsTab.topContent: return Icons.star_rounded;
      case StatsTab.history:    return Icons.history_rounded;
      case StatsTab.account:    return Icons.account_circle_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// OVERVIEW TAB
// ─────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final TimePeriod period;
  final ValueChanged<TimePeriod> onPeriodChanged;
  final int totalToday, totalWeek, totalMonth;
  final List<DailyStats> dailyStats;
  final AnimationController barController;
  final String Function(int) fmt;
  final bool isTV;

  const _OverviewTab({
    required this.period, required this.onPeriodChanged,
    required this.totalToday, required this.totalWeek, required this.totalMonth,
    required this.dailyStats, required this.barController,
    required this.fmt, required this.isTV,
  });

  int get _cur => period == TimePeriod.today ? totalToday : period == TimePeriod.week ? totalWeek : totalMonth;
  String get _label => period == TimePeriod.today ? "Aujourd'hui" : period == TimePeriod.week ? 'Cette semaine' : 'Ce mois';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(isTV ? 24 : 16),
      children: [
        _PeriodSelector(period: period, onChanged: onPeriodChanged),
        const SizedBox(height: 20),

        _BigStatCard(value: fmt(_cur), label: 'Temps de visionnage', subtitle: _label)
            .animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, end: 0),

        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(child: _MiniStatCard(icon: Icons.today_rounded, label: "Auj.", value: fmt(totalToday), color: AppTheme.violet)),
            const SizedBox(width: 10),
            Expanded(child: _MiniStatCard(icon: Icons.date_range_rounded, label: 'Semaine', value: fmt(totalWeek), color: AppTheme.secondary)),
            const SizedBox(width: 10),
            Expanded(child: _MiniStatCard(icon: Icons.calendar_month_rounded, label: 'Mois', value: fmt(totalMonth), color: AppTheme.catSeriesAccent)),
          ],
        ).animate().fadeIn(delay: 80.ms, duration: 400.ms),

        const SizedBox(height: 24),
        _SectionHeader(label: '7 DERNIERS JOURS', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 12),

        RepaintBoundary(
          child: _BarChart(data: dailyStats, controller: barController, fmt: fmt),
        ).animate().fadeIn(delay: 160.ms, duration: 400.ms),

        const SizedBox(height: 24),
        _SectionHeader(label: 'RÉSUMÉ', icon: Icons.summarize_rounded),
        const SizedBox(height: 12),

        Selector<IptvProvider, _SummaryData>(
          selector: (_, p) => _SummaryData(
            count: p.watchHistory.length,
            live: p.allLive.length,
            movies: p.allMovies.length,
            series: p.allSeries.length,
          ),
          builder: (_, data, __) =>
              _SummaryCard(data: data, fmt: fmt, totalWeek: totalWeek)
                  .animate().fadeIn(delay: 240.ms),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

class _SummaryData {
  final int count, live, movies, series;
  _SummaryData({required this.count, required this.live, required this.movies, required this.series});
  @override bool operator ==(Object o) => o is _SummaryData && o.count == count && o.live == live && o.movies == movies && o.series == series;
  @override int get hashCode => Object.hash(count, live, movies, series);
}

// ─────────────────────────────────────────────────────────────────
// TOP CONTENT TAB
// ─────────────────────────────────────────────────────────────────

class _TopContentTab extends StatefulWidget {
  final List<TopContent> topLive, topMovies, topSeries;
  final String Function(int) fmt;
  final bool isTV;
  const _TopContentTab({required this.topLive, required this.topMovies, required this.topSeries, required this.fmt, required this.isTV});

  @override
  State<_TopContentTab> createState() => _TopContentTabState();
}

class _TopContentTabState extends State<_TopContentTab> {
  int _idx = 0;
  List<TopContent> get _list => _idx == 0 ? widget.topLive : _idx == 1 ? widget.topMovies : widget.topSeries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _TypeChip(label: 'Direct', icon: Icons.live_tv_rounded, active: _idx == 0, onTap: () => setState(() => _idx = 0)),
              const SizedBox(width: 8),
              _TypeChip(label: 'Films', icon: Icons.movie_rounded, active: _idx == 1, onTap: () => setState(() => _idx = 1)),
              const SizedBox(width: 8),
              _TypeChip(label: 'Séries', icon: Icons.tv_rounded, active: _idx == 2, onTap: () => setState(() => _idx = 2)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _list.isEmpty
              ? _EmptyState(icon: Icons.star_border_rounded, message: 'Aucun contenu regardé')
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: widget.isTV ? 24 : 16, vertical: 8),
                  itemCount: _list.length,
                  itemBuilder: (_, i) => _TopContentCard(
                    rank: i + 1, content: _list[i],
                    fmt: widget.fmt, maxSeconds: _list.first.totalSeconds,
                  )
                      .animate()
                      .fadeIn(delay: Duration(milliseconds: i.clamp(0, 8) * 40), duration: 350.ms)
                      .slideX(begin: 0.1, end: 0),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// HISTORY TAB
// ─────────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final String Function(int) fmt;
  final bool isTV;
  const _HistoryTab({required this.fmt, required this.isTV});

  @override
  Widget build(BuildContext context) {
    return Selector<IptvProvider, List<HistoryEntry>>(
      selector: (_, p) => p.watchHistory.take(30).toList(),
      builder: (_, history, __) {
        if (history.isEmpty) {
          return _EmptyState(icon: Icons.history_rounded, message: 'Aucun historique disponible');
        }
        return ListView.builder(
          padding: EdgeInsets.all(isTV ? 24 : 16),
          itemCount: history.length,
          itemBuilder: (_, i) => _HistoryCard(entry: history[i], fmt: fmt)
              .animate()
              .fadeIn(delay: Duration(milliseconds: i.clamp(0, 8) * 40), duration: 350.ms)
              .slideX(begin: 0.05, end: 0),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ACCOUNT TAB — vrais champs IptvProvider
// ─────────────────────────────────────────────────────────────────

class _AccountTab extends StatelessWidget {
  final bool isTV;
  const _AccountTab({required this.isTV});

  @override
  Widget build(BuildContext context) {
    return Selector<IptvProvider, _AccountData>(
      selector: (_, p) => _AccountData(
        expirationDate: p.expirationDate,
        maxConnections: p.maxConnections,
        activeConnections: p.activeConnections,
        accountStatus: p.accountStatus,
        sourceType: p.sourceType,
        username: p.username,
        liveCount: p.allLive.length,
        movieCount: p.allMovies.length,
        seriesCount: p.allSeries.length,
        favCount: p.favorites.length,
      ),
      builder: (_, data, __) {
        final isActive = data.accountStatus.toLowerCase() == 'active';
        return ListView(
          padding: EdgeInsets.all(isTV ? 24 : 16),
          children: [
            Center(child: _StatusBadge(active: isActive, label: data.accountStatus))
                .animate().fadeIn(duration: 400.ms),
            const SizedBox(height: 24),

            _SectionHeader(label: 'ABONNEMENT', icon: Icons.card_membership_rounded),
            const SizedBox(height: 12),

            _InfoCard(items: [
              _InfoRow(icon: Icons.calendar_today_rounded, label: 'Expiration', value: data.expirationDate,
                  color: isActive ? AppTheme.success : AppTheme.error),
              _InfoRow(icon: Icons.person_rounded, label: 'Utilisateur',
                  value: data.username.isNotEmpty ? data.username : '—', color: AppTheme.violet),
              _InfoRow(icon: Icons.dns_rounded, label: 'Source', value: _srcLabel(data.sourceType), color: AppTheme.secondary),
            ]).animate().fadeIn(delay: 80.ms),

            const SizedBox(height: 20),
            _SectionHeader(label: 'CONNEXIONS', icon: Icons.link_rounded),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _MiniStatCard(icon: Icons.devices_rounded, label: 'Max', value: data.maxConnections, color: AppTheme.violet)),
                const SizedBox(width: 10),
                Expanded(child: _MiniStatCard(icon: Icons.cast_connected_rounded, label: 'Actives',
                    value: data.activeConnections, color: isActive ? AppTheme.success : AppTheme.error)),
              ],
            ).animate().fadeIn(delay: 160.ms),

            const SizedBox(height: 20),
            _SectionHeader(label: 'CATALOGUE CHARGÉ', icon: Icons.video_library_rounded),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _MiniStatCard(icon: Icons.live_tv_rounded, label: 'Chaînes', value: _fmt(data.liveCount), color: AppTheme.red)),
                const SizedBox(width: 8),
                Expanded(child: _MiniStatCard(icon: Icons.movie_rounded, label: 'Films', value: _fmt(data.movieCount), color: AppTheme.secondary)),
                const SizedBox(width: 8),
                Expanded(child: _MiniStatCard(icon: Icons.tv_rounded, label: 'Séries', value: _fmt(data.seriesCount), color: AppTheme.catSeriesAccent)),
              ],
            ).animate().fadeIn(delay: 240.ms),

            const SizedBox(height: 20),
            _SectionHeader(label: 'MES FAVORIS', icon: Icons.favorite_rounded),
            const SizedBox(height: 12),

            _InfoCard(items: [
              _InfoRow(icon: Icons.favorite_rounded, label: 'Contenus en favoris', value: '${data.favCount}', color: AppTheme.red),
            ]).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  String _srcLabel(SourceType t) {
    switch (t) {
      case SourceType.xtream: return 'Xtream Codes';
      case SourceType.m3u:    return 'M3U Playlist';
      case SourceType.direct: return 'Direct';
    }
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

class _AccountData {
  final String expirationDate, maxConnections, activeConnections, accountStatus, username;
  final SourceType sourceType;
  final int liveCount, movieCount, seriesCount, favCount;

  const _AccountData({
    required this.expirationDate, required this.maxConnections,
    required this.activeConnections, required this.accountStatus, required this.username,
    required this.sourceType, required this.liveCount, required this.movieCount,
    required this.seriesCount, required this.favCount,
  });

  @override
  bool operator ==(Object o) =>
      o is _AccountData &&
      o.expirationDate == expirationDate && o.maxConnections == maxConnections &&
      o.activeConnections == activeConnections && o.accountStatus == accountStatus &&
      o.liveCount == liveCount && o.movieCount == movieCount &&
      o.seriesCount == seriesCount && o.favCount == favCount;

  @override
  int get hashCode => Object.hash(expirationDate, maxConnections, activeConnections,
      accountStatus, liveCount, movieCount, seriesCount, favCount);
}

// ─────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────

class _AmbientBg extends StatelessWidget {
  final AnimationController controller;
  const _AmbientBg({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final size = MediaQuery.sizeOf(context);
        return CustomPaint(size: size, painter: _AmbientPainter(controller.value));
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double t;
  _AmbientPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * (0.2 + 0.12 * math.sin(t * math.pi * 2)), size.height * 0.25),
      size.width * 0.4,
      Paint()
        ..shader = RadialGradient(
          colors: [AppTheme.violet.withOpacity(0.11), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * (0.2 + 0.12 * math.sin(t * math.pi * 2)), size.height * 0.25),
          radius: size.width * 0.4,
        )),
    );
    canvas.drawCircle(
      Offset(size.width * (0.8 + 0.08 * math.cos(t * math.pi * 2)), size.height * 0.75),
      size.width * 0.35,
      Paint()
        ..shader = RadialGradient(
          colors: [AppTheme.red.withOpacity(0.07), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * (0.8 + 0.08 * math.cos(t * math.pi * 2)), size.height * 0.75),
          radius: size.width * 0.35,
        )),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t;
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 26,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientVertical,
            borderRadius: BorderRadius.circular(2),
            boxShadow: AppTheme.glowViolet(),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(gradient: AppTheme.gradientHorizontal, borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, color: Colors.white, size: 13),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5)),
      ],
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final TimePeriod period;
  final ValueChanged<TimePeriod> onChanged;
  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = ["Aujourd'hui", 'Semaine', 'Mois'];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.violet.withOpacity(0.2)),
      ),
      child: Row(
        children: TimePeriod.values.asMap().entries.map((e) {
          final active = e.value == period;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: active ? AppTheme.gradientHorizontal : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active ? AppTheme.glowViolet() : null,
                ),
                alignment: Alignment.center,
                child: Text(labels[e.key],
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? Colors.white : AppTheme.textSecondary)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  final String value, label, subtitle;
  const _BigStatCard({required this.value, required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.violet.withOpacity(0.18), AppTheme.red.withOpacity(0.09)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.violet.withOpacity(0.4)),
        boxShadow: AppTheme.glowViolet(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.violet.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.violet.withOpacity(0.35)),
            ),
            child: Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.violet, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          ShaderMask(
            shaderCallback: (b) => AppTheme.gradientHorizontal.createShader(b),
            child: Text(value,
                style: GoogleFonts.rajdhani(fontSize: 52, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
          ),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MiniStatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.rajdhani(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<DailyStats> data;
  final AnimationController controller;
  final String Function(int) fmt;
  const _BarChart({required this.data, required this.controller, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 120);
    final maxVal = data.map((d) => d.totalSeconds).reduce(math.max);
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Container(
          height: 160,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.asMap().entries.map((entry) {
              final i = entry.key;
              final d = entry.value;
              final ratio = maxVal > 0 ? d.totalSeconds / maxVal : 0.0;
              final animRatio = (ratio * controller.value).clamp(0.0, 1.0);
              final isToday = i == data.length - 1;
              final dayLabel = days[d.date.weekday % 7];

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (d.totalSeconds > 0)
                        Text(fmt(d.totalSeconds),
                            style: GoogleFonts.inter(fontSize: 8, color: isToday ? AppTheme.violet : AppTheme.textSecondary),
                            textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Container(
                        height: 110 * animRatio,
                        decoration: BoxDecoration(
                          gradient: isToday
                              ? AppTheme.gradientVertical
                              : LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [AppTheme.violet.withOpacity(0.55), AppTheme.violet.withOpacity(0.2)],
                                ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          boxShadow: isToday ? AppTheme.glowViolet() : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(dayLabel,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isToday ? Colors.white : AppTheme.textSecondary,
                              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _SummaryData data;
  final String Function(int) fmt;
  final int totalWeek;
  const _SummaryCard({required this.data, required this.fmt, required this.totalWeek});

  @override
  Widget build(BuildContext context) {
    final avgPerDay = totalWeek > 0 ? totalWeek ~/ 7 : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.violet.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          _SummaryRow(icon: Icons.play_circle_outline_rounded, label: 'Sessions totales', value: '${data.count}'),
          _DividerLine(),
          _SummaryRow(icon: Icons.trending_up_rounded, label: 'Moy. quotidienne', value: fmt(avgPerDay)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SummaryRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.violet, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary))),
          Text(value, style: GoogleFonts.rajdhani(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.transparent, AppTheme.violet.withOpacity(0.25), Colors.transparent]),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active, isTV, autofocus;
  final VoidCallback onTap;
  const _SidebarItem({required this.label, required this.icon, required this.active, required this.isTV, required this.autofocus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: FocusableInk(
        onTap: onTap,
        autofocus: autofocus && isTV,
        borderRadius: 12.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppTheme.gradientHorizontal : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active ? AppTheme.glowViolet() : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 10),
              Flexible(
                child: Text(label,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _TypeChip({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? AppTheme.gradientHorizontal : null,
          color: active ? null : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? Colors.transparent : AppTheme.violet.withOpacity(0.22)),
          boxShadow: active ? AppTheme.glowViolet() : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? Colors.white : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _TopContentCard extends StatelessWidget {
  final int rank, maxSeconds;
  final TopContent content;
  final String Function(int) fmt;
  const _TopContentCard({required this.rank, required this.content, required this.fmt, required this.maxSeconds});

  Color get _rankColor => rank == 1 ? AppTheme.gold : rank == 2 ? Colors.white54 : AppTheme.violet.withOpacity(0.5);

  @override
  Widget build(BuildContext context) {
    final progress = maxSeconds > 0 ? content.totalSeconds / maxSeconds : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(width: 3, color: _rankColor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: GoogleFonts.rajdhani(fontSize: rank <= 3 ? 22 : 16, fontWeight: FontWeight.w800, color: _rankColor),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          if (content.streamIcon.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: content.streamIcon, width: 36, height: 36, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _iconFallback,
              ),
            )
          else
            _iconFallback,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(content.title,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${content.viewCount} vue${content.viewCount > 1 ? 's' : ''} · ${fmt(content.totalSeconds)}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 3, color: AppTheme.surfaceTop,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft, widthFactor: progress,
                      child: Container(
                          decoration: BoxDecoration(gradient: AppTheme.gradientHorizontal, borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget get _iconFallback => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(8)),
    child: Icon(content.tabIndex == 1 ? Icons.live_tv_rounded : content.tabIndex == 2 ? Icons.movie_rounded : Icons.tv_rounded,
        size: 16, color: AppTheme.textSecondary),
  );
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final String Function(int) fmt;
  const _HistoryCard({required this.entry, required this.fmt});

  Color get _typeColor => entry.tabIndex == 1 ? AppTheme.red : entry.tabIndex == 2 ? AppTheme.secondary : AppTheme.catSeriesAccent;
  String get _typeLabel => entry.tabIndex == 1 ? 'DIRECT' : entry.tabIndex == 2 ? 'FILM' : 'SÉRIE';

  String _rel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.violet.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          if (entry.streamIcon.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: entry.streamIcon, width: 32, height: 32, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback,
              ),
            )
          else
            _fallback,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _typeColor.withOpacity(0.14), borderRadius: BorderRadius.circular(4)),
                      child: Text(_typeLabel,
                          style: GoogleFonts.rajdhani(fontSize: 9, fontWeight: FontWeight.w700, color: _typeColor, letterSpacing: 0.8)),
                    ),
                    const Spacer(),
                    Text(_rel(entry.watchedAt), style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(entry.title,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                // Barre de progression pour films/séries
                if (entry.tabIndex != 1 && entry.progressRatio > 0) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 3, color: AppTheme.surfaceTop,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: entry.progressRatio,
                        child: Container(
                            decoration: BoxDecoration(gradient: AppTheme.gradientHorizontal, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget get _fallback => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(6)),
    child: Icon(entry.tabIndex == 1 ? Icons.live_tv_rounded : entry.tabIndex == 2 ? Icons.movie_rounded : Icons.tv_rounded,
        size: 14, color: _typeColor),
  );
}

// ─── ACCOUNT CHILD WIDGETS ────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool active;
  final String label;
  const _StatusBadge({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.success : AppTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.violet.withOpacity(0.12)),
      ),
      child: Column(
        children: items.asMap().entries.map((e) => Column(
          children: [
            e.value,
            if (e.key < items.length - 1) _DividerLine(),
          ],
        )).toList(),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary))),
          Flexible(
            child: Text(value,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ─── EMPTY + LOADING ──────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface, shape: BoxShape.circle,
              border: Border.all(color: AppTheme.violet.withOpacity(0.2)),
            ),
            child: Icon(icon, size: 36, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(message, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('Regardez du contenu pour le voir apparaître ici',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.92, 0.92));
  }
}

class _LoadingPulse extends StatelessWidget {
  const _LoadingPulse();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientHorizontal,
            shape: BoxShape.circle,
            boxShadow: AppTheme.glowViolet(),
          ),
          child: const Center(
              child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))),
        ),
        const SizedBox(height: 16),
        Text('Calcul des statistiques…', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}