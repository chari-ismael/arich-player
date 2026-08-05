// lib/ui/widgets/mini_player_bar.dart
//
// Arich Player — Mini Player Bar
// Barre flottante persistante affichée sur HomeScreen quand un stream
// est actif mais que le PlayerScreen est fermé.
//
// Features :
//   • Thumbnail / icône du stream
//   • Titre scrollable
//   • Bouton play/pause
//   • Bouton fermer (stop)
//   • Tap → rouvre le PlayerScreen en plein écran
//   • Animation slide-up à l'apparition, slide-down à la fermeture
//   • Barre de progression pour VOD
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/mini_player_provider.dart';

class MiniPlayerBar extends StatefulWidget {
  /// Callback appelé quand l'utilisateur tape sur la barre
  /// pour rouvrir le player en plein écran.
  final VoidCallback onExpand;

  const MiniPlayerBar({super.key, required this.onExpand});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset>   _slide;
  late final Animation<double>   _fade;

  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = context.watch<MiniPlayerProvider>().isVisible;
    if (visible && !_wasVisible) {
      _anim.forward();
    } else if (!visible && _wasVisible) {
      _anim.reverse();
    }
    _wasVisible = visible;
  }

  @override
  Widget build(BuildContext context) {
    final mini = context.watch<MiniPlayerProvider>();

    if (!mini.hasActiveStream && !_wasVisible) return const SizedBox.shrink();

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: _MiniPlayerContent(
          mini: mini,
          onExpand: widget.onExpand,
        ),
      ),
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  final MiniPlayerProvider mini;
  final VoidCallback onExpand;

  const _MiniPlayerContent({required this.mini, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final isLive = mini.tabIndex == 1;
    final accentColor = isLive ? AppTheme.red
        : mini.tabIndex == 2 ? AppTheme.violet
        : AppTheme.secondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onExpand,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF14141F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accentColor.withOpacity(0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: accentColor.withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // ── Barre de progression (VOD uniquement) ──────────────────
                if (!isLive)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: StreamBuilder<Duration>(
                      stream: mini.player?.stream.position,
                      builder: (_, snap) {
                        final pos = snap.data ?? Duration.zero;
                        final dur = mini.player?.state.duration ?? Duration.zero;
                        final ratio = (dur.inMilliseconds > 0)
                            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                            : 0.0;
                        return ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft:  Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: Colors.white.withOpacity(0.06),
                            valueColor: AlwaysStoppedAnimation(accentColor.withOpacity(0.7)),
                            minHeight: 2.5,
                          ),
                        );
                      },
                    ),
                  ),

                // ── Contenu principal ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Row(
                    children: [
                      // Thumbnail
                      _Thumbnail(
                        imageUrl: mini.streamIcon,
                        isLive: isLive,
                        accentColor: accentColor,
                      ),
                      const SizedBox(width: 12),

                      // Titre + badge
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              if (isLive) ...[
                                _LiveDot(color: accentColor),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  mini.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                            const SizedBox(height: 3),
                            Text(
                              isLive ? 'En direct' : mini.tabIndex == 2 ? 'Film' : 'Série',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.38),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Play / Pause
                      _ControlBtn(
                        icon: mini.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: () => context.read<MiniPlayerProvider>().togglePlay(),
                        color: Colors.white,
                        size: 26,
                      ),
                      const SizedBox(width: 4),

                      // Fermer
                      _ControlBtn(
                        icon: Icons.close_rounded,
                        onTap: () => context.read<MiniPlayerProvider>().close(),
                        color: Colors.white38,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final String imageUrl;
  final bool   isLive;
  final Color  accentColor;

  const _Thumbnail({
    required this.imageUrl,
    required this.isLive,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accentColor.withOpacity(0.1),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: isLive ? BoxFit.contain : BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, __, ___) => _fallbackIcon(accentColor, isLive),
              )
            : _fallbackIcon(accentColor, isLive),
      ),
    );
  }

  Widget _fallbackIcon(Color color, bool live) => Center(
    child: Icon(
      live ? Icons.live_tv_rounded : Icons.movie_rounded,
      color: color.withOpacity(0.5),
      size: 20,
    ),
  );
}

// ── Live dot pulsant ──────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double>   _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, __) => Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withOpacity(0.7 + _a.value * 0.3),
        boxShadow: [BoxShadow(
          color: widget.color.withOpacity(0.5 * _a.value),
          blurRadius: 4, spreadRadius: 1,
        )],
      ),
    ),
  );
}

// ── Control button ────────────────────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color  color;
  final double size;

  const _ControlBtn({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: color, size: size),
    ),
  );
}