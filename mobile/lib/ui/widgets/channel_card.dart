// lib/ui/widgets/channel_card.dart
//
// ARICH Player — ChannelCard v3
// [PERF] memCacheWidth/Height 220px sur CachedNetworkImage → décodage ÷4 en mémoire
//
// NOUVEAUTÉS v2 :
// [1] Badge qualité auto : détection HD/FHD/4K/UHD depuis le nom de la chaîne
// [2] Wide card (Live) : layout amélioré avec numéro de chaîne, EPG area
// [3] Portrait card : shimmer sur image + overlay gradient renforcé
// [4] Hover state : scale + glow shadow plus prononcé
// [5] Badge numéro de chaîne (si disponible dans le nom)
// [6] Indicateur "en cours" pulsé sur les cards live
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../models/channel.dart';

// ── Détection badge qualité depuis le nom ────────────────────────────────────
String? _qualityBadge(String name) {
  final n = name.toUpperCase();
  if (n.contains('4K') || n.contains('UHD') || n.contains('2160')) return '4K';
  if (n.contains('FHD') || n.contains('1080') || n.contains('FULL HD')) return 'FHD';
  if (n.contains(' HD') || n.endsWith(' HD') || n.contains('HD ') || n.contains('720')) return 'HD';
  return null;
}

// ── Extraction numéro de chaîne ───────────────────────────────────────────────
String? _channelNumber(String name) {
  final match = RegExp(r'^(\d{1,4})\s*[-\.:]?\s').firstMatch(name.trim());
  return match?.group(1);
}

class ChannelCard extends StatefulWidget {
  final Channel channel;
  final bool isWide;
  final int tabIndex;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const ChannelCard({
    super.key,
    required this.channel,
    required this.isWide,
    required this.tabIndex,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _pressed = false;
  late final AnimationController _favCtrl;

  // [PERF] Calculés une fois dans initState/didUpdateWidget — pas dans build()
  String? _cachedQuality;
  String? _cachedChanNum;

  @override
  void initState() {
    super.initState();
    _favCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
    _computeCachedValues();
  }

  @override
  void didUpdateWidget(ChannelCard old) {
    super.didUpdateWidget(old);
    if (old.channel.name != widget.channel.name) {
      _computeCachedValues();
    }
  }

  void _computeCachedValues() {
    _cachedQuality = _qualityBadge(widget.channel.name);
    _cachedChanNum = _channelNumber(widget.channel.name);
  }

  @override
  void dispose() { _favCtrl.dispose(); super.dispose(); }

  Color get _accent {
    switch (widget.tabIndex) {
      case 1: return AppTheme.catLiveAccent;
      case 2: return AppTheme.catMoviesAccent;
      default: return AppTheme.catSeriesAccent;
    }
  }

  Color get _glowColor => widget.isFavorite ? AppTheme.gold : AppTheme.violet;

  void _handleFavTap() {
    HapticFeedback.lightImpact();
    _favCtrl.forward(from: 0);
    widget.onFavoriteTap();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sizes = context.tvSizes;

    return Focus(
      onFocusChange: (f) {
        if (!mounted) return;
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic, alignment: 0.3);
          });
        }
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          _handleTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Hero(
        tag: 'card_${widget.channel.streamId}_${widget.tabIndex}',
        flightShuttleBuilder: (_, anim, __, ___, ____) => ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(context.tvSizes.radiusCard),
            child: widget.isWide
                ? _buildWideCard(context.tvSizes)
                : _buildPortraitCard(context.tvSizes),
          ),
        ),
        child: GestureDetector(
        onTap: _handleTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : (_focused ? 1.03 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(sizes.radiusCard),
              boxShadow: [
                if (_focused)
                  BoxShadow(
                    color: _glowColor.withOpacity(0.50),
                    blurRadius: 22, spreadRadius: 1, offset: const Offset(0, 4),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 8, offset: const Offset(0, 3),
                  ),
              ],
              border: Border.all(
                color: _focused
                    ? _glowColor.withOpacity(0.80)
                    : Colors.white.withOpacity(0.07),
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  (sizes.radiusCard - 1.0).clamp(0, double.infinity)),
              child: widget.isWide
                  ? _buildWideCard(sizes)
                  : _buildPortraitCard(sizes),
            ),
          ),
        ),
      ),
      ),  // Hero
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [1][2] WIDE CARD — Live TV
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWideCard(TVSizes sizes) {
    final quality = _cachedQuality;
    final chanNum = _cachedChanNum;

    return Container(
      color: AppTheme.surface,
      child: Stack(fit: StackFit.expand, children: [
        // Image / logo
        _ChannelImage(
          url: widget.channel.streamIcon,
          fit: BoxFit.contain,
          placeholder: Icon(Icons.live_tv_rounded,
            color: Colors.white.withOpacity(0.07), size: 28),
        ),

        // Gradient overlay bas
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.90)],
              ),
            ),
          ),
        ),

        // Gradient overlay haut (pour badges)
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent],
              ),
            ),
          ),
        ),

        // Badge LIVE pulsant — haut gauche
        Positioned(
          top: 6, left: 7,
          child: _LiveDot(),
        ),

        // [1] Badge qualité — haut droit
        if (quality != null)
          Positioned(
            top: 6, right: 7,
            child: _QualityBadge(quality: quality),
          ),

        // Numéro de chaîne (optionnel)
        if (chanNum != null)
          Positioned(
            bottom: 22, left: 7,
            child: Text(chanNum,
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              )),
          ),

        // Nom de la chaîne
        Positioned(
          bottom: 7, left: 7, right: 36,
          child: Text(
            widget.channel.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: sizes.isTV ? 11.0 : 10.0,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),

        // Bouton favori
        Positioned(
          bottom: 4, right: 5,
          child: _FavButton(
            isFavorite: widget.isFavorite,
            controller: _favCtrl,
            onTap: _handleFavTap,
            size: sizes.isTV ? 20.0 : 16.0,
          ),
        ),

        // Overlay glow focus
        if (_focused)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [_glowColor.withOpacity(0.10), Colors.transparent],
                  radius: 1.2,
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [3] PORTRAIT CARD — Films / Séries
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPortraitCard(TVSizes sizes) {
    final quality = _cachedQuality;

    return Container(
      color: AppTheme.surface,
      child: Stack(fit: StackFit.expand, children: [
        // Poster
        _ChannelImage(
          url: widget.channel.streamIcon,
          fit: BoxFit.cover,
          placeholder: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.tabIndex == 3 ? Icons.tv_rounded : Icons.movie_rounded,
                  color: _accent.withOpacity(0.22), size: 28,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(widget.channel.name,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.28),
                      fontSize: 9, fontWeight: FontWeight.w500),
                    maxLines: 2, textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),

        // Gradient bas renforcé
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.75),
                  Colors.black.withOpacity(0.95),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),

        // Titre
        Positioned(
          bottom: 7, left: 7, right: 34,
          child: Text(
            widget.channel.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: sizes.isTV ? 10.0 : 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
            ),
            maxLines: 2, overflow: TextOverflow.ellipsis,
          ),
        ),

        // Badge SÉRIE
        if (widget.tabIndex == 3)
          Positioned(
            top: 7, left: 7,
            child: _TypeBadge(label: 'SÉRIE', color: _accent),
          ),

        // [1] Badge qualité
        if (quality != null)
          Positioned(
            top: 7, right: 7,
            child: _QualityBadge(quality: quality),
          ),

        // Bouton favori
        Positioned(
          bottom: 4, right: 4,
          child: _FavButton(
            isFavorite: widget.isFavorite,
            controller: _favCtrl,
            onTap: _handleFavTap,
            size: sizes.isTV ? 20.0 : 17.0,
          ),
        ),

        // Overlay focus glow
        if (_focused)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [_glowColor.withOpacity(0.12), Colors.transparent],
                  radius: 1.0,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHANNEL IMAGE — shimmer pendant chargement
// ─────────────────────────────────────────────────────────────────────────────
class _ChannelImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget placeholder;

  const _ChannelImage({
    required this.url, required this.fit, required this.placeholder});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return placeholder;

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      filterQuality: FilterQuality.low,
      memCacheWidth:  180,
      memCacheHeight: 180,
      maxWidthDiskCache: 360,
      maxHeightDiskCache: 360,
      fadeInDuration: const Duration(milliseconds: 150),
      // [PERF] Suppression du shimmer animate — créait 1 AnimationController
      // par image chargée (= centaines simultanés sur la home/grid) → lag majeur.
      // Remplacement par un container statique couleur neutre.
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF0E0E1C)),
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAV BUTTON — rebond élastique au tap
// ─────────────────────────────────────────────────────────────────────────────
class _FavButton extends StatelessWidget {
  final bool isFavorite;
  final AnimationController controller;
  final VoidCallback onTap;
  final double size;

  const _FavButton({
    required this.isFavorite, required this.controller,
    required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final t = controller.value;
            final scale = t < 0.5 ? 1.0 + t * 0.8 : 1.4 - (t - 0.5) * 0.8;
            return Transform.scale(
              scale: scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.elasticOut,
                child: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(isFavorite),
                  size: size,
                  color: isFavorite
                      ? AppTheme.gold
                      : Colors.white.withOpacity(0.45),
                  shadows: isFavorite
                      ? [Shadow(color: AppTheme.gold.withOpacity(0.6), blurRadius: 8)]
                      : [],
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
// LIVE DOT — pastille rouge pulsante
// [PERF] Un seul ticker global via _LiveDotTicker.instance
// Au lieu de 1 AnimationController par card (= centaines de tickers)
// ─────────────────────────────────────────────────────────────────────────────

/// TickerProvider autonome — non lié à un State, jamais disposé.
class _AppTickerProvider extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Singleton ticker — crée UN SEUL AnimationController pour toute l'app.
/// Utilise son propre TickerProvider persistant (plus jamais lié à un widget).
class _LiveDotTicker {
  _LiveDotTicker._();
  static final _LiveDotTicker instance = _LiveDotTicker._();

  AnimationController? _ctrl;
  final _vsync = _AppTickerProvider();
  int _refCount = 0;

  Animation<double> acquire() {
    _refCount++;
    if (_ctrl == null) {
      _ctrl = AnimationController(
        vsync: _vsync,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
    return CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut);
  }

  void release() {
    _refCount--;
    if (_refCount <= 0) {
      _ctrl?.dispose();
      _ctrl = null;
      _refCount = 0;
    }
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> {
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _anim = _LiveDotTicker.instance.acquire();
  }

  @override
  void dispose() {
    _LiveDotTicker.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.red.withOpacity(0.80 + _anim.value * 0.20),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(
            color: AppTheme.red.withOpacity(0.35 * _anim.value),
            blurRadius: 6, spreadRadius: 1,
          )],
        ),
        // Dot seul — pas de label "LIVE" qui peut prêter à confusion
        child: Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75 + _anim.value * 0.25),
            shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// [1] QUALITY BADGE — HD / FHD / 4K
// ─────────────────────────────────────────────────────────────────────────────
class _QualityBadge extends StatelessWidget {
  final String quality;
  const _QualityBadge({required this.quality});

  Color get _color {
    switch (quality) {
      case '4K': return const Color(0xFFFFD60A);
      case 'FHD': return const Color(0xFF0A84FF);
      default: return Colors.white60;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withOpacity(0.45)),
      ),
      child: Text(quality,
        style: TextStyle(
          color: _color,
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE BADGE — SÉRIE / FILM
// ─────────────────────────────────────────────────────────────────────────────
class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Text(label, style: TextStyle(
        color: color, fontSize: 7,
        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}