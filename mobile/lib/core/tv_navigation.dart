// lib/core/tv_navigation.dart
//
// Arich Player — Utilitaires navigation TV / D-pad
//
// Contient :
//   • TvGridNavigator     — gestion D-pad dans une grille (flèches ←→↑↓)
//   • TvListNavigator     — gestion D-pad dans une liste horizontale
//   • TvKeyboardShortcuts — raccourcis clavier globaux par écran
//   • TvFocusRestorer     — restaure le focus au retour sur un écran
//   • TvPlayerControls    — shortcuts spécifiques au player TV
//   • tvRequestFocus      — helper pour mettre le focus sur un node
//
// ⚠️  TvFocusZone et TvBackHandler sont définis dans tv_layout.dart.
//     Ils sont ré-exportés ici pour rétrocompatibilité — NE PAS les redéfinir.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ✅ FIX 2 : re-export uniquement — élimine les erreurs de symboles dupliqués
export 'package:arich_player/core/tv_layout.dart' show TvBackHandler, TvFocusZone;

// ═══════════════════════════════════════════════════════════════════════════════
// TvGridNavigator — Gestion D-pad dans une GridView
// crossAxisCount MUST match the GridView's crossAxisCount.
// ═══════════════════════════════════════════════════════════════════════════════

class TvGridNavigator extends StatefulWidget {
  final Widget child;
  final int crossAxisCount;
  final int itemCount;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  const TvGridNavigator({
    super.key,
    required this.child,
    required this.crossAxisCount,
    required this.itemCount,
    this.initialIndex = 0,
    this.onIndexChanged,
  });

  @override
  State<TvGridNavigator> createState() => _TvGridNavigatorState();
}

class _TvGridNavigatorState extends State<TvGridNavigator> {
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.initialIndex;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    int next       = _focusedIndex;
    final cols     = widget.crossAxisCount;
    final total    = widget.itemCount;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if ((next + 1) % cols != 0 && next + 1 < total) next++;
      else return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (next % cols != 0) next--;
      else return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (next + cols < total) next += cols;
      else return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (next - cols >= 0) next -= cols;
      else return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }

    if (next != _focusedIndex) {
      setState(() => _focusedIndex = next);
      widget.onIndexChanged?.call(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TvListNavigator — Gestion D-pad dans une liste horizontale
// ═══════════════════════════════════════════════════════════════════════════════

class TvListNavigator extends StatefulWidget {
  final Widget child;
  final int itemCount;
  final ScrollController? scrollController;
  final ValueChanged<int>? onIndexChanged;

  const TvListNavigator({
    super.key,
    required this.child,
    required this.itemCount,
    this.scrollController,
    this.onIndexChanged,
  });

  @override
  State<TvListNavigator> createState() => _TvListNavigatorState();
}

class _TvListNavigatorState extends State<TvListNavigator> {
  int _focusedIndex = 0;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    int next = _focusedIndex;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (next + 1 < widget.itemCount) next++;
      else return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (next > 0) next--;
      else return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }

    if (next != _focusedIndex) {
      setState(() => _focusedIndex = next);
      widget.onIndexChanged?.call(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TvKeyboardShortcuts — Raccourcis clavier globaux pour chaque écran
// ═══════════════════════════════════════════════════════════════════════════════

class TvKeyboardShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback? onMenu;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSearch;

  const TvKeyboardShortcuts({
    super.key,
    required this.child,
    this.onMenu,
    this.onPlayPause,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
            event.logicalKey == LogicalKeyboardKey.f10) {
          onMenu?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
            event.logicalKey == LogicalKeyboardKey.space) {
          onPlayPause?.call();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.f5 ||
            event.logicalKey == LogicalKeyboardKey.browserSearch) {
          onSearch?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TvFocusRestorer — Restaure le focus au retour sur un écran
// ═══════════════════════════════════════════════════════════════════════════════

class TvFocusRestorer extends StatefulWidget {
  final Widget child;
  const TvFocusRestorer({super.key, required this.child});

  @override
  State<TvFocusRestorer> createState() => _TvFocusRestorerState();
}

class _TvFocusRestorerState extends State<TvFocusRestorer>
    with WidgetsBindingObserver {
  FocusNode? _lastFocused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lastFocused != null) {
      _lastFocused?.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) _lastFocused = FocusManager.instance.primaryFocus;
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// tvRequestFocus — Helper : request focus après le frame courant
// ═══════════════════════════════════════════════════════════════════════════════

void tvRequestFocus(FocusNode node) {
  WidgetsBinding.instance.addPostFrameCallback((_) => node.requestFocus());
}

// ═══════════════════════════════════════════════════════════════════════════════
// TvPlayerControls — Shortcuts spécifiques au player TV
// Gère : play/pause (Enter/Space/OK), seek (←→), volume (↑↓)
// ═══════════════════════════════════════════════════════════════════════════════

class TvPlayerControls extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSeekForward;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onVolumeUp;
  final VoidCallback? onVolumeDown;
  final VoidCallback? onShowControls;

  const TvPlayerControls({
    super.key,
    required this.child,
    this.onPlayPause,
    this.onSeekForward,
    this.onSeekBackward,
    this.onVolumeUp,
    this.onVolumeDown,
    this.onShowControls,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        onShowControls?.call();

        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.mediaPlayPause) {
          onPlayPause?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.mediaFastForward) {
          onSeekForward?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.mediaRewind) {
          onSeekBackward?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          onVolumeUp?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onVolumeDown?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}