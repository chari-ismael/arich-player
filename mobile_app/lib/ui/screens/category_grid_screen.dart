// lib/ui/screens/category_grid_screen.dart
// ARICH Player — Category Grid Screen v9.5
//
// NOUVEAUTÉS v9 (redesign AAA — logique 100% préservée) :
// [DESIGN] Sidebar : fond 0A0912 + header ShaderMask gradient + séparateur glow
// [DESIGN] SidebarCatItem : left accent 3px glow + fond glass + icône pill + dot actif
// [DESIGN] ContentPanel header : left accent couleur-accent + badge premium
// [DESIGN] SubcatCard : double glow icône + border colorée + gradient renforcé
// [DESIGN] CountryTile : gradient dark + badge glow + flag plus large
// [DESIGN] AppBar portrait : FlexibleSpace gradient + ShaderMask title rajdhani
// [DESIGN] Empty state : animation pulsante + flèche animée slide
// [DESIGN] Skeleton : shimmer contraste élevé + border subtile
// [FIX]   liveChannels+channelIndex passés au PlayerScreen (flèches ◀▶)
// [FIX]   Films/Séries vides au clic : loadTabContent avant filterByCategory
// [DESIGN] Portrait : liste verticale _CatListItem (left accent + icône pill + chevron)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/iptv_provider.dart';
import '../../models/channel.dart';
import '../widgets/channel_card.dart';
import 'player_screen.dart';
import 'details_screen.dart';
import '../../core/tv_navigation.dart';
import '../../core/country_utils.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers noms / icônes / couleurs — inchangés
// ─────────────────────────────────────────────────────────────────────────────
String _cleanName(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'^[\|\s]+'), '');
  s = s.replaceAll(
    RegExp(r'^[A-Za-z]{2,3}\s*[\|\:\-\.]\s*', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'^[\|\s]+'), '').trim();
  if (s.isEmpty) return raw.trim();
  if (s == s.toUpperCase() && s.length > 2) {
    s = s.split(RegExp(r'(\s+|/)')).map((w) {
      if (w.isEmpty || w == '/') return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join('');
    s = raw.trim().split(RegExp(r'^[\|\s]*[A-Za-z]{2,3}\s*[\|\:\-\.]\s*[\|\s]*')).last;
    s = s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }
  return s.isEmpty ? raw.trim() : s;
}

IconData _themeIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('sport') || n.contains('foot') || n.contains('bein') ||
      n.contains('dazn') || n.contains('rugby') || n.contains('tennis') ||
      n.contains('nba') || n.contains('f1') || n.contains('boxing'))
    return Icons.sports_soccer_rounded;
  if (n.contains('cinema') || n.contains('film') || n.contains('movie') ||
      n.contains('cine') || n.contains('vod'))
    return Icons.movie_rounded;
  if (n.contains('serie') || n.contains('saison') || n.contains('season'))
    return Icons.tv_rounded;
  if (n.contains('enfant') || n.contains('kids') || n.contains('cartoon') ||
      n.contains('junior'))
    return Icons.child_care_rounded;
  if (n.contains('info') || n.contains('news') || n.contains('actu'))
    return Icons.newspaper_rounded;
  if (n.contains('music') || n.contains('musique') || n.contains('radio') ||
      n.contains('clip'))
    return Icons.music_note_rounded;
  if (n.contains('doc') || n.contains('nature') || n.contains('science') ||
      n.contains('histoire'))
    return Icons.explore_rounded;
  if (n.contains('adult') || n.contains('xxx') || n.contains('+18') ||
      n.contains('18+'))
    return Icons.lock_rounded;
  if (n.contains('religion') || n.contains('islam') || n.contains('coran'))
    return Icons.mosque_rounded;
  if (n.contains('general') || n.contains('tnt') || n.contains('region'))
    return Icons.live_tv_rounded;
  return Icons.play_circle_outline_rounded;
}

Color _themeColor(String name, Color fallback) {
  final n = name.toLowerCase();
  if (n.contains('sport') || n.contains('foot') || n.contains('bein'))
    return const Color(0xFF34C77B);
  if (n.contains('cinema') || n.contains('film') || n.contains('movie'))
    return const Color(0xFFFF6B6B);
  if (n.contains('serie')) return const Color(0xFF845EF7);
  if (n.contains('enfant') || n.contains('kids')) return const Color(0xFFFFD43B);
  if (n.contains('info') || n.contains('news')) return const Color(0xFF4DABF7);
  if (n.contains('adult') || n.contains('xxx')) return const Color(0xFFFF8787);
  return fallback;
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle groupe pays — inchangé
// ─────────────────────────────────────────────────────────────────────────────
class _CountryGroup {
  final CountryInfo? country;
  final List<Map<String, dynamic>> cats;
  const _CountryGroup({required this.country, required this.cats});
  String get flag  => country?.flag ?? '🌐';
  String get label => country != null ? CountryUtils.localizedName(country!.code) : 'Autres';
  int    get count => cats.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// CategoryGridScreen — logique 100% inchangée
// ─────────────────────────────────────────────────────────────────────────────
class CategoryGridScreen extends StatefulWidget {
  final int    tabIndex;
  final String title;
  final IconData icon;
  final bool embedded;

  const CategoryGridScreen({
    super.key,
    required this.tabIndex,
    required this.title,
    required this.icon,
    this.embedded = false,
  });

  @override
  State<CategoryGridScreen> createState() => _CategoryGridScreenState();
}

class _CategoryGridScreenState extends State<CategoryGridScreen> {
  String         _view     = 'flat';
  _CountryGroup? _selected;
  bool           _isDragging = false;
  List<Map<String, dynamic>>? _localCats;

  String? _activeCatId;
  String  _activeCatName = '';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery  = '';
  String _activeFilter = ''; // '' = Tout, sinon clé thème ex: 'sport'
  String _activeAlpha  = ''; // '' = toutes lettres, sinon ex: 'A'
  bool   _showFilters  = false; // panel filtre visible
  String _activeCountry = ''; // '' = tous pays, sinon code pays ex: 'fr'

  List<_CountryGroup>? _cache;
  int                  _cacheLen = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<IptvProvider>();
      final cats = p.getCategoriesOrdered(widget.tabIndex);
      if (cats.isEmpty) p.loadTabContent(widget.tabIndex);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.tabIndex) {
    1 => AppTheme.catLiveAccent,
    2 => AppTheme.catMoviesAccent,
    _ => AppTheme.catSeriesAccent,
  };

  List<Map<String, dynamic>> _cats(IptvProvider p) =>
      _localCats ?? p.getCategoriesOrdered(widget.tabIndex);

  List<_CountryGroup> _groups(List<Map<String, dynamic>> cats) {
    if (_cache != null && _cacheLen == cats.length) return _cache!;
    final map    = <String, List<Map<String, dynamic>>>{};
    final mapInfo = <String, CountryInfo>{};
    final others = <Map<String, dynamic>>[];
    for (final cat in cats) {
      final name    = cat['name']?.toString() ?? '';
      final country = CountryUtils.fromGroupTitle(name);
      if (country == null) {
        others.add(cat);
      } else {
        map.putIfAbsent(country.code, () => []).add(cat);
        mapInfo[country.code] = country;
      }
    }
    final groups = map.entries
        .map((e) => _CountryGroup(country: mapInfo[e.key], cats: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (others.isNotEmpty) groups.add(_CountryGroup(country: null, cats: others));
    _cache    = groups;
    _cacheLen = cats.length;
    return groups;
  }

  void _openCatPortrait(BuildContext ctx, Map<String, dynamic> cat, IptvProvider p) {
    if (_isDragging) { _saveAndExitDrag(p); return; }
    final id   = cat['category_id']?.toString() ?? cat['id']?.toString() ?? '';
    final name = _cleanName(cat['name']?.toString() ?? '');
    Navigator.push(ctx, _route(_ContentScreenPortrait(
      tabIndex: widget.tabIndex, categoryId: id, categoryName: name,
    )));
  }

  void _selectCat(Map<String, dynamic> cat, IptvProvider p) {
    final id   = cat['category_id']?.toString() ?? cat['id']?.toString() ?? '';
    final name = _cleanName(cat['name']?.toString() ?? '');
    if (_activeCatId == id) return;
    setState(() { _activeCatId = id; _activeCatName = name; });
    p.filterByCategory(id);
  }

  // Définit les thèmes de filtre disponibles et les mots-clés associés
  static const _kThemeFilters = {
    'sport'   : ['sport', 'foot', 'bein', 'dazn', 'rugby', 'tennis', 'nba', 'f1', 'boxing', 'basket'],
    'cinema'  : ['cinema', 'film', 'movie', 'cine', 'vod'],
    'series'  : ['serie', 'saison', 'season'],
    'news'    : ['info', 'news', 'actu'],
    'music'   : ['music', 'musique', 'radio', 'clip'],
    'enfants' : ['enfant', 'kids', 'cartoon', 'junior'],
    'doc'     : ['doc', 'nature', 'science', 'histoire'],
    'general' : ['general', 'tnt', 'region'],
  };

  // Labels affichés pour chaque clé
  static const _kFilterLabels = {
    'sport'   : '⚽ Sport',
    'cinema'  : '🎬 Films',
    'series'  : '📺 Séries',
    'news'    : '📰 Info',
    'music'   : '🎵 Musique',
    'enfants' : '🧸 Enfants',
    'doc'     : '🔭 Doc',
    'general' : '📡 Général',
  };

  /// Retourne les clés de thème effectivement présentes dans la liste de cats
  List<String> _availableFilters(List<Map<String, dynamic>> cats) {
    final seen = <String>{};
    for (final cat in cats) {
      final n = _cleanName(cat['name']?.toString() ?? '').toLowerCase();
      for (final entry in _kThemeFilters.entries) {
        if (entry.value.any((kw) => n.contains(kw))) {
          seen.add(entry.key);
        }
      }
    }
    // Retourner dans l'ordre de _kThemeFilters
    return _kThemeFilters.keys.where((k) => seen.contains(k)).toList();
  }

  List<Map<String, dynamic>> _allCatsFlat(IptvProvider p) {
    var cats = _cats(p);
    // Filtre par thème
    if (_activeFilter.isNotEmpty) {
      final kws = _kThemeFilters[_activeFilter] ?? [];
      cats = cats.where((c) {
        final n = _cleanName(c['name']?.toString() ?? '').toLowerCase();
        return kws.any((kw) => n.contains(kw));
      }).toList();
    }
    // Filtre par pays/langue
    if (_activeCountry.isNotEmpty) {
      cats = cats.where((c) {
        final name    = c['name']?.toString() ?? '';
        final country = CountryUtils.fromGroupTitle(name);
        return country?.code.toLowerCase() == _activeCountry;
      }).toList();
    }
    // Filtre par lettre alphabétique
    if (_activeAlpha.isNotEmpty) {
      cats = cats.where((c) {
        final n = _cleanName(c['name']?.toString() ?? '');
        return n.isNotEmpty && n[0].toUpperCase() == _activeAlpha;
      }).toList();
    }
    // Filtre par recherche texte
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      cats = cats.where((c) {
        final n = _cleanName(c['name']?.toString() ?? '').toLowerCase();
        return n.contains(q);
      }).toList();
    }
    return cats;
  }

  /// Lettres disponibles dans la liste de catégories (tri alphabétique)
  List<String> _availableLetters(List<Map<String, dynamic>> cats) {
    final seen = <String>{};
    for (final cat in cats) {
      final n = _cleanName(cat['name']?.toString() ?? '');
      if (n.isNotEmpty) seen.add(n[0].toUpperCase());
    }
    final list = seen.toList()..sort();
    return list;
  }

  /// Pays disponibles dans la liste (triés par nombre de catégories desc)
  List<({String code, String flag, String label, int count})> _availableCountries(
      List<Map<String, dynamic>> cats) {
    final map = <String, int>{};
    final info = <String, CountryInfo>{};
    for (final cat in cats) {
      final country = CountryUtils.fromGroupTitle(cat['name']?.toString() ?? '');
      if (country != null) {
        map[country.code] = (map[country.code] ?? 0) + 1;
        info[country.code] = country;
      }
    }
    final list = map.entries.map((e) => (
      code:  e.key.toLowerCase(),
      flag:  info[e.key]?.flag ?? '🌐',
      label: CountryUtils.localizedName(e.key),
      count: e.value,
    )).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  bool get _hasActiveFilter =>
      _activeFilter.isNotEmpty || _activeAlpha.isNotEmpty || _activeCountry.isNotEmpty;

  void _enterDrag(IptvProvider p) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isDragging = true;
      _view       = 'grid';
      _localCats  = List.from(p.getCategoriesOrdered(widget.tabIndex));
    });
  }

  void _saveAndExitDrag(IptvProvider p) {
    if (_localCats != null) {
      p.saveCategoryOrder(widget.tabIndex, _localCats!);
      _cache = null;
    }
    setState(() { _isDragging = false; _view = 'flat'; });
  }

  void _scrollOnDrag(Offset pos) {
    if (!_scroll.hasClients) return;
    final h = MediaQuery.of(context).size.height;
    const zone = 80.0; const speed = 15.0;
    if (pos.dy < zone) {
      _scroll.jumpTo((_scroll.offset - speed * (1 - pos.dy / zone))
          .clamp(0.0, _scroll.position.maxScrollExtent));
    } else if (pos.dy > h - zone) {
      _scroll.jumpTo((_scroll.offset + speed * ((pos.dy - (h - zone)) / zone))
          .clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  PageRoute _route(Widget p) => PageRouteBuilder(
    pageBuilder: (_, a, __) => p,
    transitionsBuilder: (_, a, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child),
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<IptvProvider>(builder: (ctx, p, _) {
      final isTV   = context.isTV;
      final isLand = MediaQuery.of(context).orientation == Orientation.landscape;
      final sizes  = context.tvSizes;
      if (isTV || isLand) return _buildTwoColumnLayout(ctx, p, isTV, sizes);
      return _buildPortraitLayout(ctx, p, isTV, sizes);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUT 2 COLONNES
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTwoColumnLayout(BuildContext ctx, IptvProvider p, bool isTV, TVSizes sizes) {
    final cats      = _allCatsFlat(p);
    final sideWidth = isTV ? 240.0 : 210.0;

    return TvBackHandler(
      onBack: () { if (!widget.embedded) Navigator.of(ctx).pop(); },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Sidebar ─────────────────────────────────────────────────────
            SizedBox(
              width: sideWidth,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF0A0912), Color(0xFF07070F)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSidebarHeader(p, isTV),
                    _buildSidebarSearch(isTV),
                    // Bouton filtre sidebar
                    _buildSidebarFilterBtn(p, isTV),
                    // Panel filtre collapsable
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _showFilters
                          ? _buildSidebarFilterPanel(p, isTV)
                          : const SizedBox(width: double.infinity),
                    ),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.transparent,
                          AppTheme.violet.withOpacity(0.25),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: cats.length,
                        itemBuilder: (_, i) {
                          final cat   = cats[i];
                          final id    = cat['category_id']?.toString() ?? cat['id']?.toString() ?? '';
                          final name  = _cleanName(cat['name']?.toString() ?? '');
                          final icon  = _themeIcon(name);
                          final color = _themeColor(name, _accent);
                          final active = _activeCatId == id;
                          return _SidebarCatItem(
                            name: name, icon: icon, color: color,
                            active: active, isTV: isTV, delay: i * 15,
                            onTap: () => _selectCat(cat, p),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Séparateur gradient vertical
            Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.violet.withOpacity(0.35),
                    AppTheme.violet.withOpacity(0.35),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.15, 0.85, 1.0],
                ),
              ),
            ),

            // ── Panneau contenu ──────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.025, 0), end: Offset.zero)
                        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                child: _activeCatId == null
                    ? _buildEmptyState(isTV)
                    : _ContentPanel(
                        key: ValueKey(_activeCatId),
                        tabIndex: widget.tabIndex,
                        categoryId: _activeCatId!,
                        categoryName: _activeCatName,
                        accent: _accent,
                        isTV: isTV,
                        sizes: sizes,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(IptvProvider p, bool isTV) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, isTV ? 24 : 16, 14, 14),
      child: Row(children: [
        Container(
          width: isTV ? 30 : 26, height: isTV ? 30 : 26,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 12),
              BoxShadow(color: AppTheme.violet.withOpacity(0.18), blurRadius: 24),
            ],
          ),
          child: Icon(widget.icon, color: Colors.white, size: isTV ? 15 : 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ShaderMask(
            shaderCallback: (b) => AppTheme.gradientPrimary
                .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
            child: Text(widget.title,
              style: GoogleFonts.rajdhani(
                color: Colors.white, fontSize: isTV ? 17 : 15,
                fontWeight: FontWeight.w700, letterSpacing: 0.5),
              overflow: TextOverflow.ellipsis),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            gradient: AppTheme.gradientHorizontal,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 8)],
          ),
          child: Text('${_cats(p).length}',
            style: GoogleFonts.inter(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _buildSidebarSearch(bool isTV) {
    final active = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Container(
        height: isTV ? 36 : 32,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0E1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppTheme.violet.withOpacity(0.5) : Colors.white.withOpacity(0.07),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: AppTheme.violet.withOpacity(0.2), blurRadius: 12)]
              : null,
        ),
        child: TextField(
          controller: _searchCtrl,
          style: GoogleFonts.inter(color: Colors.white, fontSize: isTV ? 13 : 11),
          decoration: InputDecoration(
            hintText: context.read<LanguageProvider>().l10n.t('search_hint'),
            hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 11),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search_rounded,
                color: active ? AppTheme.violet : Colors.white24,
                size: isTV ? 16 : 14),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: active
                ? GestureDetector(
                    onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                    child: Icon(Icons.close_rounded,
                        color: AppTheme.violet.withOpacity(0.7), size: 14))
                : null,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
      ),
    );
  }

  // ── Bouton filtre sidebar ────────────────────────────────────────────────
  Widget _buildSidebarFilterBtn(IptvProvider p, bool isTV) {
    final active = _showFilters || _hasActiveFilter;
    return GestureDetector(
      onTap: () => setState(() => _showFilters = !_showFilters),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _accent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active ? _accent.withOpacity(0.4) : Colors.white.withOpacity(0.07),
          ),
          boxShadow: active
              ? [BoxShadow(color: _accent.withOpacity(0.2), blurRadius: 8)]
              : null,
        ),
        child: Row(children: [
          Icon(Icons.tune_rounded,
              color: active ? _accent : Colors.white38,
              size: isTV ? 15 : 13),
          SizedBox(width: 7),
          Text(context.read<LanguageProvider>().l10n.t('cat_filter'),
            style: GoogleFonts.inter(
              color: active ? _accent : Colors.white38,
              fontSize: isTV ? 12 : 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          const Spacer(),
          if (_hasActiveFilter)
            Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _accent.withOpacity(0.6), blurRadius: 4)],
              ),
            ),
          const SizedBox(width: 2),
          Icon(
            _showFilters ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: active ? _accent : Colors.white24,
            size: 16,
          ),
        ]),
      ),
    );
  }

  // ── Panel filtre sidebar ─────────────────────────────────────────────────
  Widget _buildSidebarFilterPanel(IptvProvider p, bool isTV) {
    final allCats  = _cats(p);
    final themes   = _availableFilters(allCats);
    final letters  = _availableLetters(allCats);
    final countries = _availableCountries(allCats);

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(text.toUpperCase(),
        style: GoogleFonts.inter(
          color: Colors.white.withOpacity(0.18), fontSize: 8.5,
          fontWeight: FontWeight.w700, letterSpacing: 1.1)),
    );

    Widget chip(String label, bool selected, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            margin: const EdgeInsets.only(right: 5, bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? _accent.withOpacity(0.2) : const Color(0xFF1A1A26),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _accent.withOpacity(0.6) : Colors.white.withOpacity(0.08),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(label,
              style: GoogleFonts.inter(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
          ),
        );

    return ConstrainedBox(
      // Hauteur max = 280px pour ne pas dépasser la sidebar disponible
      constraints: const BoxConstraints(maxHeight: 280),
      child: Container(
        color: const Color(0xFF08080F),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // Thèmes
              if (themes.isNotEmpty) ...[
                sectionLabel('Thème'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Wrap(
                    children: themes.map((k) => chip(
                      _kFilterLabels[k] ?? k,
                      _activeFilter == k,
                      () => setState(() => _activeFilter = _activeFilter == k ? '' : k),
                    )).toList(),
                  ),
                ),
              ],

              // Pays / Langue
              if (countries.isNotEmpty) ...[
                sectionLabel('Langue'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Wrap(
                    children: countries.take(12).map((c) => chip(
                      '${c.flag} ${c.label}',
                      _activeCountry == c.code,
                      () => setState(() =>
                          _activeCountry = _activeCountry == c.code ? '' : c.code),
                    )).toList(),
                  ),
                ),
              ],

              // Lettre A-Z
              if (letters.isNotEmpty) ...[
                sectionLabel('Lettre'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: Wrap(
                    children: letters.map((l) => chip(
                      l,
                      _activeAlpha == l,
                      () => setState(() => _activeAlpha = _activeAlpha == l ? '' : l),
                    )).toList(),
                  ),
                ),
              ],

              // Effacer tout
              if (_hasActiveFilter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _activeFilter = ''; _activeAlpha = ''; _activeCountry = '';
                    }),
                    child: Text(context.read<LanguageProvider>().l10n.t('cat_clear_all'),
                      style: GoogleFonts.inter(
                        color: _accent.withOpacity(0.8), fontSize: 10,
                        fontWeight: FontWeight.w600)),
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isTV) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: isTV ? 72 : 60, height: isTV ? 72 : 60,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 28, spreadRadius: 2),
              BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 50, spreadRadius: 8),
            ],
          ),
          child: Icon(widget.icon, color: Colors.white.withOpacity(0.9), size: isTV ? 30 : 24),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1.0, end: 1.06, duration: 2000.ms, curve: Curves.easeInOut),
        SizedBox(height: isTV ? 20 : 16),
        Text(context.read<LanguageProvider>().l10n.t('cat_select_category'),
          style: GoogleFonts.rajdhani(
            color: Colors.white, fontSize: isTV ? 18 : 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_back_rounded, color: AppTheme.violet.withOpacity(0.6), size: 13)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .slideX(begin: 0, end: -0.3, duration: 900.ms, curve: Curves.easeInOut),
          SizedBox(width: 5),
          Text(context.read<LanguageProvider>().l10n.t('cat_select_sub'),
            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: isTV ? 12 : 10)),
        ]),
      ]).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PORTRAIT LAYOUT
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPortraitLayout(BuildContext ctx, IptvProvider p, bool isTV, TVSizes sizes) {
    final cats = _allCatsFlat(p);
    final top  = MediaQuery.paddingOf(ctx).top;

    return TvBackHandler(
      onBack: () { if (!widget.embedded) Navigator.of(ctx).pop(); },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.5, -0.6), radius: 1.0,
              colors: [_accent.withOpacity(0.05), Colors.transparent],
            ),
          ))),
          // [FIX] Abandon de SliverPersistentHeader (extents dynamiques → crash).
          // Column fixe + ListView scrollable = stable et simple.
          Column(children: [
            // AppBar fixe
            Container(
              padding: EdgeInsets.fromLTRB(4, top + 4, 4, 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_accent.withOpacity(0.08), AppTheme.background],
                ),
              ),
              child: Row(children: [
                if (!widget.embedded)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                Expanded(child: _barTitle(false, isTV)),
                // Bouton filtre avec badge
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _showFilters = !_showFilters),
                    child: Stack(clipBehavior: Clip.none, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: (_showFilters || _hasActiveFilter)
                              ? _accent.withOpacity(0.18)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_showFilters || _hasActiveFilter)
                                ? _accent.withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                          ),
                          boxShadow: (_showFilters || _hasActiveFilter)
                              ? [BoxShadow(color: _accent.withOpacity(0.25), blurRadius: 8)]
                              : null,
                        ),
                        child: Icon(Icons.tune_rounded,
                            color: (_showFilters || _hasActiveFilter)
                                ? _accent : Colors.white38,
                            size: 16),
                      ),
                      if (_hasActiveFilter)
                        Positioned(top: 4, right: 4,
                          child: Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                              gradient: AppTheme.gradientPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                  color: _accent.withOpacity(0.6), blurRadius: 4)],
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                if (!_isDragging)
                  IconButton(
                    icon: const Icon(Icons.swap_vert_rounded,
                        color: Colors.white38, size: 18),
                    onPressed: () => _enterDrag(p),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _saveAndExitDrag(p),
                    icon: Icon(Icons.check_rounded, color: _accent, size: 16),
                    label: Text(context.read<LanguageProvider>().l10n.t('cat_done'),
                      style: GoogleFonts.inter(
                          color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientHorizontal,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(
                          color: AppTheme.violet.withOpacity(0.35), blurRadius: 8)],
                    ),
                    child: Text('${cats.length}',
                      style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
            // Barre de recherche
            Container(
              color: AppTheme.background,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: _buildSearchField(),
            ),
            // Panel filtre collapsable via AnimatedSize (stable)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _showFilters
                  ? _buildFilterPanel(p)
                  : const SizedBox(width: double.infinity),
            ),
            Container(height: 1, color: Colors.white.withOpacity(0.05)),
            // Liste scrollable
            Expanded(
              child: cats.isEmpty
                  ? _buildLoadingOrEmpty(p, isTV)
                  : _isDragging
                      ? _buildDragList(cats, p, isTV, sizes)
                      : _buildCatList(cats, p, isTV, sizes),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildSearchField() {
    final active = _searchQuery.isNotEmpty;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: active ? _accent.withOpacity(0.45) : Colors.white.withOpacity(0.08),
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: _accent.withOpacity(0.15), blurRadius: 10)]
            : null,
      ),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: context.read<LanguageProvider>().l10n.t('cat_search_category'),
          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12.5),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded,
              color: active ? _accent : Colors.white24, size: 16),
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          suffixIcon: active
              ? GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 15))
              : null,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildFilterPanel(IptvProvider p) {
    final themes    = _availableFilters(_cats(p));
    final letters   = _availableLetters(_cats(p));
    final countries = _availableCountries(_cats(p));

    Widget chip(String label, bool selected, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? _accent.withOpacity(0.2) : const Color(0xFF1A1A26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _accent.withOpacity(0.6) : Colors.white.withOpacity(0.08),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: _accent.withOpacity(0.22), blurRadius: 8)]
                    : null,
              ),
              child: Text(label, style: GoogleFonts.inter(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
            ),
          ),
        );

    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: [
            Text(context.read<LanguageProvider>().l10n.t('cat_filter_by'), style: GoogleFonts.inter(
              color: Colors.white24, fontSize: 9,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            if (_hasActiveFilter)
              GestureDetector(
                onTap: () => setState(() { _activeFilter = ''; _activeAlpha = ''; _activeCountry = ''; }),
                child: Text(context.read<LanguageProvider>().l10n.t('cat_clear_all'), style: GoogleFonts.inter(
                  color: _accent.withOpacity(0.8), fontSize: 10,
                  fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            children: [
              ...themes.map((k) => chip(
                _kFilterLabels[k] ?? k, _activeFilter == k,
                () => setState(() => _activeFilter = _activeFilter == k ? '' : k),
              )),
              if (themes.isNotEmpty && countries.isNotEmpty)
                Container(width: 1, height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: Colors.white.withOpacity(0.1)),
              ...countries.take(10).map((c) => chip(
                '${c.flag} ${c.label}', _activeCountry == c.code,
                () => setState(() =>
                    _activeCountry = _activeCountry == c.code ? '' : c.code),
              )),
              if (letters.isNotEmpty)
                Container(width: 1, height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: Colors.white.withOpacity(0.1)),
              ...letters.map((l) => chip(
                l, _activeAlpha == l,
                () => setState(() => _activeAlpha = _activeAlpha == l ? '' : l),
              )),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildCatList(List<Map<String, dynamic>> cats, IptvProvider p,
      bool isTV, TVSizes sizes) {
    if (isTV) {
      return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, childAspectRatio: 1.3,
          crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          if (i >= cats.length) return const SizedBox.shrink();
          return _SubcatCard(
            rawName: cats[i]['name']?.toString() ?? '',
            accent: _accent, isTV: true, delay: 0,
            onTap: () => _openCatPortrait(ctx, cats[i], p),
          );
        },
      );
    }
    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: cats.length,
      itemBuilder: (ctx, i) {
        if (i >= cats.length) return const SizedBox.shrink();
        return _CatListItem(
          rawName: cats[i]['name']?.toString() ?? '',
          accent: _accent, delay: 0,
          onTap: () => _openCatPortrait(ctx, cats[i], p),
        );
      },
    );
  }

  Widget _buildDragList(List<Map<String, dynamic>> cats, IptvProvider p,
      bool isTV, TVSizes sizes) {
    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: cats.length,
      itemBuilder: (ctx, i) {
        final tile = _CatListItem(
          rawName: cats[i]['name']?.toString() ?? '',
          accent: _accent, delay: 0, isDragging: true, onTap: () {},
        );
        return LongPressDraggable<int>(
          data: i, hapticFeedbackOnStart: true,
          onDragUpdate: (d) => _scrollOnDrag(d.globalPosition),
          feedback: Material(color: Colors.transparent,
            child: SizedBox(width: MediaQuery.of(ctx).size.width - 32,
              child: Opacity(opacity: 0.9, child: tile))),
          childWhenDragging: Opacity(opacity: 0.2, child: tile),
          child: DragTarget<int>(
            onAcceptWithDetails: (d) {
              if (d.data == i) return;
              final list = List<Map<String, dynamic>>.from(_localCats!);
              final item = list.removeAt(d.data);
              list.insert(i, item);
              setState(() { _localCats = list; _cache = null; });
              HapticFeedback.selectionClick();
            },
            builder: (ctx, cands, _) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cands.isNotEmpty ? _accent : Colors.transparent, width: 1.5),
                color: cands.isNotEmpty ? _accent.withOpacity(0.06) : Colors.transparent,
              ),
              child: tile,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingOrEmpty(IptvProvider p, bool isTV) {
    if (p.isLoading) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2, color: _accent));
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppTheme.violet.withOpacity(0.4), blurRadius: 24),
              BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 48),
            ],
          ),
          child: Icon(widget.icon, color: Colors.white.withOpacity(0.85), size: 26),
        ),
        SizedBox(height: 16),
        Text(context.read<LanguageProvider>().l10n.t('cat_no_category'),
          style: GoogleFonts.rajdhani(
            color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
      ]).animate().fadeIn(),
    );
  }

  Widget _appBar(List<Map<String, dynamic>> cats, List<_CountryGroup> groups,
      IptvProvider p, bool inSub, bool isTV) {
    return SliverAppBar(
      pinned: true, floating: false,
      expandedHeight: widget.embedded ? 0 : (isTV ? 90 : 96),
      toolbarHeight: isTV ? 52 : kToolbarHeight,
      backgroundColor: Colors.transparent, elevation: 0,
      automaticallyImplyLeading: false,
      leading: widget.embedded ? null : IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: widget.embedded ? null : FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
        collapseMode: CollapseMode.pin,
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [_accent.withOpacity(0.08), AppTheme.background],
            ),
          ),
        ),
        title: _barTitle(false, isTV),
      ),
      title: widget.embedded ? _barTitle(false, isTV) : null,
      actions: [
        if (_isDragging)
          TextButton.icon(
            onPressed: () => _saveAndExitDrag(p),
            icon: Icon(Icons.check_rounded, color: _accent, size: 16),
            label: Text(context.read<LanguageProvider>().l10n.t('cat_done'),
              style: GoogleFonts.inter(color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
          )
        else ...[
          // Bouton filtre avec badge si actif
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _showFilters = !_showFilters),
              child: Stack(clipBehavior: Clip.none, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: (_showFilters || _hasActiveFilter)
                        ? _accent.withOpacity(0.18)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_showFilters || _hasActiveFilter)
                          ? _accent.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                    boxShadow: (_showFilters || _hasActiveFilter)
                        ? [BoxShadow(color: _accent.withOpacity(0.25), blurRadius: 8)]
                        : null,
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: (_showFilters || _hasActiveFilter)
                          ? _accent
                          : Colors.white38,
                      size: 16),
                ),
                // Badge point si filtre actif
                if (_hasActiveFilter)
                  Positioned(
                    top: 4, right: 4,
                    child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        gradient: AppTheme.gradientPrimary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: _accent.withOpacity(0.6), blurRadius: 4)],
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.swap_vert_rounded, color: Colors.white38, size: 18),
            tooltip: 'Réorganiser',
            onPressed: () => _enterDrag(p),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 8)],
            ),
            child: Text('${cats.length}',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          )),
        ),
      ],
    );
  }

  Widget _barTitle(bool inSub, bool isTV) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: isTV ? 24 : 20, height: isTV ? 24 : 20,
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 10)],
        ),
        child: Icon(widget.icon, color: Colors.white, size: isTV ? 13 : 11),
      ),
      const SizedBox(width: 8),
      Text(widget.title,
        style: GoogleFonts.rajdhani(
          color: Colors.white, fontSize: isTV ? 17 : 15,
          fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    ]);
  }

  Widget _rawGrid(List<Map<String, dynamic>> cats, IptvProvider p, bool isTV, TVSizes sizes) {
    // Portrait : liste verticale pleine largeur — bien plus lisible que des petites boxes
    if (isTV) {
      // TV garde la grille compacte
      const cols = 4;
      const pad  = 20.0;
      const gap  = 10.0;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(pad, 8, pad, 32),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols, childAspectRatio: 1.3,
            crossAxisSpacing: gap, mainAxisSpacing: gap,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              if (i >= cats.length) return const SizedBox.shrink();
              final cat  = cats[i];
              final name = cat['name']?.toString() ?? '';
              return _SubcatCard(
                rawName: name, accent: _accent, isTV: true, delay: i * 15,
                onTap: () => _openCatPortrait(ctx, cat, p),
              );
            },
            childCount: cats.length,
          ),
        ),
      );
    }
    // Mobile portrait : liste de rows premium
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            if (i >= cats.length) return const SizedBox.shrink();
            final cat   = cats[i];
            final name  = cat['name']?.toString() ?? '';
            return _CatListItem(
              rawName: name,
              accent: _accent,
              delay: i * 20,
              onTap: () => _openCatPortrait(ctx, cat, p),
            );
          },
          childCount: cats.length,
        ),
      ),
    );
  }

  Widget _dragGrid(List<Map<String, dynamic>> cats, IptvProvider p, bool isTV, TVSizes sizes) {
    final pad = isTV ? 20.0 : 16.0;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
      sliver: SliverToBoxAdapter(
        child: isTV
            // TV : grille drag classique
            ? GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, childAspectRatio: 1.3,
                  crossAxisSpacing: 8, mainAxisSpacing: 8,
                ),
                itemCount: cats.length,
                itemBuilder: (ctx, i) {
                  final cat  = cats[i];
                  final name = cat['name']?.toString() ?? '';
                  final tile = _SubcatCard(
                    rawName: name, accent: _accent, isTV: true, delay: 0, onTap: () {},
                  );
                  return LongPressDraggable<int>(
                    data: i, hapticFeedbackOnStart: true,
                    onDragUpdate: (d) => _scrollOnDrag(d.globalPosition),
                    feedback: Material(color: Colors.transparent,
                      child: SizedBox(width: 110, height: 90,
                        child: Opacity(opacity: 0.85, child: tile))),
                    childWhenDragging: Opacity(opacity: 0.2, child: tile),
                    child: DragTarget<int>(
                      onAcceptWithDetails: (d) {
                        if (d.data == i) return;
                        final list = List<Map<String, dynamic>>.from(_localCats!);
                        final item = list.removeAt(d.data);
                        list.insert(i, item);
                        setState(() { _localCats = list; _cache = null; });
                        HapticFeedback.selectionClick();
                      },
                      builder: (ctx, cands, _) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cands.isNotEmpty ? _accent : Colors.transparent, width: 2)),
                        child: tile,
                      ),
                    ),
                  );
                },
              )
            // Mobile : liste drag rows
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cats.length,
                itemBuilder: (ctx, i) {
                  final cat  = cats[i];
                  final name = cat['name']?.toString() ?? '';
                  final tile = _CatListItem(
                    rawName: name, accent: _accent, delay: 0,
                    isDragging: true, onTap: () {},
                  );
                  return LongPressDraggable<int>(
                    data: i, hapticFeedbackOnStart: true,
                    onDragUpdate: (d) => _scrollOnDrag(d.globalPosition),
                    feedback: Material(color: Colors.transparent,
                      child: SizedBox(width: MediaQuery.of(ctx).size.width - 32,
                        child: Opacity(opacity: 0.9, child: tile))),
                    childWhenDragging: Opacity(opacity: 0.2, child: tile),
                    child: DragTarget<int>(
                      onAcceptWithDetails: (d) {
                        if (d.data == i) return;
                        final list = List<Map<String, dynamic>>.from(_localCats!);
                        final item = list.removeAt(d.data);
                        list.insert(i, item);
                        setState(() { _localCats = list; _cache = null; });
                        HapticFeedback.selectionClick();
                      },
                      builder: (ctx, cands, _) => AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cands.isNotEmpty ? _accent : Colors.transparent, width: 1.5),
                          color: cands.isNotEmpty ? _accent.withOpacity(0.06) : Colors.transparent,
                        ),
                        child: tile,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR CAT ITEM — v9
// ─────────────────────────────────────────────────────────────────────────────
class _SidebarCatItem extends StatefulWidget {
  final String name; final IconData icon; final Color color;
  final bool active, isTV; final int delay; final VoidCallback onTap;
  const _SidebarCatItem({
    required this.name, required this.icon, required this.color,
    required this.active, required this.isTV, required this.delay, required this.onTap,
  });
  @override State<_SidebarCatItem> createState() => _SidebarCatItemState();
}

class _SidebarCatItemState extends State<_SidebarCatItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            gradient: active ? LinearGradient(
              colors: [widget.color.withOpacity(0.18), widget.color.withOpacity(0.06)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ) : null,
            color: active ? null : _hovered ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? widget.color.withOpacity(0.35) : Colors.transparent),
            boxShadow: active
                ? [BoxShadow(color: widget.color.withOpacity(0.12), blurRadius: 14)]
                : null,
          ),
          child: IntrinsicHeight(
            child: Row(children: [
              // Left accent 3px glow
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 3,
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [AppTheme.violet, AppTheme.red],
                  ) : null,
                  color: active ? null : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10), bottomLeft: Radius.circular(10)),
                  boxShadow: active
                      ? [BoxShadow(color: AppTheme.violet.withOpacity(0.6), blurRadius: 6)]
                      : null,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: widget.isTV ? 10 : 8),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: widget.isTV ? 26 : 22, height: widget.isTV ? 26 : 22,
                      decoration: BoxDecoration(
                        gradient: active ? AppTheme.gradientPrimary : null,
                        color: active ? null
                            : _hovered ? Colors.white.withOpacity(0.07) : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: active
                            ? [BoxShadow(color: AppTheme.violet.withOpacity(0.4), blurRadius: 8)]
                            : null,
                      ),
                      child: Icon(widget.icon,
                          size: widget.isTV ? 13 : 11,
                          color: active ? Colors.white : Colors.white38),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.name,
                        style: GoogleFonts.inter(
                          color: active ? Colors.white : Colors.white54,
                          fontSize: widget.isTV ? 12 : 11,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (active)
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          gradient: AppTheme.gradientPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                              color: AppTheme.violet.withOpacity(0.7), blurRadius: 6)],
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    // [PERF] Suppression de .animate() avec delay par item.
    // Sur 300+ catégories = 300+ AnimationControllers → lag garanti.
    // Le fade de la sidebar entière est géré par AnimatedSwitcher parent.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAT LIST ITEM — portrait mobile : row pleine largeur premium
// Remplace les petites boxes illisibles de la grille 3 colonnes
// ─────────────────────────────────────────────────────────────────────────────
class _CatListItem extends StatefulWidget {
  final String rawName;
  final Color accent;
  final int delay;
  final bool isDragging;
  final VoidCallback onTap;

  const _CatListItem({
    required this.rawName,
    required this.accent,
    required this.delay,
    required this.onTap,
    this.isDragging = false,
  });

  @override
  State<_CatListItem> createState() => _CatListItemState();
}

class _CatListItemState extends State<_CatListItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cleaned = _cleanName(widget.rawName);
    final icon    = _themeIcon(cleaned);
    final color   = _themeColor(cleaned, widget.accent);

    // Couleur uniforme = accent du tab uniquement (pas de _themeColor par catégorie)
    // Pas de delay staggeré → pas de flash noir au scroll rapide
    final c = widget.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              // Fond très subtil — couleur uniforme, pas de per-catégorie
              color: _pressed
                  ? Colors.white.withOpacity(0.07)
                  : const Color(0xFF13131A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _pressed
                    ? c.withOpacity(0.35)
                    : Colors.white.withOpacity(0.07),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.25),
                    blurRadius: 4, offset: const Offset(0, 1))
              ],
            ),
            child: Row(children: [
              // Icône dans container uniforme
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: c.withOpacity(0.85), size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(cleaned,
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              if (widget.isDragging)
                Icon(Icons.drag_handle_rounded,
                    color: Colors.white.withOpacity(0.2), size: 18)
              else
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.2), size: 18),
            ]),
          ),
        ),
      ),
    );
    // [PERF] Suppression de .animate().fadeIn() — un controller par item de liste = lag au scroll
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT PANEL — v9
// ─────────────────────────────────────────────────────────────────────────────
class _ContentPanel extends StatefulWidget {
  final int tabIndex;
  final String categoryId, categoryName;
  final Color accent;
  final bool isTV;
  final TVSizes sizes;

  const _ContentPanel({
    super.key,
    required this.tabIndex, required this.categoryId, required this.categoryName,
    required this.accent, required this.isTV, required this.sizes,
  });

  @override State<_ContentPanel> createState() => _ContentPanelState();
}

class _ContentPanelState extends State<_ContentPanel> {
  // Recherche in-catégorie
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<IptvProvider>().filterByCategory(widget.categoryId);
    });
  }

  @override
  void didUpdateWidget(_ContentPanel old) {
    super.didUpdateWidget(old);
    if (old.categoryId != widget.categoryId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<IptvProvider>().filterByCategory(widget.categoryId);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {});
    super.dispose();
  }

  PageRoute _route(Widget p) => PageRouteBuilder(
    pageBuilder: (_, a, __) => p,
    transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    transitionDuration: const Duration(milliseconds: 240),
  );

  Widget _buildSearchField() {
    final active = _searchQuery.isNotEmpty;
    final accent = widget.accent;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.07),
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 8)]
            : null,
      ),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
        decoration: InputDecoration(
          hintText: context.read<LanguageProvider>().l10n.t('cat_search_in'),
          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded,
              color: active ? accent : Colors.white24, size: 15),
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          suffixIcon: active
              ? GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                  child: const Icon(Icons.close_rounded, color: Colors.white38, size: 15))
              : null,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<IptvProvider, (bool, int, String)>(
      selector: (_, p) => (
        p.isLoading,
        p.filteredContent.length,
        p.filteredContent.isEmpty ? '' : p.filteredContent.first.categoryId,
      ),
      builder: (context, _, __) {
        final p      = context.read<IptvProvider>();
        final isLive = widget.tabIndex == 1;
        final isLand = MediaQuery.of(context).orientation == Orientation.landscape;
        final cols   = widget.isTV
            ? (isLive ? 4 : 5)
            : (isLand ? (isLive ? 3 : 4) : 3);

        // Filtrage local par recherche in-catégorie
        final items = _searchQuery.isEmpty
            ? p.filteredContent
            : p.filteredContent.where((c) =>
                c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

        return Column(children: [
          // Header avec left accent couleur de l'accent de tab
          Container(
            height: widget.isTV ? 54 : 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF0C0B18), Color(0x00090914)],
              ),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [widget.accent, AppTheme.violet],
                    ),
                    boxShadow: [BoxShadow(
                        color: widget.accent.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.categoryName,
                    style: GoogleFonts.rajdhani(
                      color: Colors.white,
                      fontSize: widget.isTV ? 16 : 14,
                      fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientHorizontal,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(
                          color: AppTheme.violet.withOpacity(0.35), blurRadius: 8)],
                    ),
                    child: Text('${p.filteredContent.length}',
                      style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ),
          // Barre recherche in-catégorie
          Container(
            color: AppTheme.background,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _buildSearchField(),
          ),

          Expanded(
            child: p.isLoading
                ? GridView.builder(
                    padding: EdgeInsets.all(widget.sizes.bodyPadding),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: isLive ? 1.9 : 0.65,
                      crossAxisSpacing: widget.sizes.cardSpacing,
                      mainAxisSpacing: widget.sizes.cardSpacing,
                    ),
                    itemCount: 12,
                    itemBuilder: (_, i) => _Skeleton(isLive: isLive, delay: i * 35),
                  )
                : items.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            gradient: AppTheme.gradientPrimary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(
                                color: AppTheme.violet.withOpacity(0.3), blurRadius: 20)],
                          ),
                          child: Icon(isLive ? Icons.live_tv_rounded : Icons.movie_rounded,
                              color: Colors.white.withOpacity(0.8), size: 24),
                        ),
                        const SizedBox(height: 14),
                        Text(_searchQuery.isEmpty ? 'Aucun contenu' : 'Aucun résultat',
                          style: GoogleFonts.rajdhani(
                            color: AppTheme.textSecondary,
                            fontSize: 14, fontWeight: FontWeight.w600)),
                      ]).animate().fadeIn())
                    : GridView.builder(
                        padding: EdgeInsets.all(widget.sizes.bodyPadding),
                        // [PERF] cacheExtent réduit : 1x hauteur écran suffit
                        // 3x causait le chargement de 3x plus d'images que nécessaire
                        cacheExtent: MediaQuery.sizeOf(context).height,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: isLive ? 1.9 : 0.65,
                          crossAxisSpacing: widget.sizes.cardSpacing,
                          mainAxisSpacing: widget.sizes.cardSpacing,
                        ),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          if (i >= items.length) return const SizedBox.shrink();
                          final item = items[i];
                          // [PERF] Plus de .animate() par card — créait N AnimationControllers
                          // simultanés (1 par card visible + cacheExtent) → freeze garanti.
                          // Remplacement : fade simple uniquement sur les 12 premiers items
                          // via TweenAnimationBuilder (1 seul controller temporaire, auto-disposé).
                          final card = RepaintBoundary(
                            child: ChannelCard(
                              channel: item, isWide: isLive, tabIndex: widget.tabIndex,
                              isFavorite: p.isFavorite(item.streamId, widget.tabIndex),
                              onFavoriteTap: () => p.toggleFavorite(item, widget.tabIndex),
                              onTap: () {
                                if (isLive) {
                                  p.setCurrentTab(1);
                                  final channels = p.filteredContent.isNotEmpty
                                      ? p.filteredContent : p.allLive;
                                  final idx = channels.indexWhere(
                                      (c) => c.streamId == item.streamId);
                                  Navigator.push(ctx, _route(PlayerScreen(
                                    streamUrl: p.getStreamUrl(item),
                                    title: item.name, streamIcon: item.streamIcon,
                                    streamId: item.streamId, tabIndex: 1,
                                    liveChannels: channels,
                                    channelIndex: idx >= 0 ? idx : 0,
                                  )));
                                } else {
                                  Navigator.push(ctx, _route(
                                      DetailsScreen(item: item, sourceTabIndex: widget.tabIndex)));
                                }
                              },
                            ),
                          );
                          // Fade uniquement sur les 12 premiers (above-the-fold)
                          if (i < 12) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 180 + i * 12),
                              curve: Curves.easeOut,
                              builder: (_, v, child) => Opacity(opacity: v, child: child),
                              child: card,
                            );
                          }
                          return card;
                        },
                      ),
          ),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COUNTRY TILE — v9
// ─────────────────────────────────────────────────────────────────────────────
class _CountryTile extends StatefulWidget {
  final _CountryGroup group; final Color accent;
  final bool isTV, dragging, showCount; final int delay; final VoidCallback onTap;
  const _CountryTile({
    required this.group, required this.accent, required this.isTV,
    required this.delay, required this.onTap,
    this.dragging = false, this.showCount = true,
  });
  @override State<_CountryTile> createState() => _CountryTileState();
}

class _CountryTileState extends State<_CountryTile> {
  bool _f = false, _p = false;
  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Focus(
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap(); return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _p = true),
        onTapUp:   (_) => setState(() => _p = false),
        onTapCancel: ()=> setState(() => _p = false),
        child: AnimatedScale(
          scale: _p ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _f ? LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [widget.accent.withOpacity(0.18), widget.accent.withOpacity(0.07),
                    const Color(0xFF0D0C17)],
              ) : const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF11101C), Color(0xFF0D0C17)],
              ),
              border: Border.all(
                color: _f ? widget.accent.withOpacity(0.55) : Colors.white.withOpacity(0.07),
                width: _f ? 1.5 : 1,
              ),
              boxShadow: _f
                  ? [BoxShadow(color: widget.accent.withOpacity(0.28), blurRadius: 20, spreadRadius: 1)]
                  : [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.isTV ? 14 : 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.flag, style: TextStyle(fontSize: widget.isTV ? 32 : 26, height: 1.1)),
                const Spacer(),
                Text(g.label,
                  style: GoogleFonts.inter(
                    color: Colors.white, fontSize: widget.isTV ? 12 : 10.5,
                    fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.showCount) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: AppTheme.gradientHorizontal,
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 4)],
                      ),
                      child: Text('${g.count}',
                        style: GoogleFonts.inter(color: Colors.white,
                            fontSize: widget.isTV ? 9 : 8, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: Text(g.count > 1 ? 'catégories' : 'catégorie',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary,
                          fontSize: widget.isTV ? 8 : 7.5),
                      overflow: TextOverflow.ellipsis)),
                  ]),
                ],
                if (widget.dragging)
                  Align(alignment: Alignment.centerRight,
                    child: Icon(Icons.drag_indicator_rounded, color: Colors.white24, size: 13)),
              ]),
            ),
          ),
        ),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: widget.delay), duration: 250.ms)
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
            delay: Duration(milliseconds: widget.delay),
            duration: 280.ms, curve: Curves.easeOutCubic);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBCAT CARD — v9 double glow icône + border colorée active
// ─────────────────────────────────────────────────────────────────────────────
class _SubcatCard extends StatefulWidget {
  final String rawName; final Color accent;
  final bool isTV; final int delay; final int? channelCount;
  final VoidCallback onTap;
  const _SubcatCard({
    required this.rawName, required this.accent, required this.isTV,
    required this.delay, required this.onTap, this.channelCount,
  });
  @override State<_SubcatCard> createState() => _SubcatCardState();
}

class _SubcatCardState extends State<_SubcatCard> {
  bool _f = false, _p = false;
  @override
  Widget build(BuildContext context) {
    final cleaned = _cleanName(widget.rawName);
    final icon    = _themeIcon(cleaned);
    final color   = _themeColor(cleaned, widget.accent);

    return Focus(
      onFocusChange: (v) => setState(() => _f = v),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap(); return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _p = true),
        onTapUp:   (_) => setState(() => _p = false),
        onTapCancel: ()=> setState(() => _p = false),
        child: AnimatedScale(
          scale: _p ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: AspectRatio(
            aspectRatio: 1.4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _f
                    ? LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [color.withOpacity(0.24), color.withOpacity(0.09), const Color(0xFF0D0C18)])
                    : LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [color.withOpacity(0.11), color.withOpacity(0.04), const Color(0xFF0C0B17)]),
                border: Border.all(
                  color: _f ? color.withOpacity(0.70) : color.withOpacity(0.20),
                  width: _f ? 1.5 : 1,
                ),
                boxShadow: _f
                    ? [BoxShadow(color: color.withOpacity(0.38), blurRadius: 24, spreadRadius: 1)]
                    : [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Stack(children: [
                Padding(
                  padding: EdgeInsets.all(widget.isTV ? 12 : 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: widget.isTV ? 44 : 36,
                          height: widget.isTV ? 44 : 36,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [
                                color.withOpacity(_f ? 0.38 : 0.22),
                                color.withOpacity(_f ? 0.18 : 0.10),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(_f ? 0.65 : 0.25),
                                blurRadius: _f ? 22 : 10, spreadRadius: _f ? 2 : 0),
                              if (_f) BoxShadow(
                                color: color.withOpacity(0.20), blurRadius: 40, spreadRadius: 4),
                            ],
                          ),
                          child: Icon(icon, color: color, size: widget.isTV ? 22 : 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(cleaned,
                      style: GoogleFonts.inter(
                        color: _f ? Colors.white : Colors.white.withOpacity(0.80),
                        fontSize: widget.isTV ? 11 : 9.5,
                        fontWeight: _f ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: -0.2),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (widget.channelCount != null && widget.channelCount! > 0)
                  Positioned(
                    bottom: 6, right: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withOpacity(0.9), color.withOpacity(0.6)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 6)],
                      ),
                      child: Text('${widget.channelCount}',
                        style: GoogleFonts.inter(color: Colors.white,
                            fontSize: widget.isTV ? 8 : 7, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: widget.delay), duration: 250.ms)
        .scale(begin: const Offset(0.88, 0.88), end: const Offset(1, 1),
            delay: Duration(milliseconds: widget.delay),
            duration: 280.ms, curve: Curves.easeOutCubic);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT SCREEN PORTRAIT — v9
// ─────────────────────────────────────────────────────────────────────────────
class _ContentScreenPortrait extends StatefulWidget {
  final int tabIndex;
  final String categoryId, categoryName;
  const _ContentScreenPortrait({
    required this.tabIndex, required this.categoryId, required this.categoryName});
  @override State<_ContentScreenPortrait> createState() => _ContentScreenPortraitState();
}

class _ContentScreenPortraitState extends State<_ContentScreenPortrait> {
  Color get _accent => switch (widget.tabIndex) {
    1 => AppTheme.catLiveAccent,
    2 => AppTheme.catMoviesAccent,
    _ => AppTheme.catSeriesAccent,
  };

  // Recherche in-catégorie
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<IptvProvider>();
      if (p.currentTab != widget.tabIndex) {
        await p.loadTabContent(widget.tabIndex);
        if (!mounted) return;
      }
      p.filterByCategory(widget.categoryId);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<IptvProvider>().filterByCategory('0');
    });
    super.dispose();
  }

  PageRoute _route(Widget p) => PageRouteBuilder(
    pageBuilder: (_, a, __) => p,
    transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    transitionDuration: const Duration(milliseconds: 240),
  );

  @override
  Widget build(BuildContext context) {
    return Selector<IptvProvider, (bool, int)>(
      selector: (_, p) => (p.isLoading, p.filteredContent.length),
      builder: (context, _, __) {
        final p      = context.read<IptvProvider>();
        final isLive = widget.tabIndex == 1;
        final sizes  = context.tvSizes;
        final cols   = isLive ? 2 : 3;

        // Filtrage local par recherche in-catégorie
        final items = _searchQuery.isEmpty
            ? p.filteredContent
            : p.filteredContent.where((c) =>
                c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

        return TvBackHandler(
          onBack: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: AppTheme.background,
            body: CustomScrollView(slivers: [
              SliverAppBar(
                pinned: true, floating: true,
                backgroundColor: AppTheme.background, elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
                title: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 4, height: 18,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [_accent, AppTheme.violet],
                      ),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [BoxShadow(color: _accent.withOpacity(0.6), blurRadius: 8)],
                    ),
                  ),
                  Flexible(child: Text(widget.categoryName,
                    style: GoogleFonts.rajdhani(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    overflow: TextOverflow.ellipsis)),
                ]),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: AppTheme.gradientHorizontal,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 8)],
                      ),
                      child: Text('${items.length}',
                        style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    )),
                  ),
                ],
              ),
              // Barre de recherche in-catégorie sticky
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchBarDelegate(
                  searchCtrl: _searchCtrl,
                  searchQuery: _searchQuery,
                  accent: _accent,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  onClear: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                ),
              ),

              if (p.isLoading)
                SliverPadding(
                  padding: EdgeInsets.all(sizes.bodyPadding),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: isLive ? 1.9 : 0.65,
                      crossAxisSpacing: sizes.cardSpacing,
                      mainAxisSpacing: sizes.cardSpacing,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _Skeleton(isLive: isLive, delay: i * 35), childCount: 12),
                  ))
              else if (items.isEmpty)
                SliverFillRemaining(
                  child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        gradient: AppTheme.gradientPrimary, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 20)],
                      ),
                      child: Icon(isLive ? Icons.live_tv_rounded : Icons.movie_rounded,
                          color: Colors.white.withOpacity(0.8), size: 24),
                    ),
                    const SizedBox(height: 14),
                    Text(_searchQuery.isEmpty ? 'Aucun contenu' : 'Aucun résultat',
                      style: GoogleFonts.rajdhani(
                        color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ]).animate().fadeIn()),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.all(sizes.bodyPadding),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: isLive ? 1.9 : 0.65,
                      crossAxisSpacing: sizes.cardSpacing,
                      mainAxisSpacing: sizes.cardSpacing,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        if (i >= items.length) return const SizedBox.shrink();
                        final item = items[i];
                        return RepaintBoundary(
                          child: ChannelCard(
                            channel: item, isWide: isLive, tabIndex: widget.tabIndex,
                            isFavorite: p.isFavorite(item.streamId, widget.tabIndex),
                            onFavoriteTap: () => p.toggleFavorite(item, widget.tabIndex),
                            onTap: () {
                              if (isLive) {
                                p.setCurrentTab(1);
                                final channels = p.filteredContent.isNotEmpty
                                    ? p.filteredContent : p.allLive;
                                final idx = channels.indexWhere(
                                    (c) => c.streamId == item.streamId);
                                Navigator.push(ctx, _route(PlayerScreen(
                                  streamUrl: p.getStreamUrl(item),
                                  title: item.name, streamIcon: item.streamIcon,
                                  streamId: item.streamId, tabIndex: 1,
                                  liveChannels: channels,
                                  channelIndex: idx >= 0 ? idx : 0,
                                )));
                              } else {
                                Navigator.push(ctx, _route(
                                    DetailsScreen(item: item, sourceTabIndex: widget.tabIndex)));
                              }
                            },
                          ).animate()
                              .fadeIn(delay: Duration(milliseconds: i * 22), duration: 220.ms)
                              .scale(begin: const Offset(0.94, 0.94), end: const Offset(1, 1),
                                  delay: Duration(milliseconds: i * 22),
                                  duration: 240.ms, curve: Curves.easeOutCubic),
                        );
                      },
                      childCount: items.length,
                    ),
                  )),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH BAR DELEGATE — barre recherche seule (utilisée dans content screen)
// ─────────────────────────────────────────────────────────────────────────────
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final Color accent;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBarDelegate({
    required this.searchCtrl,
    required this.searchQuery,
    required this.accent,
    required this.onChanged,
    required this.onClear,
  });

  @override double get minExtent => 52;
  @override double get maxExtent => 52;
  @override bool shouldRebuild(_SearchBarDelegate old) =>
      old.searchQuery != searchQuery;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final active = searchQuery.isNotEmpty;
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF13131A),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? accent.withOpacity(0.45) : Colors.white.withOpacity(0.08),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 10)]
              : null,
        ),
        child: TextField(
          controller: searchCtrl,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: context.read<LanguageProvider>().l10n.t('search_hint'),
            hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search_rounded,
                color: active ? accent : Colors.white24, size: 17),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            suffixIcon: active
                ? GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16))
                : null,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH + FILTER DELEGATE — recherche + chips thème sticky
// Utilisé dans le portrait catégories uniquement
// ─────────────────────────────────────────────────────────────────────────────
class _SearchFilterDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final String activeFilter;
  final String activeAlpha;
  final List<String> availableFilters;
  final List<String> availableLetters;
  final Map<String, String> filterLabels;
  final Color accent;
  final bool showFilters;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final ValueChanged<String> onFilterTap;
  final ValueChanged<String> onAlphaTap;
  final VoidCallback onClearAll;

  const _SearchFilterDelegate({
    required this.searchCtrl,
    required this.searchQuery,
    required this.activeFilter,
    required this.activeAlpha,
    required this.availableFilters,
    required this.availableLetters,
    required this.filterLabels,
    required this.accent,
    required this.showFilters,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onFilterTap,
    required this.onAlphaTap,
    required this.onClearAll,
  });

  bool get _hasActiveFilter => activeFilter.isNotEmpty || activeAlpha.isNotEmpty;

  // Hauteur : search (52) + panel filtres si visible (thèmes 36 + séparateur 1 + alpha 36 + padding 10)
  // [FIX] minExtent/maxExtent TOUJOURS fixes — SliverPersistentHeader pinned
  // ne supporte pas les extents dynamiques → parentDataDirty assertion crash.
  // On fixe à la hauteur max et on utilise AnimatedContainer intérieur pour collapse.
  static const double _kSearchH = 52.0;
  static const double _kPanelH  = 83.0;
  @override double get minExtent => _kSearchH + _kPanelH;
  @override double get maxExtent => _kSearchH + _kPanelH;

  @override
  bool shouldRebuild(_SearchFilterDelegate old) =>
      old.searchQuery   != searchQuery   ||
      old.activeFilter  != activeFilter  ||
      old.activeAlpha   != activeAlpha   ||
      old.showFilters   != showFilters   ||
      old.availableFilters.length != availableFilters.length ||
      old.availableLetters.length != availableLetters.length;

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.2) : const Color(0xFF1A1A26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? accent.withOpacity(0.6) : Colors.white.withOpacity(0.08),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: accent.withOpacity(0.22), blurRadius: 8)]
                : null,
          ),
          child: Text(label,
            style: GoogleFonts.inter(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final searchActive = searchQuery.isNotEmpty;
    return Container(
      color: AppTheme.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Barre de recherche ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF13131A),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: searchActive
                      ? accent.withOpacity(0.45)
                      : Colors.white.withOpacity(0.08),
                  width: searchActive ? 1.5 : 1,
                ),
                boxShadow: searchActive
                    ? [BoxShadow(color: accent.withOpacity(0.15), blurRadius: 10)]
                    : null,
              ),
              child: TextField(
                controller: searchCtrl,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.read<LanguageProvider>().l10n.t('cat_search_category'),
                  hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12.5),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search_rounded,
                      color: searchActive ? accent : Colors.white24, size: 16),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  suffixIcon: searchActive
                      ? GestureDetector(
                          onTap: onSearchClear,
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white38, size: 15))
                      : null,
                ),
                onChanged: onSearchChanged,
              ),
            ),
          ),

          // ── Panel filtres — AnimatedContainer pour éviter le crash extent dynamique
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: showFilters ? _kPanelH : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: Container(
              height: _kPanelH,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row header : label + bouton tout effacer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 7, 14, 4),
                    child: Row(children: [
                      Text(context.read<LanguageProvider>().l10n.t('cat_filter_by'),
                        style: GoogleFonts.inter(
                          color: Colors.white24, fontSize: 9,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                      const Spacer(),
                      if (_hasActiveFilter)
                        GestureDetector(
                          onTap: onClearAll,
                          child: Text(context.read<LanguageProvider>().l10n.t('cat_clear_all'),
                            style: GoogleFonts.inter(
                              color: accent.withOpacity(0.8), fontSize: 10,
                              fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                  // Chips thèmes + lettres dans une seule row scrollable
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      children: [
                        // Thèmes
                        ...availableFilters.map((key) => _chip(
                          filterLabels[key] ?? key,
                          activeFilter == key,
                          () => onFilterTap(key),
                        )),
                        // Séparateur vertical si les deux types existent
                        if (availableFilters.isNotEmpty && availableLetters.isNotEmpty)
                          Container(
                            width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.white.withOpacity(0.1),
                          ),
                        // Lettres A-Z
                        ...availableLetters.map((l) => _chip(
                          l,
                          activeAlpha == l,
                          () => onAlphaTap(l),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ), // AnimatedContainer
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SKELETON — v9 shimmer contraste élevé
// ─────────────────────────────────────────────────────────────────────────────
class _Skeleton extends StatelessWidget {
  final bool isLive; final int delay;
  const _Skeleton({required this.isLive, required this.delay});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      // [PERF] Shimmer statique — plus de AnimationController par skeleton
      // L'ancien code créait 12 controllers simultanés pour 12 skeletons
      color: const Color(0xFF11101C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
  );
}