// lib/ui/screens/favorites_screen.dart
//
// Arich Player — Écran Favoris & Historique — v2 AAA
//
// Nouveautés v2 :
//  • AppBar backdrop-blur avec border gradient violet→red + glow
//  • Section headers accent 3px gradient + icon pill + letterSpacing 1.5
//  • TabBar redesigné : pill gradient actif + compteurs gradient badge
//  • Barre de recherche : border gradient actif + icône animée
//  • Bouton tri : pill gradient horizontal avec chevron animé
//  • _FavCard AAA : gradient dark multicouche + left border accent 3px gradient
//    + play button gradient + barre reprise gradient + glow au hover
//  • _TypeBadge : pill gradient avec glow
//  • Empty state : icon container gradient double shadow + texte letterSpacing
//  • Bouton vider historique : destructive avec animation pulse
//  • Bottom sheet tri : drag handle gradient + items avec fond actif gradient
//  • Dialogs : border gradient + bouton destructif gradient rouge
//  • Animations staggered entrée + shimmer skeleton via flutter_animate
//  • Support TV : FocusableInk + autofocus + TvFocusZone
//  • Bypass BackdropFilter sur Tizen
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../core/tv_navigation.dart';
import '../../providers/iptv_provider.dart';
import '../widgets/focusable_ink.dart';
import 'player_screen.dart';
import 'details_screen.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';

// ── Tri ───────────────────────────────────────────────────────────────────────
enum _SortOrder { dateDesc, dateAsc, az, za }

extension _SortLabel on _SortOrder {
  String get label => switch (this) {
    _SortOrder.dateDesc => 'Plus récent',
    _SortOrder.dateAsc  => 'Plus ancien',
    _SortOrder.az       => 'A → Z',
    _SortOrder.za       => 'Z → A',
  };
  IconData get icon => switch (this) {
    _SortOrder.dateDesc => Icons.schedule_rounded,
    _SortOrder.dateAsc  => Icons.history_rounded,
    _SortOrder.az       => Icons.sort_by_alpha_rounded,
    _SortOrder.za       => Icons.sort_by_alpha_rounded,
  };
}

class FavoritesScreen extends StatefulWidget {
  /// Onglet initial : 0=Live, 1=Films, 2=Séries, 3=Historique
  final int initialTab;
  const FavoritesScreen({super.key, this.initialTab = 0});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _SortOrder _sort = _SortOrder.dateDesc;
  bool _searchFocused = false;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 4, vsync: this, initialIndex: widget.initialTab);
    _searchCtrl
        .addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _searchFocus.addListener(
        () => setState(() => _searchFocused = _searchFocus.hasFocus));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider    = context.watch<IptvProvider>();
    final isTV        = context.isTV;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isTizen     = Platform.operatingSystem == 'tizen';

    return TvBackHandler(
      onBack: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(isTV, isTizen),
              _buildSearchBar(),
              _buildTabBar(provider),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildFavTab(provider,
                        tabIndex: 1, isTV: isTV, isLandscape: isLandscape),
                    _buildFavTab(provider,
                        tabIndex: 2, isTV: isTV, isLandscape: isLandscape),
                    _buildFavTab(provider,
                        tabIndex: 3, isTV: isTV, isLandscape: isLandscape),
                    _buildHistoryTab(provider,
                        isTV: isTV, isLandscape: isLandscape),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(bool isTV, bool isTizen) {
    final bar = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(0.92),
        border: Border(
          bottom: BorderSide(
            color: Colors.transparent,
            width: 0,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          FocusableInk(
            onTap: () => Navigator.pop(context),
            borderRadius: 18,
            focusColor: AppTheme.violet,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.violet.withOpacity(0.18),
                    AppTheme.red.withOpacity(0.12),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.violet.withOpacity(0.25), width: 1),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 12),

          // Icon pill gradient
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(9),
              boxShadow: AppTheme.glowViolet(),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),

          // Title
          const Text(
            'Favoris & Historique',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),

          // Sort button
          FocusableInk(
            onTap: _showSortPicker,
            borderRadius: 12,
            focusColor: AppTheme.violet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.violet.withOpacity(0.15),
                    AppTheme.red.withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.violet.withOpacity(0.22), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_sort.icon, color: AppTheme.violet, size: 12),
                  const SizedBox(width: 5),
                  Text(
                    _sort.label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded,
                      color: AppTheme.textMuted, size: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Gradient border bas
    return Stack(
      children: [
        bar,
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppTheme.violet.withOpacity(0.4),
                  AppTheme.red.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _searchFocused
              ? AppTheme.violet.withOpacity(0.5)
              : Colors.white.withOpacity(0.07),
          width: _searchFocused ? 1.5 : 1,
        ),
        boxShadow: _searchFocused
            ? [
                BoxShadow(
                  color: AppTheme.violet.withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          const SizedBox(width: 13),
          AnimatedSwitcher(
            duration: 200.ms,
            child: Icon(
              _searchFocused
                  ? Icons.search_rounded
                  : Icons.search_rounded,
              color: _searchFocused ? AppTheme.violet : AppTheme.textMuted,
              size: 16,
              key: ValueKey(_searchFocused),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style:
                  TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: context.read<LanguageProvider>().l10n.t('fav_search'),
                hintStyle:
                    TextStyle(color: AppTheme.textMuted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
              ),
              cursorColor: AppTheme.violet,
            ),
          ),
          if (_query.isNotEmpty)
            FocusableInk(
              onTap: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
              borderRadius: 10,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    color: AppTheme.textMuted, size: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────────────────────

  // Selector isole les compteurs : rebuild TabBar seulement si les longueurs changent
  Widget _buildTabBar(IptvProvider provider) {
    return Selector<IptvProvider, (int, int, int, int)>(
      selector: (_, p) => (
        p.favorites.where((f) => f.tabIndex == 1).length,
        p.favorites.where((f) => f.tabIndex == 2).length,
        p.favorites.where((f) => f.tabIndex == 3).length,
        p.watchHistory.length,
      ),
      builder: (_, counts, __) {
        final (favLive, favMovies, favSeries, history) = counts;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(10),
              boxShadow: AppTheme.glowViolet(),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(3),
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            tabs: [
              _tab(Icons.live_tv_rounded, 'Live', favLive),
              _tab(Icons.movie_rounded, 'Films', favMovies),
              _tab(Icons.tv_rounded, 'Séries', favSeries),
              _tab(Icons.history_rounded, 'Historique', history),
            ],
          ),
        );
      },
    );
  }

  Tab _tab(IconData icon, String label, int count) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 12),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          // Badge compteur gradient pill
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.violet.withOpacity(0.35),
                  AppTheme.red.withOpacity(0.25),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ],
    ),
  );

  // ── Favoris tab ────────────────────────────────────────────────────────────

  Widget _buildFavTab(
    IptvProvider provider, {
    required int tabIndex,
    required bool isTV,
    required bool isLandscape,
  }) {
    final items = _sortedFavs(_filteredFavs(provider, tabIndex));

    if (items.isEmpty) {
      return _buildEmpty(
        icon: tabIndex == 1
            ? Icons.live_tv_rounded
            : tabIndex == 2
                ? Icons.movie_rounded
                : Icons.tv_rounded,
        title: context.read<LanguageProvider>().l10n.t('fav_no_favorites'),
        subtitle: tabIndex == 1
            ? 'Ajoutez des chaînes live à vos favoris'
            : tabIndex == 2
                ? 'Ajoutez des films à vos favoris'
                : 'Ajoutez des séries à vos favoris',
      );
    }

    final cols = (isTV || isLandscape) ? 3 : 2;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: tabIndex == 1 ? 16 / 9 : 2 / 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final fav = items[i];
        return _FavCard(
          key: ValueKey('${fav.streamId}_${fav.tabIndex}'),
          streamIcon: fav.streamIcon,
          title: fav.title,
          tabIndex: fav.tabIndex,
          positionSeconds: 0,
          totalDurationSeconds: 0,
          animDelay: i * 30,
          onTap: () => _onFavTap(fav, provider),
          onDelete: () => _confirmDeleteFav(fav, provider),
        )
            .animate()
            .fadeIn(
                delay: Duration(milliseconds: i.clamp(0, 8) * 40),
                duration: 280.ms)
            .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
      },
    );
  }

  // ── Historique tab ─────────────────────────────────────────────────────────

  Widget _buildHistoryTab(
    IptvProvider provider, {
    required bool isTV,
    required bool isLandscape,
  }) {
    final items = _sortedHistory(_filteredHistory(provider));

    if (items.isEmpty) {
      return _buildEmpty(
        icon: Icons.history_rounded,
        title: context.read<LanguageProvider>().l10n.t('fav_history_empty'),
        subtitle: context.read<LanguageProvider>().l10n.t('fav_history_empty_sub'),
      );
    }

    final cols = (isTV || isLandscape) ? 3 : 2;

    return Column(
      children: [
        // Bouton vider l'historique
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: FocusableInk(
            onTap: () => _confirmClearHistory(provider),
            borderRadius: 11,
            focusColor: AppTheme.error,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.07),
                borderRadius: BorderRadius.circular(11),
                border:
                    Border.all(color: AppTheme.error.withOpacity(0.22)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_sweep_rounded,
                      color: AppTheme.error.withOpacity(0.75), size: 14),
                  const SizedBox(width: 7),
                  Text(
                    'Vider l\'historique',
                    style: TextStyle(
                      color: AppTheme.error.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .custom(
              duration: 3000.ms,
              builder: (_, value, child) => child,
            ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final entry = items[i];
              final pct = (entry.positionSeconds > 0 &&
                      entry.totalDurationSeconds > 0)
                  ? (entry.positionSeconds / entry.totalDurationSeconds)
                      .clamp(0.0, 1.0)
                  : 0.0;
              return _FavCard(
                key: ValueKey(
                    'hist_${entry.streamId}_${entry.tabIndex}'),
                streamIcon: entry.streamIcon,
                title: entry.title,
                tabIndex: entry.tabIndex,
                positionSeconds: entry.positionSeconds,
                totalDurationSeconds: entry.totalDurationSeconds,
                progressPct: pct,
                animDelay: i * 30,
                onTap: () => _onHistoryTap(entry, provider),
                onDelete: () => provider.removeFromHistory(
                    entry.streamId, entry.tabIndex),
              )
                  .animate()
                  .fadeIn(
                      delay: Duration(milliseconds: i * 40),
                      duration: 300.ms)
                  .slideY(
                      begin: 0.08, end: 0, curve: Curves.easeOutCubic);
            },
          ),
        ),
      ],
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon container double gradient shadow
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.violet.withOpacity(0.18),
                  AppTheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppTheme.violet.withOpacity(0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withOpacity(0.08),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: AppTheme.textMuted, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.textMuted.withOpacity(0.8),
              fontSize: 12,
              letterSpacing: 0.1,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      )
          .animate()
          .fadeIn(duration: 450.ms)
          .slideY(begin: 0.07, end: 0, curve: Curves.easeOutCubic),
    );
  }

  // ── Filtres / Tri ──────────────────────────────────────────────────────────

  List<FavoriteEntry> _filteredFavs(IptvProvider provider, int tabIndex) {
    final all = provider.favorites
        .where((f) => f.tabIndex == tabIndex)
        .toList();
    if (_query.isEmpty) return all;
    return all
        .where((f) => f.title.toLowerCase().contains(_query))
        .toList();
  }

  List<FavoriteEntry> _sortedFavs(List<FavoriteEntry> list) {
    final copy = List<FavoriteEntry>.from(list);
    switch (_sort) {
      case _SortOrder.dateDesc:
        break;
      case _SortOrder.dateAsc:
        copy;
        break;
      case _SortOrder.az:
        copy.sort((a, b) => a.title.compareTo(b.title));
        break;
      case _SortOrder.za:
        copy.sort((a, b) => b.title.compareTo(a.title));
        break;
    }
    return copy;
  }

  List<HistoryEntry> _filteredHistory(IptvProvider provider) {
    final all = provider.watchHistory;
    if (_query.isEmpty) return all;
    return all
        .where((h) => h.title.toLowerCase().contains(_query))
        .toList();
  }

  List<HistoryEntry> _sortedHistory(List<HistoryEntry> list) {
    final copy = List<HistoryEntry>.from(list);
    switch (_sort) {
      case _SortOrder.dateDesc:
        break;
      case _SortOrder.dateAsc:
        copy;
        break;
      case _SortOrder.az:
        copy.sort((a, b) => a.title.compareTo(b.title));
        break;
      case _SortOrder.za:
        copy.sort((a, b) => b.title.compareTo(a.title));
        break;
    }
    return copy;
  }

  // ── Sort picker ────────────────────────────────────────────────────────────

  void _showSortPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle gradient
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientHorizontal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              // Section header
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TRIER PAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._SortOrder.values.map((s) {
                final isSelected = _sort == s;
                return AnimatedContainer(
                  duration: 200.ms,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(colors: [
                            AppTheme.violet.withOpacity(0.15),
                            AppTheme.red.withOpacity(0.08),
                          ])
                        : null,
                    color: isSelected ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: isSelected
                        ? Border.all(
                            color: AppTheme.violet.withOpacity(0.25),
                            width: 1)
                        : null,
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? AppTheme.gradientPrimary
                            : null,
                        color: isSelected
                            ? null
                            : AppTheme.surface.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(s.icon,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textMuted,
                          size: 16),
                    ),
                    title: Text(
                      s.label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    trailing: isSelected
                        ? Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: AppTheme.gradientHorizontal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 12),
                          )
                        : null,
                    onTap: () {
                      setState(() => _sort = s);
                      Navigator.pop(context);
                    },
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _onFavTap(FavoriteEntry fav, IptvProvider provider) {
    final ch = fav.toChannel();
    if (fav.tabIndex == 1) {
      Navigator.push(
          context,
          _route(PlayerScreen(
            streamUrl: fav.streamUrl,
            title: fav.title,
            streamIcon: fav.streamIcon,
            streamId: fav.streamId,
            tabIndex: fav.tabIndex,
          )));
    } else {
      final list =
          fav.tabIndex == 2 ? provider.allMovies : provider.allSeries;
      final full =
          list.where((c) => c.streamId == fav.streamId).firstOrNull;
      Navigator.push(context,
          _route(DetailsScreen(item: full ?? ch, sourceTabIndex: fav.tabIndex)));
    }
  }

  void _onHistoryTap(HistoryEntry entry, IptvProvider provider) {
    if (entry.tabIndex == 1) {
      Navigator.push(
          context,
          _route(PlayerScreen(
            streamUrl: entry.streamUrl,
            title: entry.title,
            streamIcon: entry.streamIcon,
            streamId: entry.streamId,
            tabIndex: entry.tabIndex,
          )));
    } else {
      final list = entry.tabIndex == 2
          ? provider.allMovies
          : provider.allSeries;
      final ch =
          list.where((c) => c.streamId == entry.streamId).firstOrNull;
      Navigator.push(
          context,
          _route(ch != null
              ? DetailsScreen(item: ch, sourceTabIndex: entry.tabIndex)
              : PlayerScreen(
                  streamUrl: entry.streamUrl,
                  title: entry.title,
                  streamIcon: entry.streamIcon,
                  streamId: entry.streamId,
                  tabIndex: entry.tabIndex)));
    }
  }

  PageRoute _route(Widget screen) => PageRouteBuilder(
        pageBuilder: (_, a, __) => screen,
        transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child),
        transitionDuration: const Duration(milliseconds: 300),
      );

  // ── Suppression ────────────────────────────────────────────────────────────

  void _confirmDeleteFav(FavoriteEntry fav, IptvProvider provider) {
    showDialog(
      context: context,
      builder: (_) => _GradientDialog(
        title: context.read<LanguageProvider>().l10n.t('fav_remove'),
        content: 'Retirer "${fav.title}" de vos favoris ?',
        confirmLabel: 'Retirer',
        onConfirm: () => provider.removeFavorite(fav.streamId, fav.tabIndex),
      ),
    );
  }

  void _confirmClearHistory(IptvProvider provider) {
    showDialog(
      context: context,
      builder: (_) => _GradientDialog(
        title: context.read<LanguageProvider>().l10n.t('fav_clear_history'),
        content: 'Supprimer tout l\'historique de visionnage ?',
        confirmLabel: 'Vider',
        onConfirm: () => provider.clearHistory(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DIALOG AAA avec border gradient
// ═════════════════════════════════════════════════════════════════════════════

class _GradientDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final VoidCallback onConfirm;

  const _GradientDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.violet.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.violet.withOpacity(0.08),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title avec accent
            Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            // Séparateur gradient
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppTheme.violet.withOpacity(0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.read<LanguageProvider>().l10n.t('cancel'),
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 4),
                // Bouton destructif gradient rouge
                FocusableInk(
                  onTap: () {
                    Navigator.pop(context);
                    onConfirm();
                  },
                  borderRadius: 10,
                  focusColor: AppTheme.error,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.error.withOpacity(0.85),
                          AppTheme.error.withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.error.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WIDGET CARTE FAVORI / HISTORIQUE — AAA
// ═════════════════════════════════════════════════════════════════════════════

class _FavCard extends StatefulWidget {
  final String streamIcon;
  final String title;
  final int    tabIndex;
  final int    positionSeconds;
  final int    totalDurationSeconds;
  final double progressPct;
  final int    animDelay;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _FavCard({
    super.key,
    required this.streamIcon,
    required this.title,
    required this.tabIndex,
    required this.positionSeconds,
    required this.totalDurationSeconds,
    required this.onTap,
    required this.onDelete,
    this.progressPct = 0,
    this.animDelay = 0,
  });

  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLive = widget.tabIndex == 1;
    // hover uniquement sur desktop/TV — pas de MouseRegion sur Android (rebuilds inutiles)
    final isTouch = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    Widget card = AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.surface, Color(0xFF0A0A18)],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: _hovered
                  ? AppTheme.violet.withOpacity(0.35)
                  : Colors.white.withOpacity(0.07),
              width: _hovered ? 1.5 : 1,
            ),
            boxShadow: _hovered
                ? [BoxShadow(
                    color: AppTheme.violet.withOpacity(0.15),
                    blurRadius: 20, spreadRadius: 1)]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail — CachedNetworkImage évite les re-téléchargements
              widget.streamIcon.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.streamIcon,
                      fit: isLive ? BoxFit.contain : BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallback(),
                      placeholder: (_, __) => _fallback(),
                    )
                  : _fallback(),

              // Gradient overlay multicouche bas
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.92),
                        Colors.black.withOpacity(0.15),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 0.75],
                    ),
                  ),
                ),
              ),

              // Left border accent 3px gradient violet
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                  ),
                ),
              ),

              // Badge type
              Positioned(
                top: 7,
                left: 10,
                child: _TypeBadge(widget.tabIndex),
              ),

              // Bouton supprimer
              Positioned(
                top: 5,
                right: 5,
                child: FocusableInk(
                  onTap: widget.onDelete,
                  borderRadius: 12,
                  focusColor: AppTheme.error,
                  child: AnimatedContainer(
                    duration: 150.ms,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? Colors.black.withOpacity(0.75)
                          : Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1), width: 0.5),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 12),
                  ),
                ),
              ),

              // Play button au centre (visible au hover)
              if (_hovered)
                Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientHorizontal,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.glowViolet(),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 20),
                  )
                      .animate()
                      .scale(
                          begin: const Offset(0.6, 0.6),
                          duration: 180.ms,
                          curve: Curves.easeOutBack)
                      .fadeIn(duration: 150.ms),
                ),

              // Titre
              Positioned(
                bottom: widget.progressPct > 0 ? 14 : 8,
                left: 10,
                right: 8,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    shadows: [
                      Shadow(
                          blurRadius: 6,
                          color: Colors.black,
                          offset: Offset(0, 1)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Barre de reprise gradient + glow
              if (widget.progressPct > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Stack(
                    children: [
                      Container(
                        height: 3.5,
                        color: Colors.white.withOpacity(0.12),
                      ),
                      FractionallySizedBox(
                        widthFactor: widget.progressPct,
                        child: Container(
                          height: 3.5,
                          decoration: BoxDecoration(
                            gradient: AppTheme.gradientHorizontal,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.violet.withOpacity(0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    if (!isTouch) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: card,
      );
    }

    return FocusableInk(
      onTap: widget.onTap,
      onLongPress: widget.onDelete,
      borderRadius: 14,
      focusColor: AppTheme.violet,
      child: card,
    );
  }

  Widget _fallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surfaceHigh,
              AppTheme.surface,
            ],
          ),
        ),
        child: Icon(
          widget.tabIndex == 1
              ? Icons.live_tv_rounded
              : widget.tabIndex == 2
                  ? Icons.movie_rounded
                  : Icons.tv_rounded,
          color: AppTheme.violet.withOpacity(0.15),
          size: 28,
        ),
      );
}

// ── Badge type ─────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final int tabIndex;
  const _TypeBadge(this.tabIndex);

  @override
  Widget build(BuildContext context) {
    final (label, color1, color2) = switch (tabIndex) {
      1 => ('LIVE', AppTheme.red, const Color(0xFFFF6B6B)),
      2 => ('FILM', AppTheme.violet, const Color(0xFF9B7BFF)),
      _ => ('SÉRIE', AppTheme.catSeriesAccent, const Color(0xFF36D8B7)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1.withOpacity(0.9), color2.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: color1.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}