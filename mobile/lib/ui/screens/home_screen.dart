// lib/ui/screens/home_screen.dart
// ARICH Player — Home Screen v18
// [FIX-CRASH] Suppression double appel loadTabContent(index) en mode portrait
//   (CategoryGridScreen le fait lui-même → plus de conflit sur _isLoadingTab)
// ─────────────────────────────────────────────────────────────────────────────
// v16d — Correctifs :
//   • [BUG-FILMS-HOME] Films/Séries n'apparaissaient pas sur l'accueil :
//     Le Selector (isLoading, errorMessage) ne se retriggait plus après
//     isLoading=false → _cachedMovies restait vide même quand allMovies était
//     peuplé. Fix : Selector élargi à (isLoading, errorMessage, allMovies.length,
//     allSeries.length) + _tryPopulateCaches() appelé dans le builder.
//   • [BUG-LAND-TABS] Onglets Direct/Films/Séries muets en paysage :
//     _buildLandscape ignorait _activeTab → affichait toujours le layout home.
//     Fix : si _activeTab > 0, afficher CategoryGridScreen embedded avec la
//     bottom nav en haut (même pattern que TV sidebar).
// ─────────────────────────────────────────────────────────────────────────────
// v16c — [BUG-OVERFLOW] Boutons Hero : Row → Wrap + ConstrainedBox(maxWidth:360)
// v16c — [BUG-TABS portrait] setState+push simultanés → push seul suffit
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/playlist_provider.dart';
import '../widgets/channel_card.dart';
import '../widgets/focusable_ink.dart';
import 'player_screen.dart';
import 'details_screen.dart';
import 'settings_screen.dart';
import 'category_grid_screen.dart';
import 'epg_screen.dart';
import 'favorites_screen.dart';
import 'login_screen.dart';
import '../../models/channel.dart';
import '../../core/tv_navigation.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import 'profile_screen.dart';
import '../../providers/mini_player_provider.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/portrait_bottom_nav.dart';
import 'stats_screen.dart';
import 'downloads_screen.dart';
import '../../services/download_service.dart';

const _kHideLive   = 'pref_hide_live';
const _kHideMovies = 'pref_hide_movies';
const _kHideSeries = 'pref_hide_series';

const _kHeroH     = 500.0;
const _kHeroHLand = 240.0;
const _kHeroHTV   = 340.0;
const _kNavH      = 64.0; // [FIX-OVERFLOW] était 56 → débordait de 1px sur portrait

// ─────────────────────────────────────────────────────────────────────────────
// Contrôleur Hero isolé — evite que le timer rebuilde tout le Scaffold
// ─────────────────────────────────────────────────────────────────────────────
class _HeroController extends ChangeNotifier {
  int    index     = 0;
  Timer? _timer;
  bool   get isRunning => _timer?.isActive ?? false;

  void start(int total) {
    _timer?.cancel();
    index = 0; // [FIX] Toujours reset pour éviter un index périmé si total change
    if (total <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      index = (index + 1) % total;
      notifyListeners();
    });
  }

  void reset(int total) {
    _timer?.cancel();
    index = 0;
    start(total);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  int  _activeTab   = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, ScrollController> _rowScrolls = {};

  bool _hideLive = false, _hideMovies = false, _hideSeries = false;

  final ScrollController _mainScroll = ScrollController();
  // [PERF] ValueNotifier au lieu de setState → seuls les widgets abonnés
  // via ValueListenableBuilder rebuilent sur scroll. Plus de rebuild Scaffold.
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier(0.0);
  static const _kScrollThreshold = 8.0;

  // Hero isolé
  final _HeroController _heroCtrl = _HeroController();

  // isTouch + isTizen calculés une fois dans initState
  bool _isTouch  = true;
  bool _isTizen  = false;

  // _tabsData mémoïsé
  List<({IconData icon, String label, int index})>? _cachedTabs;

  // Sport
  List<_SportMatch> _todayMatches = [];
  bool   _matchesLoading = true;
  String _matchesError   = '';

  static const _topLeagues = {
    'UEFA Champions League','UEFA Europa League','UEFA Europa Conference League',
    'English Premier League','Spanish La Liga','French Ligue 1','French Ligue 2',
    'German Bundesliga','Italian Serie A','Portuguese Primeira Liga',
    'Dutch Eredivisie','Scottish Premiership','Belgian First Division A',
    'FA Cup','Coupe de France','Copa del Rey','DFB-Pokal','Coppa Italia',
    'FIFA World Cup','UEFA European Championship','Africa Cup of Nations',
    'Copa America','UEFA Nations League','UEFA Super Cup','FIFA Club World Cup',
  };

  ScrollController _rowCtrl(String k) =>
      _rowScrolls.putIfAbsent(k, () => ScrollController());

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadHidePrefs();
    _mainScroll.addListener(_onScroll);
    // isTouch + isTizen calculés une fois — jamais dans itemBuilder
    _isTouch = Platform.isAndroid || Platform.isIOS;
    _isTizen = Platform.operatingSystem == 'tizen';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<IptvProvider>();

      context.read<PlaylistProvider>().addListener(_onPlaylistsChanged);
      _loadTodayMatches();

      // [FIX-LOAD] Attendre que _loadSavedCredentials() soit terminé avant de
      // déclencher loadTabContent. Sans ça, deux chargements réseau tournent en
      // parallèle sur la même source → contention → UI figée.
      // On poll isInitializing avec un délai minimal (16ms = 1 frame).
      if (p.isInitializing) {
        await Future.doWhile(() async {
          await Future.delayed(const Duration(milliseconds: 16));
          return mounted && context.read<IptvProvider>().isInitializing;
        });
      }
      if (!mounted) return;

      // Relit le provider après l'attente
      final pReady = context.read<IptvProvider>();
      if (!pReady.isAuthenticated) return; // pas de session IPTV valide

      if (pReady.allLive.isEmpty) {
        pReady.loadTabContent(1); // sans await — le Consumer rebuild quand ça arrive
      }
      if (pReady.allMovies.isEmpty || pReady.allSeries.isEmpty) {
        pReady.prefetchMoviesAndSeries();
      }
    });
  }

  // Throttle : ne rebuilde que si le déplacement dépasse _kScrollThreshold
  void _onScroll() {
    final off = _mainScroll.hasClients ? _mainScroll.offset : 0.0;
    if ((off - _scrollOffsetNotifier.value).abs() >= _kScrollThreshold) {
      _scrollOffsetNotifier.value = off;
    }
  }

  void _loadHidePrefs() {
    final b = Hive.box('settings');
    _hideLive   = b.get(_kHideLive,   defaultValue: false) as bool;
    _hideMovies = b.get(_kHideMovies, defaultValue: false) as bool;
    _hideSeries = b.get(_kHideSeries, defaultValue: false) as bool;
    _cachedTabs = null; // invalider le cache
  }

  void _onPlaylistsChanged() {
    if (!mounted) return;
    if (!context.read<PlaylistProvider>().hasAccounts) {
      // [BUG2] Capturer navigator et provider AVANT l'await
      // → évite accès à BuildContext détaché après logout async
      final nav      = Navigator.of(context);
      final provider = context.read<IptvProvider>();
      provider.logout().then((_) {
        nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mainScroll.removeListener(_onScroll);
    _mainScroll.dispose();
    _scrollOffsetNotifier.dispose();
    _heroCtrl.dispose();
    for (final c in _rowScrolls.values) c.dispose();
    try { context.read<PlaylistProvider>().removeListener(_onPlaylistsChanged); } catch (_) {}
    super.dispose();
  }

  List<Channel> _heroCandidates(IptvProvider p) => [
    ...p.allMovies.take(5),
    ...p.allSeries.take(4),
  ];

  // ── Sport ──────────────────────────────────────────────────────────────────
  Future<void> _loadTodayMatches() async {
    try {
      final today = DateTime.now();
      final date  = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final r = await http.get(
        Uri.parse('https://www.thesportsdb.com/api/v1/json/3/eventsday.php?d=$date&s=Soccer'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (r.statusCode != 200) { if (mounted) setState(() => _matchesLoading = false); return; }
      final allRaw = (jsonDecode(r.body)['events'] as List?) ?? [];
      if (allRaw.isEmpty) { if (mounted) setState(() => _matchesLoading = false); return; }
      final filtered  = allRaw.where((m) => _topLeagues.contains(m['strLeague'] as String? ?? '')).toList();
      final effective = filtered.isNotEmpty ? filtered : allRaw;
      final seen    = <String>{};
      final deduped = effective.where((m) => seen.add(m['idEvent'] as String? ?? '')).toList();
      final matches = deduped.map((m) {
        final s  = (m['strStatus'] as String? ?? '').toLowerCase();
        String ns = 'SCHEDULED';
        if (['inprogress','live','1h','2h','ht'].contains(s)) ns = 'IN_PLAY';
        else if (['ft','aet','pen','finished','ap'].contains(s)) ns = 'FINISHED';
        String time = '';
        try {
          final dt = DateTime.parse('${m['dateEvent']}T${m['strTime']}').toLocal();
          time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        } catch (_) {}
        return _SportMatch(
          homeTeam: m['strHomeTeam'] as String? ?? '?',
          awayTeam: m['strAwayTeam'] as String? ?? '?',
          competition: m['strLeague'] as String? ?? '',
          time: time, status: ns,
          homeScore: int.tryParse((m['intHomeScore'] ?? '').toString()),
          awayScore: int.tryParse((m['intAwayScore'] ?? '').toString()),
        );
      }).toList();
      matches.sort((a, b) {
        int p(String s) => s == 'IN_PLAY' ? 0 : s == 'SCHEDULED' ? 1 : 2;
        final pc = p(a.status).compareTo(p(b.status));
        return pc != 0 ? pc : a.time.compareTo(b.time);
      });
      if (mounted) setState(() { _todayMatches = matches.take(15).toList(); _matchesLoading = false; });
    } catch (e) {
      debugPrint('[Sports] $e');
      if (mounted) setState(() { _matchesLoading = false; _matchesError = 'Matchs indisponibles'; });
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _closeSearch() {
    setState(() { _isSearching = false; _searchController.clear(); });
    context.read<IptvProvider>().searchGlobal('');
  }

  void _openProfile() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => _ProfileSheet(
        onProfile: () { Navigator.pop(ctx); Navigator.push(context, _fadeRoute(const ProfileScreen())); },
        onSettings: () {
          Navigator.pop(ctx);
          Navigator.push(context, _fadeRoute(const SettingsScreen()))
              .then((_) { if (mounted) setState(_loadHidePrefs); });
        },
      ),
    );
  }

  PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionsBuilder: (_, a, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child),
    ),
    transitionDuration: const Duration(milliseconds: 360),
  );

  // _tabsData mémoïsé — recalcul seulement si flags hide changent
  List<({IconData icon, String label, int index})> _tabsData() {
    if (_cachedTabs != null) return _cachedTabs!;
    final l = context.read<LanguageProvider>().l10n;
    _cachedTabs = [
      (icon: Icons.home_rounded,    label: context.read<LanguageProvider>().l10n.t('nav_home'),   index: 0),
      if (!_hideLive)   (icon: Icons.live_tv_rounded,   label: context.read<LanguageProvider>().l10n.t('nav_live'),   index: 1),
      if (!_hideMovies) (icon: Icons.movie_rounded,      label: context.read<LanguageProvider>().l10n.t('nav_movies'), index: 2),
      if (!_hideSeries) (icon: Icons.tv_rounded,         label: context.read<LanguageProvider>().l10n.t('nav_series'), index: 3),
      (icon: Icons.favorite_rounded, label: context.read<LanguageProvider>().l10n.t('nav_favorites'), index: 98),
      if (!_hideLive) (icon: Icons.calendar_view_week_rounded, label: context.read<LanguageProvider>().l10n.t('nav_tv_guide'), index: 99),
    ];
    return _cachedTabs!;
  }

  void _onTabTap(int index) {
    if (index == 98) { Navigator.push(context, _fadeRoute(const FavoritesScreen())); return; }
    if (index == 99) { Navigator.push(context, _fadeRoute(EpgScreen())); return; }
    final isTV   = context.isTV;
    final isLand = MediaQuery.of(context).orientation == Orientation.landscape;
    if (index == 0) { setState(() => _activeTab = 0); return; }

    // Mode TV / paysage : affichage inline via setState (pas de push)
    if (isTV || isLand) {
      setState(() => _activeTab = index);
      context.read<IptvProvider>().loadTabContent(index);
      return;
    }

    // [BUG3 FIX] Mode portrait : push vers CategoryGridScreen en plein écran.
    // On NE fait PAS setState(_activeTab = index) avant le push — sinon
    // _buildPortrait affiche CategoryGridScreen inline ET le push l'ouvre
    // en parallèle, provoquant un double affichage + conflit de navigation.
    final l      = context.read<LanguageProvider>().l10n;
    final titles = {1: context.read<LanguageProvider>().l10n.t('nav_live'), 2: context.read<LanguageProvider>().l10n.t('nav_movies'), 3: context.read<LanguageProvider>().l10n.t('nav_series')};
    final icons  = {1: Icons.live_tv_rounded, 2: Icons.movie_rounded, 3: Icons.tv_rounded};
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => CategoryGridScreen(
          tabIndex: index, title: titles[index]!, icon: icons[index]!),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child),
      ),
      transitionDuration: const Duration(milliseconds: 300),
    ));
    // Pas de .then() — _activeTab n'a pas changé, rien à remettre à 0.
  }

  void _onCardTap(Channel item, IptvProvider provider, int tabIndex) {
    if (tabIndex == 1) {
      provider.setCurrentTab(1);
      // [FIX] Passer liveChannels + channelIndex pour activer les flèches ◀▶
      final channels = provider.filteredContent.isNotEmpty
          ? provider.filteredContent
          : provider.allLive;
      final idx = channels.indexWhere((c) => c.streamId == item.streamId);
      Navigator.push(context, _fadeRoute(PlayerScreen(
        streamUrl: provider.getStreamUrl(item), title: item.name,
        streamIcon: item.streamIcon, streamId: item.streamId, tabIndex: 1,
        liveChannels: channels,
        channelIndex: idx >= 0 ? idx : 0)));
    } else {
      Navigator.push(context, _fadeRoute(DetailsScreen(item: item, sourceTabIndex: tabIndex)));
    }
  }

  void _expandMiniPlayer() {
    final mini = context.read<MiniPlayerProvider>();
    if (!mini.hasActiveStream) return;
    mini.hideMiniPlayer();
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => PlayerScreen(
        streamUrl: mini.streamUrl, title: mini.title,
        streamIcon: mini.streamIcon, tabIndex: mini.tabIndex, streamId: mini.streamId),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(
      builder: (context, provider, __) {
        // Le hero démarre dès que les données arrivent — via postFrameCallback
        // pour éviter setState/notifyListeners en plein build
        final cands = _heroCandidates(provider);
        if (cands.isNotEmpty && !_heroCtrl.isRunning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _heroCtrl.start(cands.length);
          });
        }

        final isTV   = context.isTV;
        final isLand = MediaQuery.of(context).orientation == Orientation.landscape;

        return TvBackHandler(
          onBack: () {
            if (_isSearching) setState(() { _isSearching = false; _searchController.clear(); });
          },
          child: Scaffold(
            backgroundColor: AppTheme.background,
            extendBodyBehindAppBar: true,
            body: isTV
                ? _buildTVLayout(context, provider)
                : isLand
                    ? _buildLandscape(context, provider)
                    : _buildPortrait(context, provider),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [A] PORTRAIT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPortrait(BuildContext context, IptvProvider provider) {
    // [FIX-v13] Si les données ne sont pas encore là et qu'aucun prefetch
    // n'est en cours, le relancer (cas : retour sur l'accueil après navigation).
    if (provider.isAuthenticated &&
        !provider.isPrefetchingContent &&
        (provider.allMovies.isEmpty || provider.allSeries.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<IptvProvider>().prefetchMoviesAndSeries();
      });
    }

    if (_isSearching) {
      return Column(children: [
        _buildNavbar(provider, solid: true),
        Expanded(child: _buildSearchResults(provider)),
      ]);
    }
    if (_activeTab > 0) {
      final l      = context.read<LanguageProvider>().l10n;
      final titles = {1: context.read<LanguageProvider>().l10n.t('nav_live'), 2: context.read<LanguageProvider>().l10n.t('nav_movies'), 3: context.read<LanguageProvider>().l10n.t('nav_series')};
      final icons  = {1: Icons.live_tv_rounded, 2: Icons.movie_rounded, 3: Icons.tv_rounded};
      return Stack(children: [
        CategoryGridScreen(key: ValueKey('embed_$_activeTab'),
            tabIndex: _activeTab, title: titles[_activeTab]!, icon: icons[_activeTab]!, embedded: true),
        _buildNavbar(provider, solid: true),
      ]);
    }
    if (provider.errorMessage.isNotEmpty && provider.allMovies.isEmpty && provider.allSeries.isEmpty) {
      return _buildError(provider);
    }

    return Stack(children: [
      CustomScrollView(
        controller: _mainScroll,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHero(provider, _kHeroH)),
          if (!_hideLive)
            SliverToBoxAdapter(child: _buildTonightRow(provider)),
          SliverToBoxAdapter(child: _buildContinueWatching(provider)),
          if (!_hideMovies && _rowHasContent(provider.allMovies, provider))
            SliverToBoxAdapter(child: _buildRow(
              title: context.read<LanguageProvider>().l10n.t('home_movies'), accentColor: AppTheme.violet,
              items: provider.allMovies.take(30).toList(),
              provider: provider, tabIndex: 2, rowKey: 'movies',
            )),
          if (!_hideSeries && _rowHasContent(provider.allSeries, provider))
            SliverToBoxAdapter(child: _buildRow(
              title: context.read<LanguageProvider>().l10n.t('home_series'), accentColor: AppTheme.secondary,
              items: provider.allSeries.take(30).toList(),
              provider: provider, tabIndex: 3, rowKey: 'series',
            )),
          if (!_hideMovies && !_hideSeries &&
              provider.allMovies.isEmpty && provider.allSeries.isEmpty &&
              !provider.isPrefetchingContent && !provider.isLoading)
            SliverToBoxAdapter(child: _buildNoVodHint()),
          if (!_hideLive)
            SliverToBoxAdapter(child: _buildSportSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      // Navbar : wrapper dédié qui écoute le scroll lui-même
      _NavbarScrollWrapper(
        scrollController: _mainScroll,
        heroH: _kHeroH,
        builder: (solid) => _buildNavbar(provider, solid: solid),
      ),
      // MiniPlayer
      Positioned(left: 0, right: 0, bottom: 58,
          child: MiniPlayerBar(onExpand: _expandMiniPlayer)),
      Positioned(left: 0, right: 0, bottom: 0,
        child: PortraitBottomNav(
          activeTab: _activeTab,
          hideLive: _hideLive,
          hideMovies: _hideMovies,
          hideSeries: _hideSeries,
          onTabTap: _onTabTap,
          onSettingsClosed: () { if (mounted) setState(_loadHidePrefs); },
        )),
      // [FIX-v13] Barre chargement : isLoading OU prefetch films/séries en cours
      if (provider.isLoading || provider.isPrefetchingContent)
        const Positioned(top: 0, left: 0, right: 0,
          child: LinearProgressIndicator(minHeight: 2,
              color: AppTheme.violet, backgroundColor: Colors.transparent)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [B] NAVBAR
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildNavbar(IptvProvider provider, {bool solid = false}) {
    final isTizen = _isTizen;

    Widget inner = Container(
      decoration: BoxDecoration(
        color: solid
            ? Colors.black.withOpacity(isTizen ? 0.97 : 0.70)
            : Colors.transparent,
        border: solid
            ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5))
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _kNavH,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSearching ? _buildSearchBar(provider) : _buildNavRow(provider),
          ),
        ),
      ),
    );

    if (!isTizen && solid) {
      inner = ClipRect(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: inner));
    }
    return inner;
  }

  Widget _buildNavRow(IptvProvider provider) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait && !context.isTV;
    return Row(key: const ValueKey('nav'), children: [
      Padding(padding: const EdgeInsets.only(left: 12, right: 4),
        child: Image.asset('assets/logo.png', height: 28, fit: BoxFit.contain)),
      if (!isPortrait) ...[
        Flexible(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min,
            children: _tabsData().map((t) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: FocusableNavTab(label: t.label, icon: t.icon, isActive: _activeTab == t.index,
                autofocus: context.isTV && t.index == 0, onTap: () => _onTabTap(t.index)),
            )).toList()),
        )),
      ] else
        const Spacer(),
      // Boutons droits
      Row(mainAxisSize: MainAxisSize.min, children: [
        _NavBtn(icon: Icons.search_rounded, onTap: () => setState(() => _isSearching = true)),
        _DownloadNavBtn(onTap: () => Navigator.push(context, _fadeRoute(const DownloadsScreen()))),
        _NavBtn(icon: Icons.bar_chart_rounded,
            onTap: () => Navigator.push(context, _fadeRoute(const StatsScreen()))),
        Padding(padding: const EdgeInsets.only(right: 12, left: 2),
          child: GestureDetector(onTap: _openProfile,
              child: _AvatarBubble(
                username: provider.username.isNotEmpty
                    ? provider.username
                    : (Supabase.instance.client.auth.currentUser?.email ?? ''),
                size: 30,
              ))),
      ]),
    ]);
  }

  Widget _buildSearchBar(IptvProvider provider) {
    return Row(key: const ValueKey('search'), children: [
      const SizedBox(width: 12),
      Expanded(child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: TextField(
          controller: _searchController, autofocus: true,
          style: TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: context.read<LanguageProvider>().l10n.t('search_hint'),
            hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: provider.searchGlobal,
        ),
      )),
      FocusableInk(onTap: _closeSearch, borderRadius: 8,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(context.read<LanguageProvider>().l10n.t('cancel'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)))),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [C] HERO — Prime Video style
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHero(IptvProvider provider, double height) {
    final cands      = _heroCandidates(provider);
    final hasContent = cands.isNotEmpty;

    // [FIX-RANGERROR] Restart le timer si le nombre de candidats a changé.
    // Sans ça, _heroCtrl.index peut dépasser cands.length - 1 si allMovies/allSeries
    // changent entre deux builds (ex: chargement playlist → index stale → clamp(-1) → crash).
    if (hasContent && _heroCtrl.isRunning == false ||
        hasContent && _heroCtrl.index >= cands.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heroCtrl.start(cands.length);
      });
    }

    return SizedBox(
      height: height,
      child: Stack(fit: StackFit.expand, children: [

        // Backdrop isolé — écoute _heroCtrl directement, pas setState global
        RepaintBoundary(
          child: _HeroBackdrop(
            cands: cands,
            heroCtrl: _heroCtrl,
            height: height,
          ),
        ),

        // Overlays cinématiques statiques — pas de rebuild
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.15),
              Colors.black.withOpacity(0.65),
              Colors.black.withOpacity(0.92),
              Colors.black,
            ],
            stops: const [0.28, 0.46, 0.66, 0.84, 1.0],
          ),
        ))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.50), Colors.transparent],
            stops: const [0.0, 0.28],
          ),
        ))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Colors.black.withOpacity(0.40), Colors.transparent],
            stops: const [0.0, 0.60],
          ),
        ))),

        // Métadonnées — ListenableBuilder isolé sur _heroCtrl
        if (hasContent)
          Positioned(left: 20, right: 20, bottom: 28,
            child: ListenableBuilder(
              listenable: _heroCtrl,
              builder: (_, __) {
                // [FIX-RANGERROR] cands peut être vide ou plus court entre deux rebuilds
                if (cands.isEmpty) return const SizedBox.shrink();
                final idx = _heroCtrl.index.clamp(0, cands.length - 1);
                final ch  = cands[idx];
                return _PrimeHeroMeta(
                  key: ValueKey('meta_${ch.streamId}'),
                  channel: ch,
                  tabIndex: provider.allMovies.contains(ch) ? 2 : 3,
                  provider: provider,
                  onPlay:  (c, t) => _onCardTap(c, provider, t),
                  onFav:   (c, t) {
                    provider.toggleFavorite(c, t);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(provider.isFavorite(c.streamId, t)
                          ? '${c.name} retiré des favoris'
                          : '${c.name} ajouté aux favoris'),
                      backgroundColor: AppTheme.surfaceHigh,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ));
                  },
                );
              },
            )),

        // Dots
        if (hasContent && cands.length > 1)
          Positioned(bottom: 14, left: 0, right: 0,
            child: ListenableBuilder(
              listenable: _heroCtrl,
              builder: (_, __) {
                if (cands.isEmpty) return const SizedBox.shrink();
                return _HeroDots(
                  count: cands.length,
                  activeIndex: _heroCtrl.index.clamp(0, cands.length - 1),
                );
              },
            )),
      ]),
    );
  }

  Widget _heroFallback(double height) => Container(
    height: height,
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0A0818), Color(0xFF1A0A2E), Color(0xFF07070F)],
    )),
    child: Center(child: ShaderMask(
      shaderCallback: (b) => AppTheme.gradientPrimary.createShader(Rect.fromLTWH(0,0,b.width,b.height)),
      child: const Icon(Icons.play_circle_fill_rounded, size: 80, color: Colors.white),
    )),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // [CW] CONTINUER À REGARDER
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildContinueWatching(IptvProvider provider) {
    // Filtrer uniquement films/séries avec position > 5% et < 95%
    final items = provider.watchHistory.where((e) {
      if (e.tabIndex == 1) return false; // pas les lives
      if (e.totalDurationSeconds <= 0) return false;
      final ratio = e.positionSeconds / e.totalDurationSeconds;
      return ratio > 0.05 && ratio < 0.95;
    }).take(10).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    final sizes = context.tvSizes;
    final isTV  = context.isTV;
    const cardW = 160.0;
    const cardH = 96.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sizes.bodyPadding, 28, sizes.bodyPadding, 14),
          child: Row(children: [
            Container(
              width: 3, height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [AppTheme.red, Color(0xFF7B2FFF)],
                ),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.55), blurRadius: 6)],
              ),
            ),
            Flexible(child: Text(
              context.read<LanguageProvider>().l10n.t('home_continue_watching'),
              style: const TextStyle(color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.w700, letterSpacing: -0.3),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
        ),
        SizedBox(
          height: cardH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            controller: _rowCtrl('continue'),
            padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
            addRepaintBoundaries: true,
            itemExtent: cardW + sizes.cardSpacing,
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final entry = items[i];
              final ratio = (entry.positionSeconds / entry.totalDurationSeconds).clamp(0.0, 1.0);
              // Trouver le Channel correspondant
              final allContent = entry.tabIndex == 2 ? provider.allMovies : provider.allSeries;
              final channel = allContent.cast<dynamic>().firstWhere(
                (c) => c.streamId == entry.streamId, orElse: () => null,
              );

              return Padding(
                padding: EdgeInsets.only(right: sizes.cardSpacing),
                child: FocusableInk(
                  onTap: () {
                    if (channel == null) return;
                    if (entry.tabIndex == 2) {
                      Navigator.push(context, _fadeRoute(DetailsScreen(item: channel, sourceTabIndex: 2)));
                    } else {
                      Navigator.push(context, _fadeRoute(DetailsScreen(item: channel, sourceTabIndex: 3)));
                    }
                  },
                  borderRadius: 10,
                  focusColor: AppTheme.red,
                  child: SizedBox(
                    width: cardW,
                    child: Stack(children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: entry.streamIcon.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: entry.streamIcon,
                                width: cardW, height: cardH,
                                fit: BoxFit.cover,
                                memCacheWidth: (cardW * 2).toInt(),
                                errorWidget: (_, __, ___) => _cwFallback(entry.tabIndex, cardW, cardH),
                              )
                            : _cwFallback(entry.tabIndex, cardW, cardH),
                      ),
                      // Gradient overlay
                      Positioned.fill(child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: DecoratedBox(decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                            stops: const [0.35, 1.0],
                          ),
                        )),
                      )),
                      // Titre
                      Positioned(bottom: 22, left: 8, right: 8,
                        child: Text(entry.title,
                          style: const TextStyle(color: Colors.white, fontSize: 10,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      // Barre de progression
                      Positioned(bottom: 0, left: 0, right: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(10),
                              bottomRight: Radius.circular(10)),
                          child: Stack(children: [
                            Container(height: 3, color: Colors.white.withOpacity(0.15)),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                      colors: [AppTheme.violet, AppTheme.red]),
                                  boxShadow: [BoxShadow(
                                      color: AppTheme.violet.withOpacity(0.6),
                                      blurRadius: 4)],
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      // Icône play
                      Positioned(bottom: 18, right: 8,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.5)),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ]),
                  ),
                ).animate().fadeIn(
                    delay: Duration(milliseconds: i.clamp(0, 6) * 40),
                    duration: 280.ms),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _cwFallback(int tabIndex, double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(child: Icon(
      tabIndex == 2 ? Icons.movie_rounded : Icons.tv_rounded,
      color: Colors.white.withOpacity(0.15), size: 28,
    )),
  );

  bool _rowHasContent(List<Channel> items, IptvProvider provider) =>
      items.isNotEmpty || provider.isPrefetchingContent || provider.isLoading;

  Widget _buildNoVodHint() {
    final sizes = context.tvSizes;
    return Padding(
      padding: EdgeInsets.fromLTRB(sizes.bodyPadding, 8, sizes.bodyPadding, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(children: [
          Icon(Icons.movie_filter_outlined, color: AppTheme.violet.withOpacity(0.7), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(
            context.read<LanguageProvider>().l10n.t('home_no_vod'),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35),
          )),
        ]),
      ),
    );
  }

  Widget _buildTonightRow(IptvProvider provider) {
    final items = provider.allLive.take(16).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final sizes = context.tvSizes;
    const cardW = 148.0;
    const cardH = 88.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sizes.bodyPadding, 20, sizes.bodyPadding, 12),
          child: Row(children: [
            Container(
              width: 3, height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.red, AppTheme.violet],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              context.read<LanguageProvider>().l10n.t('home_tonight'),
              style: const TextStyle(
                color: Colors.white, fontSize: 17,
                fontWeight: FontWeight.w700, letterSpacing: -0.3,
              ),
            ),
          ]),
        ),
        SizedBox(
          height: cardH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            controller: _rowCtrl('tonight'),
            padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
            itemExtent: cardW + sizes.cardSpacing,
            itemCount: items.length,
            itemBuilder: (_, i) {
              final ch = items[i];
              return Padding(
                padding: EdgeInsets.only(right: sizes.cardSpacing),
                child: FocusableInk(
                  onTap: () => _onCardTap(ch, provider, 1),
                  borderRadius: 12,
                  focusColor: AppTheme.red,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(fit: StackFit.expand, children: [
                      if (ch.streamIcon.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ch.streamIcon,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.high,
                          memCacheWidth: 440,
                          memCacheHeight: 260,
                          errorWidget: (_, __, ___) => _liveThumbFallback(),
                        )
                      else
                        _liveThumbFallback(),
                      DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                        ),
                      )),
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LIVE',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Positioned(
                        left: 8, right: 8, bottom: 8,
                        child: Text(ch.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                          )),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _liveThumbFallback() => Container(
    color: const Color(0xFF14141F),
    child: const Center(
      child: Icon(Icons.live_tv_rounded, color: Colors.white24, size: 28),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // [D] ROW POSTERS — Prime Video style
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildRow({
    required String title,
    required Color accentColor,
    required List<Channel> items,
    required IptvProvider provider,
    required int tabIndex,
    required String rowKey,
  }) {
    final sizes  = context.tvSizes;
    final isTV   = sizes.isTV;
    final isLand = MediaQuery.of(context).orientation == Orientation.landscape;

    // [v18] Cards légèrement plus grandes en mobile — plus facile à tapper
    final cardW = isLand ? 90.0  : isTV ? 136.0 : 116.0;
    final cardH = isLand ? 134.0 : isTV ? 200.0 : 172.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header design system — accent bar 3px + glow + titre
        Padding(
          padding: EdgeInsets.fromLTRB(sizes.bodyPadding, 28, sizes.bodyPadding, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Accent bar gauche 3px
            Container(
              width: 3, height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [accentColor, accentColor.withOpacity(0.4)],
                ),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [BoxShadow(color: accentColor.withOpacity(0.55), blurRadius: 6)],
              ),
            ),
            Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 17,
                fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const Spacer(),
            GestureDetector(
              onTap: () => _onTabTap(tabIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withOpacity(0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.read<LanguageProvider>().l10n.t('see_all'), style: TextStyle(
                      color: accentColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded, color: accentColor, size: 13),
                ]),
              ),
            ),
          ]),
        ),
        // Posters avec fade edges
        SizedBox(
          height: cardH,
          child: items.isEmpty
              ? _skeletonRow(cardW, cardH, sizes)
              : ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.04, 0.92, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    controller: _rowCtrl(rowKey),
                    padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
                    addRepaintBoundaries: true,
                    // [PERF-ANR] itemExtent fixe → Flutter skip le layout calc à chaque item
                    itemExtent: cardW + sizes.cardSpacing,
                    cacheExtent: cardW * 3,
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      Widget card = _PosterCard(
                        channel: item, width: cardW, height: cardH,
                        tabIndex: tabIndex, accentColor: accentColor,
                        isFavorite: provider.isFavorite(item.streamId, tabIndex),
                        isTouch: _isTouch,
                        onTap: () => _onCardTap(item, provider, tabIndex),
                        onFav: () => provider.toggleFavorite(item, tabIndex),
                      );
                      return Padding(
                        padding: EdgeInsets.only(right: sizes.cardSpacing),
                        child: Focus(
                          skipTraversal: true,
                          onFocusChange: (focused) {
                            if (focused && isTV) {
                              final ctrl = _rowCtrl(rowKey);
                              if (ctrl.hasClients) {
                                final off = (i.toDouble() * (cardW + sizes.cardSpacing)) - sizes.bodyPadding;
                                ctrl.animateTo(off.clamp(0.0, ctrl.position.maxScrollExtent),
                                    duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
                              }
                            }
                          },
                          child: card.animate().fadeIn(
                            delay: Duration(milliseconds: i.clamp(0, 8) * 45), duration: 300.ms),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _skeletonRow(double w, double h, TVSizes sizes) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: EdgeInsets.only(right: sizes.cardSpacing),
        child: RepaintBoundary(
          child: _SkeletonBox(width: w, height: h, borderRadius: 10, staggerIndex: i),
        )),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [E] SPORT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSportSection() {
    final sizes     = context.tvSizes;
    final liveCount = _todayMatches.where((m) => m.status == 'IN_PLAY').length;

    if (_matchesError.isNotEmpty || (!_matchesLoading && _todayMatches.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sizes.bodyPadding, 24, sizes.bodyPadding, 12),
          child: Row(children: [
            Flexible(child: Text(context.read<LanguageProvider>().l10n.t('nav_sport'), style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3), overflow: TextOverflow.ellipsis)),
            if (liveCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const RepaintBoundary(child: _LiveBadge()),
                  const SizedBox(width: 5),
                  Text('$liveCount en direct',
                      style: const TextStyle(color: AppTheme.red, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ]),
        ),
        SizedBox(
          height: 112,
          child: _matchesLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
                  itemCount: 4,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(right: sizes.cardSpacing),
                    child: RepaintBoundary(
                      child: _SkeletonBox(width: 196, height: 112, borderRadius: 12, staggerIndex: i),
                    )))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  controller: _rowCtrl('sport'),
                  padding: EdgeInsets.symmetric(horizontal: sizes.bodyPadding),
                  addRepaintBoundaries: true,
                  itemCount: _todayMatches.length,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(right: sizes.cardSpacing),
                    child: _SportCard(match: _todayMatches[i], index: i))),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [F] SEARCH
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSearchResults(IptvProvider provider) {
    final query = provider.currentSearchQuery;
    if (query.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.05), size: 64),
        SizedBox(height: 12),
        Text(context.read<LanguageProvider>().l10n.t('search_hint'),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      ]));
    }
    final results = provider.globalSearchResults;
    if (results.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded, color: Colors.white.withOpacity(0.05), size: 64),
        SizedBox(height: 12),
        Text('${context.read<LanguageProvider>().l10n.t('home_no_results_for')} "$query"',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      ]).animate().fadeIn());
    }
    final l      = context.read<LanguageProvider>().l10n;
    final live   = results.where((r) => r.tabIndex == 1).toList();
    final movies = results.where((r) => r.tabIndex == 2).toList();
    final series = results.where((r) => r.tabIndex == 3).toList();
    final sizes  = context.tvSizes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('${results.length} résultat${results.length > 1 ? 's' : ''}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
        if (live.isNotEmpty)   _searchGroup(context.read<LanguageProvider>().l10n.t('nav_live'),   live,   provider, 1, sizes),
        if (movies.isNotEmpty) _searchGroup(context.read<LanguageProvider>().l10n.t('nav_movies'), movies, provider, 2, sizes),
        if (series.isNotEmpty) _searchGroup(context.read<LanguageProvider>().l10n.t('nav_series'), series, provider, 3, sizes),
      ],
    );
  }

  Widget _searchGroup(String title, List<SearchResult> results, IptvProvider provider, int tab, TVSizes sizes) {
    final isLive = tab == 1;
    final query  = provider.currentSearchQuery.toLowerCase();
    final accent = tab == 1 ? AppTheme.red : tab == 2 ? AppTheme.violet : AppTheme.secondary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
        child: Row(children: [
          Container(width: 3, height: 14, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(8)),
            child: Text('\${results.length}', style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w600))),
        ])),
      SizedBox(
        height: isLive ? sizes.cardHeightLive : 154,
        child: ListView.builder(
          scrollDirection: Axis.horizontal, itemCount: results.length,
          itemBuilder: (ctx, i) {
            final ch = results[i].channel;
            return Padding(
              padding: EdgeInsets.only(right: sizes.cardSpacing),
              child: Stack(children: [
                SizedBox(width: isLive ? sizes.cardWidthLandscape : 104,
                  child: ChannelCard(channel: ch, isWide: isLive, tabIndex: tab,
                    isFavorite: provider.isFavorite(ch.streamId, tab),
                    onFavoriteTap: () => provider.toggleFavorite(ch, tab),
                    onTap: () => _onCardTap(ch, provider, tab))),
                if (query.isNotEmpty && ch.name.toLowerCase().startsWith(query))
                  Positioned(top: 5, left: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                    child: Text(context.read<LanguageProvider>().l10n.t('sport_top_badge'), style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w800)))),
              ]),
            ).animate().fadeIn(delay: Duration(milliseconds: i.clamp(0,6)*35), duration: 240.ms);
          },
        )),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [G] ERROR
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildError(IptvProvider provider) {
    return Center(child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 68, height: 68,
          decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), shape: BoxShape.circle,
              border: Border.all(color: AppTheme.error.withOpacity(0.3))),
          child: const Icon(Icons.wifi_off_rounded, color: AppTheme.error, size: 30)),
        SizedBox(height: 18),
        Text(provider.errorMessage, style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center),
        SizedBox(height: 22),
        GradientButton(label: context.read<LanguageProvider>().l10n.t('retry'),
            height: 46, radius: 12, onTap: () => provider.loadTabContent(_activeTab)),
      ]).animate().fadeIn(duration: 380.ms).slideY(begin: 0.08, end: 0),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [H] LANDSCAPE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildLandscape(BuildContext context, IptvProvider provider) {
    if (_isSearching) {
      return Column(children: [
        _buildNavbar(provider, solid: true),
        Expanded(child: _buildSearchResults(provider)),
      ]);
    }

    // [BUG LANDSCAPE FIX] Quand un onglet Direct/Films/Séries est actif,
    // afficher CategoryGridScreen en plein écran (comme en portrait TV).
    // Avant ce fix, _buildLandscape ignorait _activeTab et affichait
    // toujours le layout home → les onglets semblaient ne rien faire.
    if (_activeTab > 0 && _activeTab < 10) {
      final l      = context.read<LanguageProvider>().l10n;
      final titles = {1: context.read<LanguageProvider>().l10n.t('nav_live'), 2: context.read<LanguageProvider>().l10n.t('nav_movies'), 3: context.read<LanguageProvider>().l10n.t('nav_series')};
      final icons  = {1: Icons.live_tv_rounded, 2: Icons.movie_rounded, 3: Icons.tv_rounded};
      return Column(children: [
        _LandscapeBottomNav(
          tabs: _tabsData(), activeTab: _activeTab, isSearching: false,
          username: provider.username,
          searchLabel: context.read<LanguageProvider>().l10n.t('nav_search'),
          onTabTap: _onTabTap,
          onSearchTap: () => setState(() => _isSearching = true),
          onProfileTap: _openProfile,
          onDownloadsTap: () => Navigator.push(context, _fadeRoute(const DownloadsScreen()))),
        Expanded(child: CategoryGridScreen(
          key: ValueKey('land_embed_$_activeTab'),
          tabIndex: _activeTab,
          title: titles[_activeTab]!,
          icon: icons[_activeTab]!,
          embedded: true,
        )),
      ]);
    }

    final tabs = _tabsData();
    final l    = context.read<LanguageProvider>().l10n;
    return Column(children: [
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 300, child: ListView(padding: EdgeInsets.zero, children: [
          _buildHero(provider, _kHeroHLand),
          if (!_hideLive) _buildSportSection(),
        ])),
        Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          if (!_hideMovies) _buildRow(title: context.read<LanguageProvider>().l10n.t('home_movies'), accentColor: AppTheme.violet,
            items: provider.allMovies.take(30).toList(),
            provider: provider, tabIndex: 2, rowKey: 'movies_l'),
          if (!_hideSeries) _buildRow(title: context.read<LanguageProvider>().l10n.t('home_series'), accentColor: AppTheme.secondary,
            items: provider.allSeries.take(30).toList(),
            provider: provider, tabIndex: 3, rowKey: 'series_l'),
        ])),
      ])),
      _LandscapeBottomNav(
        tabs: tabs, activeTab: _activeTab, isSearching: _isSearching,
        username: provider.username, searchLabel: context.read<LanguageProvider>().l10n.t('nav_search'),
        onTabTap: _onTabTap,
        onSearchTap: () => setState(() => _isSearching = true),
        onProfileTap: _openProfile,
        onDownloadsTap: () => Navigator.push(context, _fadeRoute(const DownloadsScreen()))),
      MiniPlayerBar(onExpand: _expandMiniPlayer),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // [I] TV LAYOUT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTVLayout(BuildContext context, IptvProvider provider) {
    final tabs = _tabsData();
    final sidebar = Container(
      width: 220,
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A18), Color(0xFF07070F)]),
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24, offset: const Offset(4,0))],
      ),
      child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
          child: Image.asset('assets/logo.png', height: 32, fit: BoxFit.contain, alignment: Alignment.centerLeft)
              .animate().fadeIn(duration: 600.ms).slideX(begin: -0.1, end: 0)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 1, color: Colors.white.withOpacity(0.04))),
        const SizedBox(height: 12),
        ...tabs.asMap().entries.map((e) => RepaintBoundary(
          child: _TVSidebarTab(icon: e.value.icon, label: e.value.label,
            active: _activeTab == e.value.index && !_isSearching,
            autofocus: e.value.index == 0, animDelay: e.key * 60,
            onTap: () => _onTabTap(e.value.index)))),
        _TVSidebarTab(icon: Icons.search_rounded,
          label: context.read<LanguageProvider>().l10n.t('nav_search'),
          active: _isSearching, animDelay: tabs.length * 60,
          onTap: () => setState(() => _isSearching = true)),
        const Spacer(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(height: 1, color: Colors.white.withOpacity(0.04))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
          child: FocusableInk(onTap: _openProfile, borderRadius: 14, focusColor: AppTheme.violet,
            child: Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF16162A), Color(0xFF101020)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08))),
              child: Row(children: [
                _AvatarBubble(username: provider.username, size: 38),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(provider.username.isNotEmpty ? provider.username
                      : context.read<LanguageProvider>().l10n.t('arich_account'),
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(context.read<LanguageProvider>().l10n.t('settings_title'),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                ])),
                const Icon(Icons.settings_rounded, color: AppTheme.textSecondary, size: 15),
              ]))).animate().fadeIn(delay: 400.ms)),
      ])),
    );
    return FocusTraversalGroup(policy: OrderedTraversalPolicy(),
      child: Row(children: [
        TvFocusZone(order: 1, child: sidebar),
        Expanded(child: TvFocusZone(order: 2,
          child: _isSearching ? _buildSearchResults(provider) : Stack(children: [
            ListView(padding: const EdgeInsets.only(bottom: 36), children: [
              _buildHero(provider, _kHeroHTV),
              _buildContinueWatching(provider),
              if (!_hideMovies) _buildRow(title: context.read<LanguageProvider>().l10n.t('home_movies'), accentColor: AppTheme.violet,
                items: provider.allMovies.take(30).toList(),
                provider: provider, tabIndex: 2, rowKey: 'movies_tv'),
              if (!_hideSeries) _buildRow(title: context.read<LanguageProvider>().l10n.t('home_series'), accentColor: AppTheme.secondary,
                items: provider.allSeries.take(30).toList(),
                provider: provider, tabIndex: 3, rowKey: 'series_tv'),
              _buildSportSection(),
            ]),
            if (provider.isLoading || provider.isPrefetchingContent)
              const Positioned(top: 10, right: 14,
                child: SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white24))),
          ]))),
      ]));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NAVBAR SCROLL WRAPPER — écoute le scroll indépendamment du Scaffold
// Évite que _buildNavbar rebuild à chaque setState du scroll principal
// ═════════════════════════════════════════════════════════════════════════════
class _NavbarScrollWrapper extends StatefulWidget {
  final ScrollController scrollController;
  final double heroH;
  final Widget Function(bool solid) builder;
  const _NavbarScrollWrapper({
    required this.scrollController,
    required this.heroH,
    required this.builder,
  });
  @override
  State<_NavbarScrollWrapper> createState() => _NavbarScrollWrapperState();
}

class _NavbarScrollWrapperState extends State<_NavbarScrollWrapper> {
  bool _solid = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final off    = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    final should = off > (widget.heroH - 160);
    if (should != _solid) setState(() => _solid = should);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_solid);
}

// ═════════════════════════════════════════════════════════════════════════════
// HERO BACKDROP — widget isolé qui écoute _HeroController
// Seul ce widget rebuilde lors du changement de slide, pas tout le Scaffold
// ═════════════════════════════════════════════════════════════════════════════
class _HeroBackdrop extends StatelessWidget {
  final List<Channel> cands;
  final _HeroController heroCtrl;
  final double height;
  const _HeroBackdrop({
    required this.cands,
    required this.heroCtrl,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: heroCtrl,
      builder: (_, __) {
        if (cands.isEmpty) return _fallback();
        final idx = heroCtrl.index.clamp(0, cands.length - 1);
        final url = cands[idx].streamIcon;
        if (url.isEmpty) return _fallback();
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: CachedNetworkImage(
            key: ValueKey('hbg_${cands[idx].streamId}'),
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            width: double.infinity,
            height: height,
            memCacheWidth: 1400,
            placeholder: (_, __) => Container(color: const Color(0xFF080812)),
            errorWidget: (_, __, ___) => _fallback(),
          ),
        );
      },
    );
  }

  Widget _fallback() => Container(
    height: height,
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF0A0818), Color(0xFF1A0A2E), Color(0xFF07070F)],
    )),
    child: Center(child: ShaderMask(
      shaderCallback: (b) => AppTheme.gradientPrimary.createShader(Rect.fromLTWH(0,0,b.width,b.height)),
      child: const Icon(Icons.play_circle_fill_rounded, size: 80, color: Colors.white),
    )),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PRIME HERO META — métadonnées style Amazon Prime Video
// ═════════════════════════════════════════════════════════════════════════════
class _PrimeHeroMeta extends StatelessWidget {
  final Channel channel;
  final int tabIndex;
  final IptvProvider provider;
  final void Function(Channel, int) onPlay;
  final void Function(Channel, int) onFav;

  const _PrimeHeroMeta({super.key, required this.channel, required this.tabIndex,
      required this.provider, required this.onPlay, required this.onFav});

  double get _fakeRating {
    final h = channel.name.hashCode.abs();
    return 3.0 + (h % 20) / 10.0;
  }

  int get _fakeYear {
    final h = channel.streamId.hashCode.abs();
    return 2019 + (h % 6);
  }

  List<String> get _fakeGenres {
    const pool = ['Action','Drame','Thriller','Comédie','Sci-Fi','Crime','Horreur','Romance','Aventure'];
    final h = channel.name.hashCode.abs();
    return [pool[h % pool.length], pool[(h + 3) % pool.length]];
  }

  @override
  Widget build(BuildContext context) {
    final isFav      = provider.isFavorite(channel.streamId, tabIndex);
    final typeLabel  = tabIndex == 2 ? 'FILM' : 'SÉRIE';
    final typeColor  = tabIndex == 2 ? AppTheme.violet : AppTheme.secondary;
    final isTizen    = Platform.operatingSystem == 'tizen';
    final rating     = _fakeRating;
    final year       = _fakeYear;
    final genres     = _fakeGenres;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
      children: [

        // Badge type pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.20),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: typeColor.withOpacity(0.40)),
          ),
          child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 9,
              fontWeight: FontWeight.w900, letterSpacing: 1.8)),
        ),
        const SizedBox(height: 10),

        // Titre
        Text(channel.name,
          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900,
            letterSpacing: -0.8, height: 1.05,
            shadows: [Shadow(blurRadius: 40, color: Colors.black), Shadow(blurRadius: 10, color: Colors.black)]),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06, end: 0),

        const SizedBox(height: 10),

        // Méta ligne
        Wrap(
          spacing: 8, runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
              final filled = i < rating.floor();
              final half   = !filled && i < rating;
              return Icon(
                half ? Icons.star_half_rounded : filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: AppTheme.gold, size: 13,
              );
            })),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Text('$year', style: const TextStyle(color: Colors.white70,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            ...genres.map((g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Text(g, style: const TextStyle(color: Colors.white60,
                  fontSize: 11, fontWeight: FontWeight.w500)),
            )),
          ],
        ).animate().fadeIn(delay: 80.ms, duration: 350.ms),

        const SizedBox(height: 8),

        // Badge inclus
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 13),
          SizedBox(width: 5),
          Text(context.read<LanguageProvider>().l10n.t('included_in_arich'), style: TextStyle(
              color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
        ]).animate().fadeIn(delay: 120.ms),

        const SizedBox(height: 16),

        // Boutons — ConstrainedBox + Wrap pour éviter overflow sur petits écrans
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Wrap(
            spacing: 10, runSpacing: 8,
            children: [
              GestureDetector(
                onTap: () => onPlay(channel, tabIndex),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A6AFF), Color(0xFF0050E6)]),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: const Color(0xFF1A6AFF).withOpacity(0.40), blurRadius: 16)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(context.read<LanguageProvider>().l10n.t('watch'), style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => onFav(channel, tabIndex),
                child: isTizen
                    ? _listButton(isFav)
                    : ClipRRect(borderRadius: BorderRadius.circular(6),
                        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: _listButton(isFav))),
              ),
              GestureDetector(
                onTap: () => onPlay(channel, tabIndex),
                child: isTizen
                    ? _infoButton()
                    : ClipOval(child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: _infoButton())),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 180.ms, duration: 350.ms),
      ],
    );
  }

  Widget _listButton(bool isFav) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    decoration: BoxDecoration(
      color: isFav ? Colors.white.withOpacity(0.22) : Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: isFav ? Colors.white.withOpacity(0.55) : Colors.white.withOpacity(0.22)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(isFav ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 17),
      const SizedBox(width: 6),
      Text(isFav ? 'Dans ma liste' : 'Ma liste',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _infoButton() => Container(
    width: 42, height: 42,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.12),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withOpacity(0.22)),
    ),
    child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// HERO DOTS — reçoit activeIndex directement, StatelessWidget
// ═════════════════════════════════════════════════════════════════════════════
class _HeroDots extends StatelessWidget {
  final int count;
  final int activeIndex;
  const _HeroDots({required this.count, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22.0 : 5.0, height: 4,
          decoration: BoxDecoration(
            gradient: active ? AppTheme.gradientHorizontal : null,
            color: active ? null : Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(2),
            boxShadow: active ? [BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 6)] : null),
        );
      }));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// POSTER CARD
// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
// POSTER CARD — v2 Prime Video style
// Gradient overlay du bas, titre en bas, badge qualité, glow au focus
// ═════════════════════════════════════════════════════════════════════════════
class _PosterCard extends StatefulWidget {
  final Channel channel;
  final double width, height;
  final int tabIndex;
  final Color accentColor;
  final bool isFavorite;
  final bool isTouch;
  final VoidCallback onTap, onFav;
  const _PosterCard({required this.channel, required this.width, required this.height,
      required this.tabIndex, required this.accentColor,
      required this.isFavorite, required this.isTouch,
      required this.onTap, required this.onFav});
  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.07)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    setState(() => _hovered = v);
    if (v) _scaleCtrl.forward(); else _scaleCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isTizen = Platform.operatingSystem == 'tizen';

    Widget card = GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: Container(
          width: widget.width, height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? widget.accentColor.withOpacity(0.45)
                    : Colors.black.withOpacity(0.55),
                blurRadius: _hovered ? 28 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [

              // ── Image ──
              widget.channel.streamIcon.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.channel.streamIcon,
                      fit: BoxFit.cover,
                      memCacheWidth: (widget.width * 2).toInt(),
                      memCacheHeight: (widget.height * 2).toInt(),
                      maxWidthDiskCache: (widget.width * 3).toInt(),
                      maxHeightDiskCache: (widget.height * 3).toInt(),
                      fadeInDuration: const Duration(milliseconds: 250),
                      errorWidget: (_, __, ___) => _fallback())
                  : _fallback(),

              // ── Gradient overlay prime-video style (plus profond) ──
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.82),
                  ],
                  stops: const [0.35, 0.62, 1.0],
                )))),

              // ── Hover overlay subtle ──
              if (_hovered)
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [
                      widget.accentColor.withOpacity(0.12),
                      Colors.transparent,
                    ])))),

              // ── Border focus glow ──
              Positioned.fill(child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered
                        ? widget.accentColor.withOpacity(0.6)
                        : Colors.white.withOpacity(0.07),
                    width: _hovered ? 2 : 1,
                  )),
              )),

              // ── Play button au hover ──
              if (_hovered)
                Center(child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.7), width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 26),
                )),

              // ── Titre bas ──
              Positioned(bottom: 0, left: 0, right: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(widget.channel.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.width > 100 ? 10.5 : 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black),
                        Shadow(blurRadius: 16, color: Colors.black),
                      ]),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                )),

              // ── Badge qualité top-left ──
              Positioned(top: 7, left: 7,
                child: _QualityBadge(channel: widget.channel, accentColor: widget.accentColor)),

              // ── Bouton favori top-right ──
              Positioned(top: 6, right: 6,
                child: GestureDetector(
                  onTap: widget.onFav,
                  child: isTizen
                      ? _FavBadge(isFav: widget.isFavorite, accent: widget.accentColor, withBlur: false)
                      : ClipOval(child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: _FavBadge(
                              isFav: widget.isFavorite,
                              accent: widget.accentColor,
                              withBlur: true))))),
            ]),
          ),
        ),
      ),
    );

    if (!widget.isTouch) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit:  (_) => _setHover(false),
        child: card);
    }
    return card;
  }

  Widget _fallback() => Container(
    color: AppTheme.surface,
    child: Center(child: Icon(
      widget.tabIndex == 2 ? Icons.movie_rounded : Icons.tv_rounded,
      color: Colors.white.withOpacity(0.10), size: 32)));
}

// ── Badge qualité ─────────────────────────────────────────────────────────────
class _QualityBadge extends StatelessWidget {
  final Channel channel;
  final Color accentColor;
  const _QualityBadge({required this.channel, required this.accentColor});

  String? _quality() {
    final name = channel.name.toUpperCase();
    if (name.contains('4K') || name.contains('UHD')) return '4K';
    if (name.contains('FHD') || name.contains('1080')) return 'FHD';
    if (name.contains(' HD') || name.endsWith('HD')) return 'HD';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final q = _quality();
    if (q == null) return const SizedBox.shrink();
    final color = q == '4K' ? AppTheme.gold
                : q == 'FHD' ? AppTheme.secondary
                : accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)],
      ),
      child: Text(q,
        style: const TextStyle(
          color: Colors.white, fontSize: 8,
          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

// ── Bouton favori ─────────────────────────────────────────────────────────────
class _FavBadge extends StatelessWidget {
  final bool isFav, withBlur;
  final Color accent;
  const _FavBadge({required this.isFav, required this.accent, required this.withBlur});
  @override
  Widget build(BuildContext context) => Container(
    width: 26, height: 26,
    decoration: BoxDecoration(
      color: isFav
          ? accent.withOpacity(withBlur ? 0.40 : 0.75)
          : Colors.black.withOpacity(withBlur ? 0.38 : 0.60),
      shape: BoxShape.circle,
      border: Border.all(
        color: isFav ? accent.withOpacity(0.65) : Colors.white.withOpacity(0.18))),
    child: Icon(
      isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      color: isFav ? Colors.white : Colors.white60, size: 13));
}

// ═════════════════════════════════════════════════════════════════════════════
// SPORT CARD
// ═════════════════════════════════════════════════════════════════════════════
class _SportCard extends StatelessWidget {
  final _SportMatch match;
  final int index;
  const _SportCard({required this.match, required this.index});

  @override
  Widget build(BuildContext context) {
    final isLive     = match.status == 'IN_PLAY';
    final isFinished = match.status == 'FINISHED';
    final hasScore   = match.homeScore != null && match.awayScore != null;
    final accent     = isLive ? AppTheme.red : AppTheme.catSportAccent;
    final isTizen    = Platform.operatingSystem == 'tizen';

    Widget inner = Container(
      width: 196,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: isLive
              ? [AppTheme.red.withOpacity(0.14), Colors.black.withOpacity(0.55)]
              : [Colors.white.withOpacity(0.07), Colors.black.withOpacity(0.50)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLive ? AppTheme.red.withOpacity(0.28) : Colors.white.withOpacity(0.09)),
      ),
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 3,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [accent, accent.withOpacity(0.15)]),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(match.competition, style: TextStyle(color: accent.withOpacity(0.75),
                  fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              SizedBox(height: 5),
              Text(match.homeTeam, style: TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(context.read<LanguageProvider>().l10n.t('sport_vs'), style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 9))),
              Text(match.awayTeam, style: const TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
              children: [
              if (isLive && hasScore) ...[
                isTizen
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.red, borderRadius: BorderRadius.circular(6),
                            boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.45), blurRadius: 10)]),
                        child: Text('${match.homeScore}-${match.awayScore}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)))
                    : ClipRRect(borderRadius: BorderRadius.circular(6),
                        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.red.withOpacity(0.88),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.45), blurRadius: 10)]),
                            child: Text('${match.homeScore}-${match.awayScore}',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))))),
                SizedBox(height: 5),
                const RepaintBoundary(child: _LiveBadge()),
              ] else if (isFinished && hasScore) ...[
                Text('${match.homeScore}-${match.awayScore}',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w800)),
                Text(context.read<LanguageProvider>().l10n.t('sport_finished'), style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8, fontWeight: FontWeight.w700)),
              ] else ...[
                Text(match.time.isNotEmpty ? match.time : '--:--',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(context.read<LanguageProvider>().l10n.t('sport_soon'), style: TextStyle(color: accent.withOpacity(0.55),
                    fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ],
            ]),
          ])),
      ]),
    );

    if (!isTizen) {
      inner = ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: inner));
    }
    return inner.animate().fadeIn(
        delay: Duration(milliseconds: index.clamp(0,6)*40), duration: 250.ms);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SPORT MATCH MODEL
// ═════════════════════════════════════════════════════════════════════════════
class _SportMatch {
  final String homeTeam, awayTeam, competition, time, status;
  final int? homeScore, awayScore;
  const _SportMatch({required this.homeTeam, required this.awayTeam,
      required this.competition, required this.time, required this.status,
      this.homeScore, this.awayScore});
}

// ═════════════════════════════════════════════════════════════════════════════
// LIVE BADGE
// ═════════════════════════════════════════════════════════════════════════════
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}
class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _p;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _p = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _p, builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.red.withOpacity(0.82 + _p.value * 0.18),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.4 * _p.value), blurRadius: 6, spreadRadius: 1)]),
      // Dot seul — pas de label explicite
      child: Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75 + _p.value * 0.25),
          shape: BoxShape.circle),
      )));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SKELETON BOX — contrôleur partagé (shimmer unifié, un seul timer)
// ═════════════════════════════════════════════════════════════════════════════
class _SkeletonBox extends StatefulWidget {
  final double? width, height;
  final double borderRadius;
  final int staggerIndex; // remplace delay — utilisé pour l'offset visuel, pas pour le timer
  const _SkeletonBox({this.width, this.height, this.borderRadius = 12, this.staggerIndex = 0});
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}
class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;
  @override
  void initState() {
    super.initState();
    // Un seul contrôleur par instance — mais désormais sans delay setState externe
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    // staggerIndex décale visuellement la position du shimmer, pas le timer
    final staggerOffset = (widget.staggerIndex * 0.12).clamp(0.0, 0.48);
    return AnimatedBuilder(animation: _a, builder: (_, __) {
      final t = ((_a.value + staggerOffset) % 1.0);
      return ClipRRect(borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Container(width: widget.width, height: widget.height,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: const Alignment(-1.5, -0.5), end: const Alignment(1.5, 0.5),
              colors: const [Color(0xFF1A1A26), Color(0xFF1C1C2A), Color(0xFF252535), Color(0xFF1C1C2A), Color(0xFF1A1A26)],
              stops: [0.0, (t-0.15).clamp(0.0,1.0), t, (t+0.15).clamp(0.0,1.0), 1.0]))));
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROFILE SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _ProfileSheet extends StatelessWidget {
  final VoidCallback onProfile, onSettings;
  const _ProfileSheet({required this.onProfile, required this.onSettings});
  @override
  Widget build(BuildContext context) {
    final provider  = context.read<IptvProvider>();
    final username  = provider.username;
    final isTizen   = Platform.operatingSystem == 'tizen';
    Widget inner = Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isTizen ? 0.97 : 0.72),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(width: 36, height: 4, decoration: BoxDecoration(
            gradient: AppTheme.gradientHorizontal, borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.4), blurRadius: 8)])),
        const SizedBox(height: 22),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            _AvatarBubble(username: username, size: 52),
            SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(username.isNotEmpty ? username : 'Mon compte',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text(context.read<LanguageProvider>().l10n.t('settings_title'),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ])),
          ])).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
        SizedBox(height: 20),
        Container(height: 1, color: Colors.white.withOpacity(0.06)),
        SizedBox(height: 8),
        _SheetRow(icon: Icons.person_rounded, iconColor: AppTheme.violet, label: context.read<LanguageProvider>().l10n.t('my_profile'),
            subtitle: context.read<LanguageProvider>().l10n.t('profile_avatar_desc'), onTap: onProfile)
            .animate().fadeIn(delay: 80.ms).slideY(begin: 0.04, end: 0, delay: 80.ms),
        _SheetRow(icon: Icons.settings_rounded, iconColor: AppTheme.secondary, label: context.read<LanguageProvider>().l10n.t('settings_title'),
            subtitle: 'Playlists, affichage, préférences', onTap: onSettings)
            .animate().fadeIn(delay: 130.ms).slideY(begin: 0.04, end: 0, delay: 130.ms),
        SizedBox(height: 8),
        Container(height: 1, color: Colors.white.withOpacity(0.06)),
        SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DangerButton(label: context.read<LanguageProvider>().l10n.t('settings_logout'),
              icon: Icons.logout_rounded, height: 46,
              onTap: () {
                final nav = Navigator.of(context); nav.pop();
                Future.microtask(() => _doLogout(context, provider));
              })).animate().fadeIn(delay: 180.ms),
        const SizedBox(height: 16),
      ])),
    );
    if (!isTizen) {
      inner = ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: inner));
    }
    return inner;
  }

  void _doLogout(BuildContext context, IptvProvider provider) {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final l = context.read<LanguageProvider>().l10n;
    showDialog(context: rootCtx, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(context.read<LanguageProvider>().l10n.t('settings_logout'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      content: Text(context.read<LanguageProvider>().l10n.t('settings_logout_confirm'), style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(rootCtx),
            child: Text(context.read<LanguageProvider>().l10n.t('cancel'), style: TextStyle(color: AppTheme.textSecondary))),
        TextButton(onPressed: () async {
          Navigator.pop(rootCtx); await provider.logout();
          if (rootCtx.mounted) Navigator.of(rootCtx).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
        }, child: Text(context.read<LanguageProvider>().l10n.t('settings_logout'),
            style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600))),
      ]));
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon; final Color iconColor; final String label, subtitle; final VoidCallback onTap;
  const _SheetRow({required this.icon, required this.iconColor,
      required this.label, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap,
      splashColor: iconColor.withOpacity(0.10), highlightColor: iconColor.withOpacity(0.05),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [iconColor.withOpacity(0.20), iconColor.withOpacity(0.08)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: iconColor.withOpacity(0.20))),
            child: Icon(icon, color: iconColor, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: iconColor.withOpacity(0.4), size: 14),
        ]))));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DOWNLOAD NAV BTN — avec badge actif
// ═════════════════════════════════════════════════════════════════════════════
class _DownloadNavBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _DownloadNavBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => Consumer<DownloadService>(
    builder: (_, svc, __) {
      final hasActive = svc.activeCount > 0;
      return GestureDetector(onTap: onTap,
        child: SizedBox(width: 36, height: 36,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(width: 36, height: 36,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.download_rounded, color: Colors.white, size: 16)),
            if (hasActive)
              Positioned(top: 2, right: 6,
                child: Container(width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: AppTheme.violet, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: AppTheme.violet.withOpacity(0.7), blurRadius: 4)]))),
          ])));
    });
}

// ═════════════════════════════════════════════════════════════════════════════
// NAV BTN
// ═════════════════════════════════════════════════════════════════════════════
class _NavBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap,
      child: Container(width: 36, height: 36, margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16)));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AVATAR BUBBLE
// ═════════════════════════════════════════════════════════════════════════════
class _AvatarBubble extends StatefulWidget {
  final String username; final double size;
  const _AvatarBubble({required this.username, required this.size});
  @override
  State<_AvatarBubble> createState() => _AvatarBubbleState();
}
class _AvatarBubbleState extends State<_AvatarBubble> {
  String _avatarPath = '';
  bool   _hasAvatar  = false;
  @override
  void initState() {
    super.initState();
    final path = Hive.box('settings').get('arich_user_avatar_path', defaultValue: '') as String;
    if (path.isNotEmpty) {
      _avatarPath = path;
      _hasAvatar  = File(path).existsSync(); // caché ici — jamais dans build()
    }
  }
  @override
  Widget build(BuildContext context) {
    final initial = widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?';
    return Container(width: widget.size, height: widget.size,
      decoration: BoxDecoration(gradient: _hasAvatar ? null : AppTheme.gradientPrimary,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 10)]),
      child: ClipOval(child: _hasAvatar
          ? Image.file(File(_avatarPath), fit: BoxFit.cover)
          : Center(child: Text(initial, style: TextStyle(color: Colors.white,
              fontSize: widget.size * 0.38, fontWeight: FontWeight.w700)))));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TV SIDEBAR TAB
// ═════════════════════════════════════════════════════════════════════════════
class _TVSidebarTab extends StatefulWidget {
  final IconData icon; final String label; final bool active, autofocus;
  final VoidCallback onTap; final int animDelay;
  const _TVSidebarTab({required this.icon, required this.label, required this.active,
      required this.onTap, this.autofocus = false, this.animDelay = 0});
  @override
  State<_TVSidebarTab> createState() => _TVSidebarTabState();
}
class _TVSidebarTabState extends State<_TVSidebarTab> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap(); return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: widget.active ? LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                colors: [AppTheme.violet.withOpacity(0.22), AppTheme.secondary.withOpacity(0.08)]) : null,
            color: !widget.active ? (_focused ? Colors.white.withOpacity(0.05) : Colors.transparent) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.active ? AppTheme.violet.withOpacity(0.40)
                : _focused ? AppTheme.violet.withOpacity(0.25) : Colors.transparent),
            boxShadow: widget.active ? [BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 2))] : null),
          child: Row(children: [
            AnimatedContainer(duration: const Duration(milliseconds: 200),
              width: 3, height: 18, margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: widget.active ? AppTheme.gradientVertical : null,
                color: widget.active ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: widget.active ? [BoxShadow(color: AppTheme.violet.withOpacity(0.6), blurRadius: 6)] : null)),
            Icon(widget.icon, size: 18, color: widget.active ? AppTheme.violet : Colors.white54),
            const SizedBox(width: 10),
            Flexible(child: Text(widget.label, style: TextStyle(color: widget.active ? Colors.white : Colors.white60,
                fontSize: 13, fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400), overflow: TextOverflow.ellipsis)),
            if (widget.active) ...[
              const Spacer(),
              Container(width: 6, height: 6, decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.7), blurRadius: 6)])),
            ],
          ]),
        )),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: widget.animDelay), duration: 300.ms)
        .slideX(begin: -0.06, end: 0, delay: Duration(milliseconds: widget.animDelay),
            duration: 350.ms, curve: Curves.easeOutCubic);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LANDSCAPE BOTTOM NAV
// ═════════════════════════════════════════════════════════════════════════════
class _LandscapeBottomNav extends StatelessWidget {
  final List<({IconData icon, String label, int index})> tabs;
  final int activeTab; final bool isSearching; final String username, searchLabel;
  final void Function(int) onTabTap;
  final VoidCallback onSearchTap, onProfileTap;
  final VoidCallback? onDownloadsTap;
  const _LandscapeBottomNav({required this.tabs, required this.activeTab,
      required this.isSearching, required this.username, required this.searchLabel,
      required this.onTabTap, required this.onSearchTap, required this.onProfileTap,
      this.onDownloadsTap});
  @override
  Widget build(BuildContext context) {
    final isTizen = Platform.operatingSystem == 'tizen';
    final inner = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF06060F).withOpacity(isTizen ? 0.97 : 0.88),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08)))),
      child: SafeArea(top: false, child: SizedBox(height: 52, child: Row(children: [
        Expanded(child: Row(children: tabs.map((t) {
          final active = activeTab == t.index && !isSearching;
          return Expanded(child: _LandNavChip(icon: t.icon, label: t.label, active: active, onTap: () => onTabTap(t.index)));
        }).toList())),
        Container(width: 1, height: 28, color: Colors.white.withOpacity(0.06)),
        _LandNavChip(icon: Icons.search_rounded, label: searchLabel, active: isSearching, onTap: onSearchTap),
        if (onDownloadsTap != null) ...[
          Container(width: 1, height: 28, color: Colors.white.withOpacity(0.06)),
          Consumer<DownloadService>(builder: (_, svc, __) {
            final hasActive = svc.activeCount > 0;
            return Stack(clipBehavior: Clip.none, children: [
              _LandNavChip(icon: Icons.download_rounded, label: context.read<LanguageProvider>().l10n.t('downloads_title'), active: false, onTap: onDownloadsTap!),
              if (hasActive)
                Positioned(top: 6, right: 8,
                  child: Container(width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: AppTheme.violet, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.7), blurRadius: 4)]))),
            ]);
          }),
        ],
        Container(width: 1, height: 28, color: Colors.white.withOpacity(0.06)),
        Material(color: Colors.transparent, child: InkWell(onTap: onProfileTap, borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 52, child: Center(child: _AvatarBubble(username: username, size: 28))))),
      ]))));
    if (isTizen) return ClipRect(child: inner);
    return ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: inner));
  }
}

class _LandNavChip extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  const _LandNavChip({required this.icon, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      splashColor: AppTheme.violet.withOpacity(0.15), highlightColor: Colors.transparent,
      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
        height: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Stack(alignment: Alignment.topCenter, children: [
          AnimatedContainer(duration: const Duration(milliseconds: 200), height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [AppTheme.violet, AppTheme.secondary]) : null,
              color: active ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
              boxShadow: active ? [BoxShadow(color: AppTheme.violet.withOpacity(0.6), blurRadius: 6)] : null)),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: active ? AppTheme.violet.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 17, color: active ? AppTheme.violet : Colors.white30)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 8.5, color: active ? Colors.white : Colors.white30,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ]),
        ]))));
  }
}