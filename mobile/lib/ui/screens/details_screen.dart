// lib/ui/screens/details_screen.dart
//
// ARICH IPTV — Details Screen v3
//
// NOUVEAUTÉS v3 (redesign visuel AAA — logique 100% préservée) :
// [DESIGN] Poster column : border gradient pill + double glow shadow
// [DESIGN] Portrait header : gradient 4-stops cinématique + vignette latérale
// [DESIGN] Section headers : barre accent gauche + glow + icône gradient pill
// [DESIGN] Bouton "Regarder" : double boxShadow (blurRadius 24 + 48) + glow animé
// [DESIGN] Bouton "Ma liste" : border gradient actif + icon gradient
// [DESIGN] Progression reprise : track gradient violet→red + glow
// [DESIGN] Episode tiles : card dark premium + left accent gradient + play btn gradient
// [DESIGN] Sélecteur saisons : pill gradient actif + count badge violet
// [DESIGN] Cast card : gradient dark + left border accent + rows redesignées
// [DESIGN] Meta badges : icône tintée + border colorée + padding premium
// [DESIGN] Rating badge TMDB : glow gold + star gradient
// [DESIGN] Circle buttons : glassmorphism BackdropFilter
// [DESIGN] Type badge : gradient pill avec letterSpacing
// [DESIGN] Skeleton shimmer amélioré
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../../core/theme.dart';
import '../../models/channel.dart';
import '../../providers/iptv_provider.dart';
import 'player_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/tmdb_service.dart';
import '../../services/download_service.dart';
import 'downloads_screen.dart';
import '../widgets/focusable_ink.dart';

class DetailsScreen extends StatefulWidget {
  final Channel item;
  final int sourceTabIndex;

  const DetailsScreen({
    super.key,
    required this.item,
    required this.sourceTabIndex,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen>
    with SingleTickerProviderStateMixin {
  String _selectedSeason = '';
  Map<String, dynamic> _vodInfo = {};
  bool _loadingVodInfo = false;
  bool _synopsisExpanded = false;

  String? _tmdbPosterUrl;
  String? _tmdbBackdropUrl;
  double? _tmdbRating;
  String? _tmdbOverview;
  List<String> _tmdbGenres  = [];
  int?    _tmdbYear;
  bool    _tmdbLoading = false;

  final ScrollController _scrollController = ScrollController();
  late final AnimationController _seasonAnim;

  bool get _isSeries => widget.sourceTabIndex == 3;
  bool get _isMovie  => widget.sourceTabIndex == 2;

  @override
  void initState() {
    super.initState();
    _seasonAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isSeries) {
        context.read<IptvProvider>().fetchSeriesDetails(widget.item.streamId);
      } else if (_isMovie) {
        _fetchVodInfo();
      }
      _fetchTmdb();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _seasonAnim.dispose();
    super.dispose();
  }

  Future<void> _fetchVodInfo() async {
    setState(() => _loadingVodInfo = true);
    try {
      final data = await context.read<IptvProvider>().api
          .getVodInfo(widget.item.streamId);
      if (mounted) {
        setState(() {
          _vodInfo = (data['info'] as Map<String, dynamic>?) ?? {};
          _loadingVodInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVodInfo = false);
    }
  }

  Future<void> _fetchTmdb() async {
    final title = widget.item.name;
    if (title.isEmpty) return;
    setState(() => _tmdbLoading = true);
    try {
      await TmdbService.init();
      final posterUrl = await TmdbService.getPoster(title, tabIndex: widget.sourceTabIndex);
      final details = await TmdbService.getDetails(title, tabIndex: widget.sourceTabIndex);
      if (!mounted) return;
      setState(() {
        _tmdbPosterUrl = posterUrl;
        _tmdbLoading   = false;
        if (details != null) {
          _tmdbRating   = details['vote_average'] != null
              ? (details['vote_average'] as num).toDouble() : null;
          _tmdbOverview = details['overview'] as String?;
          _tmdbYear     = _parseYear(details['release_date'] as String?
              ?? details['first_air_date'] as String?);
          _tmdbBackdropUrl = details['backdrop_path'] != null
              ? 'https://image.tmdb.org/t/p/w780${details['backdrop_path']}' : null;
          final genreList = details['genres'] as List?;
          if (genreList != null) {
            _tmdbGenres = genreList.map((g) => g['name'].toString()).take(3).toList();
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _tmdbLoading = false);
    }
  }

  int? _parseYear(String? dateStr) {
    if (dateStr == null || dateStr.length < 4) return null;
    return int.tryParse(dateStr.substring(0, 4));
  }

  Map<String, dynamic>? get _info {
    if (_isMovie) return _vodInfo.isNotEmpty ? _vodInfo : null;
    return context.read<IptvProvider>().currentSeriesInfo['info']
        as Map<String, dynamic>?;
  }

  String get _synopsis =>
      (_tmdbOverview?.isNotEmpty == true ? _tmdbOverview : null) ??
      _info?['plot']?.toString() ??
      _info?['description']?.toString() ??
      _info?['synopsis']?.toString() ??
      '';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        if (!_scrollController.hasClients) return KeyEventResult.ignored;
        const step = 180.0;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _scrollController.animateTo(
            (_scrollController.offset + step)
                .clamp(0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _scrollController.animateTo(
            (_scrollController.offset - step)
                .clamp(0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: isLandscape
            ? _buildLandscapeLayout(provider)
            : _buildPortraitLayout(provider),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LANDSCAPE — 2 colonnes
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLandscapeLayout(IptvProvider provider) {
    final isFav = provider.isFavorite(widget.item.streamId, widget.sourceTabIndex);
    final screenW = MediaQuery.of(context).size.width;
    final posterW = (screenW * 0.28).clamp(180.0, 280.0);

    return Row(children: [
      SizedBox(
        width: posterW,
        child: _buildPosterColumn(provider, isFav),
      ),
      // Séparateur subtil avec glow violet
      Container(
        width: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppTheme.violet.withOpacity(0.25),
              AppTheme.violet.withOpacity(0.25),
              Colors.transparent,
            ],
            stops: const [0.0, 0.2, 0.8, 1.0],
          ),
        ),
      ),
      Expanded(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleSection(isLandscape: true),
                    const SizedBox(height: 14),
                    _buildMetaRow(provider),
                    const SizedBox(height: 16),
                    if (_synopsis.isNotEmpty) _buildSynopsisWidget(),
                    if (_isMovie) ...[const SizedBox(height: 20), _buildCastSection()],
                    if (_isSeries) ...[
                      const SizedBox(height: 20),
                      _buildSeriesSection(provider, isLandscape: true),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PORTRAIT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPortraitLayout(IptvProvider provider) {
    final isFav = provider.isFavorite(widget.item.streamId, widget.sourceTabIndex);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          expandedHeight: 340,
          pinned: true,
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: _circleBtn(Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _circleBtn(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? AppTheme.gold : Colors.white,
                onTap: () => _toggleFav(provider),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(background: _buildPortraitHeader()),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitleSection(isLandscape: false),
                const SizedBox(height: 12),
                _buildMetaRow(provider),
                const SizedBox(height: 16),
                if (_synopsis.isNotEmpty) _buildSynopsisWidget(),
                if (_isMovie) ...[
                  const SizedBox(height: 20),
                  _buildCastSection(),
                  const SizedBox(height: 28),
                  _buildPlayButton(provider),
                ],
                if (_isSeries) ...[
                  const SizedBox(height: 20),
                  _buildSeriesSection(provider, isLandscape: false),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POSTER COLONNE (landscape)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPosterColumn(IptvProvider provider, bool isFav) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF09090F), Color(0xFF07070E)],
        ),
      ),
      child: SafeArea(
        bottom: false, // [FIX] bottom:true + maxH=0.52*screenH → overflow 9.4px
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _circleBtn(Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
              _circleBtn(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? AppTheme.gold : Colors.white,
                onTap: () => _toggleFav(provider),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // [v3] Poster avec double glow + border gradient
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LayoutBuilder(builder: (context, constraints) {
              final maxH = MediaQuery.of(context).size.height * 0.46;
              final posterH = (constraints.maxWidth * 3 / 2).clamp(0.0, maxH);
              return SizedBox(
                height: posterH,
                child: Stack(children: [
                  // Glow derrière le poster
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(color: AppTheme.violet.withOpacity(0.28),
                              blurRadius: 32, spreadRadius: 4),
                          BoxShadow(color: AppTheme.red.withOpacity(0.12),
                              blurRadius: 48, spreadRadius: 8),
                        ],
                      ),
                    ),
                  ),
                  // Border gradient pill container
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientPrimary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: _buildPosterImage(),
                    ),
                  ),
                ]),
              );
            }),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0),

          const SizedBox(height: 16),

          // Badges
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _typeBadge(),
              const SizedBox(width: 8),
              if (_info?['rating'] != null)
                _ratingBadge(_info!['rating'].toString()),
            ]),
          ),

          const Spacer(),

          // Bouton play compact en bas
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: _buildPlayButton(provider, compact: true),
          ),
        ]),
      ),
    );
  }

  Widget _buildPosterImage() {
    final url = _tmdbPosterUrl ?? (widget.item.streamIcon.isNotEmpty
        ? widget.item.streamIcon : null);
    if (url == null) {
      return _tmdbLoading ? _posterSkeleton() : _posterFallback();
    }
    return Stack(fit: StackFit.expand, children: [
      CachedNetworkImage(
        imageUrl: url, fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, __) => _posterSkeleton(),
        errorWidget: (_, __, ___) => _posterFallback(),
      ),
      if (_tmdbPosterUrl != null)
        Positioned(bottom: 8, right: 8, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, height: 5,
                decoration: const BoxDecoration(color: Color(0xFF01D277), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('TMDB', style: TextStyle(
                color: Colors.white54, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
        )),
    ]);
  }

  Widget _posterSkeleton() => Container(
    color: const Color(0xFF1A1A26),
    child: Center(child: SizedBox(width: 28, height: 28,
      child: CircularProgressIndicator(
          strokeWidth: 2, color: AppTheme.violet.withOpacity(0.5)))),
  );

  Widget _posterFallback() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          AppTheme.violet.withOpacity(0.35),
          AppTheme.red.withOpacity(0.2),
          AppTheme.surface,
        ],
      ),
    ),
    child: Center(child: Icon(
      _isSeries ? Icons.tv_rounded : Icons.movie_rounded,
      color: Colors.white.withOpacity(0.12), size: 48,
    )),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // PORTRAIT HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPortraitHeader() {
    return Stack(fit: StackFit.expand, children: [
      // Image backdrop
      (_tmdbBackdropUrl ?? (widget.item.streamIcon.isNotEmpty ? widget.item.streamIcon : null)) != null
          ? CachedNetworkImage(
              imageUrl: _tmdbBackdropUrl ?? widget.item.streamIcon,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              errorWidget: (_, __, ___) => Container(color: AppTheme.surface))
          : Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppTheme.violet.withOpacity(0.4), AppTheme.surface],
              ))),
      // [v3] Gradient top + bottom + vignetttes latérales
      DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.55), Colors.transparent],
            stops: const [0, 0.35],
          ))),
      DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [AppTheme.background, AppTheme.background.withOpacity(0.55), Colors.transparent],
            stops: const [0, 0.22, 0.65],
          ))),
      // Vignetttes latérales subtiles
      DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [AppTheme.background.withOpacity(0.35), Colors.transparent,
              Colors.transparent, AppTheme.background.withOpacity(0.35)],
            stops: const [0, 0.12, 0.88, 1.0],
          ))),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TITRE + BADGES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTitleSection({required bool isLandscape}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isLandscape) ...[
          Row(children: [
            _typeBadge(),
            const SizedBox(width: 8),
            if (_info?['rating'] != null) _ratingBadge(_info!['rating'].toString()),
          ]),
          const SizedBox(height: 10),
        ],
        Text(
          widget.item.name,
          style: TextStyle(
            fontSize: isLandscape ? 20 : 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // META ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetaRow(IptvProvider provider) {
    if (_loadingVodInfo) {
      return Row(children: [
        _skeletonBox(60, 22),
        const SizedBox(width: 8),
        _skeletonBox(80, 22),
      ]).animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 1200.ms, color: Colors.white.withOpacity(0.04));
    }

    final year = _tmdbYear?.toString()
        ?? _info?['releasedate']?.toString()
        ?? _info?['release_date']?.toString();
    final duration = _info?['duration']?.toString();
    final genres = _tmdbGenres.isNotEmpty
        ? _tmdbGenres
        : (_info?['genre']?.toString() ?? '').split(',')
            .map((s) => s.trim()).where((s) => s.isNotEmpty).take(3).toList();

    final items = <Widget>[];
    if (_tmdbRating != null && _tmdbRating! > 0) items.add(_tmdbRatingBadge(_tmdbRating!));
    if (year != null && year.isNotEmpty)
      items.add(_metaBadge(Icons.calendar_today_outlined,
          year.length > 4 ? year.substring(0, 4) : year));
    if (duration != null && duration.isNotEmpty)
      items.add(_metaBadge(Icons.schedule_outlined, duration));
    for (final g in genres.take(2))
      items.add(_metaBadge(Icons.local_movies_outlined, g, color: AppTheme.violet));

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 6, children: items)
        .animate().fadeIn(delay: 80.ms).slideY(begin: 0.06, end: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNOPSIS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSynopsisWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [v3] Section header avec barre accent gauche
        _sectionHeader('SYNOPSIS', Icons.notes_rounded),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: Text(
            _synopsis,
            style: TextStyle(
                color: AppTheme.textSecondary.withOpacity(0.85),
                fontSize: 13, height: 1.7),
            maxLines: _synopsisExpanded ? null : 3,
            overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        if (_synopsis.length > 160)
          FocusableInk(
            onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
            borderRadius: 8,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _synopsisExpanded ? 'Réduire' : 'Lire la suite',
                  style: TextStyle(
                    color: AppTheme.violet.withOpacity(0.9),
                    fontSize: 12, fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _synopsisExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.violet.withOpacity(0.8), size: 16,
                ),
              ]),
            ),
          ),
      ],
    ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CAST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCastSection() {
    if (_loadingVodInfo) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF11101C), Color(0xFF0D0C17)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: List.generate(2, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              _skeletonBox(13, 13, radius: 6),
              const SizedBox(width: 8),
              _skeletonBox(60, 10),
              const SizedBox(width: 8),
              Expanded(child: _skeletonBox(double.infinity, 10)),
            ]),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(delay: Duration(milliseconds: i * 150),
              duration: 1200.ms, color: Colors.white.withOpacity(0.04))),
        ),
      );
    }

    if (_vodInfo.isEmpty) return const SizedBox.shrink();

    final director = _vodInfo['director']?.toString() ?? '';
    final cast      = _vodInfo['cast']?.toString()     ?? '';
    final genre     = _vodInfo['genre']?.toString()    ?? '';

    if (director.isEmpty && cast.isEmpty && genre.isEmpty) return const SizedBox.shrink();

    // [v3] Card dark gradient + left accent border violet
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF12111E), Color(0xFF0E0D18)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          // Left accent violet
          Container(
            width: 3,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('ÉQUIPE', Icons.people_alt_rounded),
                  const SizedBox(height: 12),
                  if (genre.isNotEmpty)    _infoRow(Icons.local_movies_outlined, 'Genre', genre),
                  if (director.isNotEmpty) _infoRow(Icons.movie_creation_outlined, 'Réalisateur', director),
                  if (cast.isNotEmpty)     _infoRow(Icons.people_outline_rounded, 'Acteurs', cast),
                ],
              ),
            ),
          ),
        ]),
      ),
    ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOUTON PLAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlayButton(IptvProvider provider, {bool compact = false}) {
    final resumePos = _isMovie
        ? provider.getResumePosition(widget.item.streamId, widget.sourceTabIndex) : 0;
    final hasResume = resumePos > 10;
    final isFav     = provider.isFavorite(widget.item.streamId, widget.sourceTabIndex);
    final dlId      = '${widget.item.streamId}_${widget.sourceTabIndex}';

    return Consumer<DownloadService>(
      builder: (context, dlSvc, _) {
        final dlItem     = dlSvc.find(dlId);
        final downloaded = dlItem?.isCompleted ?? false;
        final dlActive   = dlItem?.isActive ?? false;
        final dlQueued   = dlItem?.status == DownloadStatus.queued;
        final dlProgress = dlItem?.progress ?? 0.0;
        final dlError    = dlItem?.status == DownloadStatus.error;

        return Column(children: [
          // ── Bouton principal ──
          FocusableInk(
            autofocus: true,
            borderRadius: 16,
            focusColor: AppTheme.violet,
            onTap: () {
              if (downloaded && dlItem?.localPath != null) {
                _navigateToPlayer('file://${dlItem!.localPath}');
                return;
              }
              provider.setCurrentTab(widget.sourceTabIndex);
              _navigateToPlayer(provider.getStreamUrl(widget.item));
            },
            child: Container(
              width: double.infinity,
              height: compact ? 46 : 54,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientHorizontal,
                borderRadius: BorderRadius.circular(compact ? 12 : 16),
                boxShadow: [
                  BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 6)),
                  BoxShadow(color: AppTheme.violet.withOpacity(0.18), blurRadius: 48, spreadRadius: 2),
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  downloaded ? Icons.play_circle_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  downloaded ? 'Lire (offline)' : hasResume ? 'Reprendre' : 'Regarder',
                  style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : 15, letterSpacing: -0.2,
                  ),
                ),
              ]),
            ),
          ),

          // ── Progression reprise ──
          if (hasResume && !downloaded) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (resumePos / 7200).clamp(0.0, 1.0),
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(AppTheme.violet),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 3),
            Text('Reprise à ${_fmt(Duration(seconds: resumePos))}',
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
          ],

          if (!compact) ...[
            const SizedBox(height: 10),
            // ── Bouton Download ── (films uniquement — séries gèrent par épisode)
            if (_isMovie) _buildDownloadBtn(
              dlSvc: dlSvc,
              id: dlId,
              streamUrl: provider.getStreamUrl(widget.item),
              downloaded: downloaded,
              dlActive: dlActive,
              dlQueued: dlQueued,
              dlError: dlError,
              dlProgress: dlProgress,
              dlItem: dlItem,
            ),

            if (_isMovie) const SizedBox(height: 10),

            // ── Ma liste ──
            FocusableInk(
              onTap: () => _toggleFav(provider),
              borderRadius: 14,
              focusColor: AppTheme.gold,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity, height: 46,
                decoration: BoxDecoration(
                  gradient: isFav ? LinearGradient(colors: [
                    AppTheme.gold.withOpacity(0.12),
                    AppTheme.gold.withOpacity(0.06),
                  ]) : null,
                  color: isFav ? null : AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isFav ? AppTheme.gold.withOpacity(0.4) : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(isFav ? Icons.check_rounded : Icons.add_rounded,
                      color: isFav ? AppTheme.gold : Colors.white.withOpacity(0.55), size: 18),
                  const SizedBox(width: 8),
                  Text(isFav ? 'Dans ma liste' : 'Ma liste',
                      style: TextStyle(
                        color: isFav ? AppTheme.gold : Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w600, fontSize: 13,
                      )),
                ]),
              ),
            ).animate().fadeIn(delay: 300.ms),
          ],
        ]).animate().fadeIn(delay: 240.ms).slideY(begin: 0.06, end: 0);
      },
    );
  }

  Widget _buildDownloadBtn({
    required DownloadService dlSvc,
    required String id,
    required String streamUrl,
    required bool downloaded,
    required bool dlActive,
    required bool dlQueued,
    required bool dlError,
    required double dlProgress,
    DownloadItem? dlItem,
  }) {
    // Statut et apparence
    final Color btnColor;
    final IconData btnIcon;
    final String btnLabel;

    if (downloaded) {
      btnColor = AppTheme.success;
      btnIcon  = Icons.download_done_rounded;
      btnLabel = 'Téléchargé · Supprimer';
    } else if (dlActive) {
      btnColor = AppTheme.violet;
      btnIcon  = Icons.downloading_rounded;
      btnLabel = dlProgress > 0
          ? '${(dlProgress * 100).toStringAsFixed(0)}% — Annuler'
          : 'Téléchargement… — Annuler';
    } else if (dlQueued) {
      btnColor = Colors.white38;
      btnIcon  = Icons.hourglass_top_rounded;
      btnLabel = 'En attente — Annuler';
    } else if (dlError) {
      btnColor = AppTheme.error;
      btnIcon  = Icons.error_rounded;
      btnLabel = 'Erreur — Réessayer';
    } else {
      btnColor = const Color(0xFF1A2035);
      btnIcon  = Icons.download_rounded;
      btnLabel = 'Télécharger';
    }

    return FocusableInk(
      borderRadius: 14,
      focusColor: AppTheme.violet,
      onTap: () {
        if (downloaded) {
          dlSvc.delete(id);
        } else if (dlActive || dlQueued) {
          dlSvc.cancel(id);
        } else if (dlError) {
          dlSvc.retry(id);
        } else {
          dlSvc.enqueue(DownloadItem(
            id:         id,
            title:      widget.item.name,
            streamIcon: widget.item.streamIcon,
            url:        streamUrl,
            ext:        widget.item.containerExtension.isNotEmpty
                ? widget.item.containerExtension : 'mp4',
            tabIndex:   widget.sourceTabIndex,
          ));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity, height: 46,
        decoration: BoxDecoration(
          color: btnColor.withOpacity(downloaded ? 0.1 : dlActive ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: btnColor.withOpacity(downloaded || dlActive ? 0.45 : 0.2),
            width: dlActive ? 1.5 : 1,
          ),
          boxShadow: dlActive
              ? [BoxShadow(color: AppTheme.violet.withOpacity(0.2), blurRadius: 10)]
              : null,
        ),
        child: Stack(children: [
          // Progress fill (actif seulement)
          if (dlActive && dlProgress > 0)
            FractionallySizedBox(
              widthFactor: dlProgress,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.violet.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(btnIcon, color: btnColor, size: 17),
              const SizedBox(width: 8),
              Text(btnLabel,
                  style: TextStyle(
                      color: btnColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ),
        ]),
      ),
    ).animate().fadeIn(delay: 340.ms);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SÉRIES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSeriesSection(IptvProvider provider, {required bool isLandscape}) {
    if (provider.isLoadingSeriesInfo) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 24, height: 24,
            child: CircularProgressIndicator(color: AppTheme.violet.withOpacity(0.7), strokeWidth: 2)),
          const SizedBox(height: 14),
          Text(context.read<LanguageProvider>().l10n.t('details_loading_episodes'),
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ])),
      );
    }

    if (provider.currentSeriesInfo.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(child: Text(
          context.read<LanguageProvider>().l10n.t('details_episodes_error'),
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        )),
      );
    }

    final episodesData = provider.currentSeriesInfo['episodes'];
    if (episodesData == null || episodesData is! Map || episodesData.isEmpty) {
      return Text(context.read<LanguageProvider>().l10n.t('details_no_episodes'),
          style: const TextStyle(color: Colors.white38));
    }

    final seasons = (episodesData as Map).keys.cast<String>().toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    if (_selectedSeason.isEmpty || !seasons.contains(_selectedSeason)) {
      _selectedSeason = seasons.first;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // [v3] Header SAISONS avec badge count violet
      Row(children: [
        _sectionHeader('SAISONS', Icons.video_library_rounded),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 8)],
          ),
          child: Text('${seasons.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 12),

      // [v3] Sélecteur saisons pill gradient
      SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: seasons.length,
          itemBuilder: (_, i) {
            final s = seasons[i];
            final sel = _selectedSeason == s;
            final epCount = (episodesData[s] as List?)?.length ?? 0;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FocusableInk(
                onTap: () {
                  setState(() => _selectedSeason = s);
                  _seasonAnim..reset()..forward();
                },
                borderRadius: 20,
                focusColor: AppTheme.violet,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: sel ? AppTheme.gradientHorizontal : null,
                    color: sel ? null : AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppTheme.violet.withOpacity(0.5) : Colors.white.withOpacity(0.06)),
                    boxShadow: sel
                        ? [BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 12)]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('S$s', style: TextStyle(
                      color: sel ? Colors.white : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w400,
                    )),
                    if (epCount > 0) ...[
                      const SizedBox(width: 5),
                      Text('$epCount ep', style: TextStyle(
                        color: sel ? Colors.white.withOpacity(0.7) : AppTheme.textMuted,
                        fontSize: 10,
                      )),
                    ],
                  ]),
                ),
              ),
            );
          },
        ),
      ),

      const SizedBox(height: 16),
      Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, AppTheme.violet.withOpacity(0.2),
              AppTheme.violet.withOpacity(0.2), Colors.transparent],
            stops: const [0, 0.2, 0.8, 1.0],
          ),
        ),
      ),
      const SizedBox(height: 8),

      // Épisodes avec AnimatedSwitcher
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_selectedSeason),
          child: isLandscape
              ? _buildEpisodeGrid(episodesData[_selectedSeason], provider)
              : _buildEpisodeList(episodesData[_selectedSeason], provider),
        ),
      ),
    ]);
  }

  Widget _buildEpisodeGrid(dynamic seasonEps, IptvProvider provider) {
    if (seasonEps == null || (seasonEps as List).isEmpty) return _noEpisodesWidget();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 2.8,
        crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: seasonEps.length,
      itemBuilder: (_, i) => _buildEpisodeTile(seasonEps[i] as Map<String, dynamic>, i, provider, compact: true),
    );
  }

  Widget _buildEpisodeList(dynamic seasonEps, IptvProvider provider) {
    if (seasonEps == null || (seasonEps as List).isEmpty) return _noEpisodesWidget();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: seasonEps.length,
      separatorBuilder: (_, __) => Container(height: 1, color: Colors.white.withOpacity(0.04)),
      itemBuilder: (_, i) => _buildEpisodeTile(seasonEps[i] as Map<String, dynamic>, i, provider),
    );
  }

  // [v3] Episode tile card dark premium + left accent
  Widget _buildEpisodeTile(Map<String, dynamic> ep, int i, IptvProvider provider, {bool compact = false}) {
    final epNum    = ep['episode_num']?.toString() ?? (i + 1).toString();
    final title    = ep['title']?.toString() ?? 'Épisode $epNum';
    final duration = ep['info']?['duration']?.toString();
    final plot     = ep['info']?['plot']?.toString();
    final stillPath = ep['info']?['movie_image']?.toString() ?? ep['info']?['still_path']?.toString();
    final epId     = int.tryParse(ep['id']?.toString() ?? '0') ?? 0;
    final resumePos = provider.getResumePosition(epId, widget.sourceTabIndex);
    final hasProg  = resumePos > 10;

    return FocusableInk(
      onTap: () => _navigateToPlayer(
        provider.getEpisodeStreamUrl(ep),
        title: '${widget.item.name} — $title',
        streamId: epId,
      ),
      borderRadius: 12,
      focusColor: AppTheme.violet,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            // Left accent gradient actif si en cours
            Container(
              width: 2.5,
              decoration: BoxDecoration(
                gradient: hasProg ? AppTheme.gradientPrimary
                    : LinearGradient(colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.0),
                      ]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    vertical: compact ? 8 : 12, horizontal: 8),
                child: Row(children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: compact ? 72 : 88,
                      height: compact ? 44 : 54,
                      child: Stack(fit: StackFit.expand, children: [
                        stillPath != null && stillPath.isNotEmpty
                            ? CachedNetworkImage(imageUrl: stillPath, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _epNumBox(epNum))
                            : _epNumBox(epNum),
                        DecoratedBox(decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                            ))),
                        Positioned(bottom: 4, left: 5,
                          child: Text('E$epNum', style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black)]))),
                        if (hasProg)
                          Positioned(bottom: 0, left: 0, right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(8)),
                              child: LinearProgressIndicator(
                                value: (resumePos / 2700).clamp(0.0, 1.0),
                                backgroundColor: Colors.white.withOpacity(0.15),
                                valueColor: AlwaysStoppedAnimation(AppTheme.violet),
                                minHeight: 2.5,
                              ),
                            )),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title, style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (duration != null && !compact) ...[
                          const SizedBox(height: 3),
                          Text(duration, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                        ],
                        if (plot != null && plot.isNotEmpty && !compact) ...[
                          const SizedBox(height: 2),
                          Text(plot, style: TextStyle(
                              color: AppTheme.textSecondary.withOpacity(0.7), fontSize: 11, height: 1.4),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // [v3] Play button gradient + download button
                  Consumer<DownloadService>(builder: (_, dlSvc, __) {
                    final epDlId     = '${epId}_3';
                    final dlItem     = dlSvc.find(epDlId);
                    final downloaded = dlItem?.isCompleted ?? false;
                    final dlActive   = dlItem?.isActive ?? false;
                    final dlQueued   = dlItem?.status == DownloadStatus.queued;
                    final dlError    = dlItem?.status == DownloadStatus.error;

                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      // Download icon btn
                      FocusableInk(
                        borderRadius: 14,
                        focusColor: AppTheme.violet,
                        onTap: () {
                          if (downloaded) { dlSvc.delete(epDlId); return; }
                          if (dlActive || dlQueued) { dlSvc.cancel(epDlId); return; }
                          if (dlError) { dlSvc.retry(epDlId); return; }
                          dlSvc.enqueue(DownloadItem(
                            id:           epDlId,
                            title:        widget.item.name,
                            streamIcon:   widget.item.streamIcon,
                            url:          provider.getEpisodeStreamUrl(ep),
                            ext:          ep['container_extension']?.toString() ?? 'mp4',
                            tabIndex:     3,
                            episodeTitle: title,
                            seasonLabel:  _selectedSeason.isNotEmpty
                                ? 'Saison $_selectedSeason' : null,
                          ));
                        },
                        child: Container(
                          width: 28, height: 28,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: downloaded
                                ? AppTheme.success.withOpacity(0.15)
                                : dlActive
                                    ? AppTheme.violet.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.06),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: downloaded
                                  ? AppTheme.success.withOpacity(0.4)
                                  : dlActive
                                      ? AppTheme.violet.withOpacity(0.4)
                                      : Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Icon(
                            downloaded
                                ? Icons.download_done_rounded
                                : dlActive || dlQueued
                                    ? Icons.downloading_rounded
                                    : dlError
                                        ? Icons.error_rounded
                                        : Icons.download_rounded,
                            color: downloaded
                                ? AppTheme.success
                                : dlActive
                                    ? AppTheme.violet
                                    : Colors.white38,
                            size: 13,
                          ),
                        ),
                      ),
                      // Play btn
                      FocusableInk(
                        borderRadius: 15,
                        focusColor: AppTheme.violet,
                        onTap: () {
                          if (downloaded && dlItem?.localPath != null) {
                            _navigateToPlayer('file://${dlItem!.localPath}',
                                title: '${widget.item.name} — $title',
                                streamId: epId);
                            return;
                          }
                          _navigateToPlayer(provider.getEpisodeStreamUrl(ep),
                              title: '${widget.item.name} — $title',
                              streamId: epId);
                        },
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            gradient: AppTheme.gradientPrimary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 10),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ]);
                  }),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: i * 35), duration: 220.ms);
  }

  Widget _noEpisodesWidget() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      context.read<LanguageProvider>().l10n.t('details_no_episodes_season'),
      style: const TextStyle(color: Colors.white38, fontSize: 13),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  // [v3] Section header : barre accent gauche + glow + icône pill gradient
  Widget _sectionHeader(String label, IconData icon) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Barre accent gauche avec glow
      Container(
        width: 3, height: 20,
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)],
        ),
      ),
      const SizedBox(width: 10),
      // Icône pill gradient
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Icon(icon, color: Colors.white, size: 11),
      ),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        fontSize: 10, color: Colors.white.withOpacity(0.55),
        fontWeight: FontWeight.w800, letterSpacing: 1.5,
      )),
    ]);
  }

  // [v3] Circle buttons glassmorphism
  Widget _circleBtn(IconData icon, {required VoidCallback onTap, Color color = Colors.white}) {
    final inner = Container(
      margin: const EdgeInsets.all(8),
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Icon(icon, color: color, size: 16),
    );
    return FocusableInk(
      onTap: onTap,
      borderRadius: 26,
      focusColor: color,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: inner,
        ),
      ),
    );
  }

  Widget _typeBadge() {
    final label = _isSeries ? 'SÉRIE' : _isMovie ? 'FILM' : 'DIRECT';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppTheme.gradientHorizontal,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 8)],
      ),
      child: Text(label, style: const TextStyle(
          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
    );
  }

  // [v3] TMDB rating badge avec glow gold
  Widget _tmdbRatingBadge(double rating) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.gold.withOpacity(0.1),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.gold.withOpacity(0.45)),
      boxShadow: [BoxShadow(color: AppTheme.gold.withOpacity(0.15), blurRadius: 10)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: AppTheme.gold, size: 12),
      const SizedBox(width: 4),
      Text(rating.toStringAsFixed(1),
          style: const TextStyle(color: AppTheme.gold, fontSize: 11, fontWeight: FontWeight.w800)),
      const SizedBox(width: 2),
      Text('/10', style: TextStyle(color: AppTheme.gold.withOpacity(0.55), fontSize: 9)),
    ]),
  );

  Widget _ratingBadge(String rating) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.gold.withOpacity(0.1),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 11, color: AppTheme.gold),
      const SizedBox(width: 4),
      Text(
        rating.length > 3 ? rating.substring(0, 3) : rating,
        style: const TextStyle(color: AppTheme.gold, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ]),
  );

  // [v3] Meta badges avec icône tintée + border colorée
  Widget _metaBadge(IconData icon, String label, {Color? color}) {
    final c = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: c.withOpacity(0.8)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            color: c.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: AppTheme.textMuted),
      const SizedBox(width: 8),
      Text('$label  ', style: const TextStyle(
          color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
      Expanded(child: Text(value,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );

  // [v3] Episode number fallback box
  Widget _epNumBox(String num) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppTheme.violet.withOpacity(0.2), AppTheme.surface],
      ),
    ),
    child: Center(child: Text(num, style: const TextStyle(
        color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w800))),
  );

  Widget _skeletonBox(double width, double height, {double radius = 4}) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
        color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(radius)),
  );

  void _toggleFav(IptvProvider provider) {
    final added = provider.toggleFavorite(widget.item, widget.sourceTabIndex);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added ? 'Ajouté aux favoris ☆' : 'Retiré des favoris'),
      duration: const Duration(seconds: 2),
      backgroundColor: AppTheme.surface,
    ));
    setState(() {});
  }

  void _navigateToPlayer(String url, {String? title, int? streamId}) {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<LanguageProvider>().l10n.t('player_invalid_url')),
      ));
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, a, b) => PlayerScreen(
          streamUrl: url,
          title: title ?? widget.item.name,
          streamIcon: widget.item.streamIcon,
          streamId: streamId ?? widget.item.streamId,
          tabIndex: widget.sourceTabIndex,
        ),
        transitionsBuilder: (_, a, b, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}