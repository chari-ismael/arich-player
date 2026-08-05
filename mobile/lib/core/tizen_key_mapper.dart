// lib/core/tizen_key_mapper.dart
//
// Correctifs appliqués (Session v10 — Mars 2026) :
//   1. event.keyLabel  →  event.logicalKey.keyLabel  (getter inexistant sur KeyDownEvent)
//   2. const retiré des maps  (LogicalKeyboardKey interdit comme clé const Flutter 3.x)
//   3. LogicalKeyboardKey.homePage  →  .browserHome  (homePage supprimé Flutter 3.x)
//   4. Singleton TizenKeyMapper.instance + init()   (appelé depuis main.dart)
//   5. Callbacks player : onPlayPause, onStop, onRewind, onFastForward,
//      onNext, onPrevious, onInfo, onRed, onGreen, onYellow, onBlue, onDigit
//      + clearHandlers()  (requis par player_screen.dart dispose())

import 'package:flutter/services.dart';

// ── Actions enum ──────────────────────────────────────────────────────────────

/// Actions télécommande Samsung TV mappées depuis les [KeyDownEvent].
enum TizenAction {
  up, down, left, right,
  select, back, home,
  playPause, stop, rewind, fastForward,
  channelUp, channelDown,
  volumeUp, volumeDown, mute,
  digit0, digit1, digit2, digit3, digit4,
  digit5, digit6, digit7, digit8, digit9,
  unknown,
}

// ── TizenKeyMapper ────────────────────────────────────────────────────────────

class TizenKeyMapper {
  // ── Singleton ─────────────────────────────────────────────────────────────
  TizenKeyMapper._();
  static final TizenKeyMapper instance = TizenKeyMapper._();

  bool _initialized = false;

  // ── Callbacks player (settables depuis player_screen.dart) ────────────────
  // Ces callbacks permettent au player de brancher ses actions directement
  // sur les touches télécommande sans passer par un Focus widget intermédiaire.
  // clearHandlers() les remet tous à null dans dispose().

  VoidCallback?             onPlayPause;
  VoidCallback?             onStop;
  VoidCallback?             onRewind;
  VoidCallback?             onFastForward;
  VoidCallback?             onNext;
  VoidCallback?             onPrevious;
  VoidCallback?             onInfo;
  VoidCallback?             onRed;
  VoidCallback?             onGreen;
  VoidCallback?             onYellow;
  VoidCallback?             onBlue;
  void Function(int digit)? onDigit;

  /// Remet tous les callbacks à null.
  /// Appelé dans dispose() de player_screen pour éviter les fuites mémoire.
  void clearHandlers() {
    onPlayPause   = null;
    onStop        = null;
    onRewind      = null;
    onFastForward = null;
    onNext        = null;
    onPrevious    = null;
    onInfo        = null;
    onRed         = null;
    onGreen       = null;
    onYellow      = null;
    onBlue        = null;
    onDigit       = null;
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Appelé une fois depuis main.dart après TVDetector().init().
  /// Idempotent.
  void init() {
    if (_initialized) return;
    _initialized = true;
    // Écoute globale des KeyDownEvent pour dispatcher les callbacks.
    // Les Focus widgets du player reçoivent également les événements via
    // onKeyEvent — les deux mécanismes coexistent.
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
  }

  /// Handler global : dispatche vers les callbacks si branchés.
  /// Retourne false pour ne pas consommer l'événement — les Focus widgets
  /// peuvent aussi le traiter.
  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final action = mapEvent(event);
    _dispatchCallbacks(action, event);
    return false; // ne consomme pas → propagation normale
  }

  void _dispatchCallbacks(TizenAction action, KeyDownEvent event) {
    switch (action) {
      case TizenAction.playPause:
        onPlayPause?.call();
      case TizenAction.stop:
        onStop?.call();
      case TizenAction.rewind:
        onRewind?.call();
      case TizenAction.fastForward:
        onFastForward?.call();
      case TizenAction.channelUp:
        onPrevious?.call();
      case TizenAction.channelDown:
        onNext?.call();
      default:
        // Touches couleur : comparaison par keyLabel (String)
        final label = event.logicalKey.keyLabel;
        switch (label) {
          case 'ColorF0Red':   onRed?.call();
          case 'ColorF1Green': onGreen?.call();
          case 'ColorF2Yellow': onYellow?.call();
          case 'ColorF3Blue':  onBlue?.call();
        }
        // Chiffres
        if (isDigitAction(action)) {
          final d = digitFromAction(action);
          if (d != null) onDigit?.call(d);
        }
    }
  }

  // ── Map principale ────────────────────────────────────────────────────────
  // Correctif #2 : final (pas const)
  // Correctif #3 : .browserHome remplace .homePage (supprimé Flutter 3.x)
  static final Map<LogicalKeyboardKey, TizenAction> _keyMap = {
    LogicalKeyboardKey.arrowUp:          TizenAction.up,
    LogicalKeyboardKey.arrowDown:        TizenAction.down,
    LogicalKeyboardKey.arrowLeft:        TizenAction.left,
    LogicalKeyboardKey.arrowRight:       TizenAction.right,
    LogicalKeyboardKey.select:           TizenAction.select,
    LogicalKeyboardKey.enter:            TizenAction.select,
    LogicalKeyboardKey.gameButtonSelect: TizenAction.select,
    LogicalKeyboardKey.goBack:           TizenAction.back,
    LogicalKeyboardKey.escape:           TizenAction.back,
    LogicalKeyboardKey.browserBack:      TizenAction.back,
    // homePage n'existe plus depuis Flutter 3.x → browserHome
    LogicalKeyboardKey.browserHome:      TizenAction.home,
    LogicalKeyboardKey.mediaPlay:        TizenAction.playPause,
    LogicalKeyboardKey.mediaPause:       TizenAction.playPause,
    LogicalKeyboardKey.mediaPlayPause:   TizenAction.playPause,
    LogicalKeyboardKey.mediaStop:        TizenAction.stop,
    LogicalKeyboardKey.mediaRewind:      TizenAction.rewind,
    LogicalKeyboardKey.mediaFastForward: TizenAction.fastForward,
    LogicalKeyboardKey.channelUp:        TizenAction.channelUp,
    LogicalKeyboardKey.channelDown:      TizenAction.channelDown,
    LogicalKeyboardKey.audioVolumeUp:    TizenAction.volumeUp,
    LogicalKeyboardKey.audioVolumeDown:  TizenAction.volumeDown,
    LogicalKeyboardKey.audioVolumeMute:  TizenAction.mute,
  };

  // ── Map chiffres ──────────────────────────────────────────────────────────
  static final Map<LogicalKeyboardKey, TizenAction> _digits = {
    LogicalKeyboardKey.digit0: TizenAction.digit0,
    LogicalKeyboardKey.digit1: TizenAction.digit1,
    LogicalKeyboardKey.digit2: TizenAction.digit2,
    LogicalKeyboardKey.digit3: TizenAction.digit3,
    LogicalKeyboardKey.digit4: TizenAction.digit4,
    LogicalKeyboardKey.digit5: TizenAction.digit5,
    LogicalKeyboardKey.digit6: TizenAction.digit6,
    LogicalKeyboardKey.digit7: TizenAction.digit7,
    LogicalKeyboardKey.digit8: TizenAction.digit8,
    LogicalKeyboardKey.digit9: TizenAction.digit9,
  };

  // ── mapEvent ──────────────────────────────────────────────────────────────

  /// Convertit un [KeyDownEvent] en [TizenAction].
  ///
  /// Correctif #1 : on travaille avec event.logicalKey (LogicalKeyboardKey)
  /// pour les comparaisons de type, et event.logicalKey.keyLabel (String)
  /// uniquement pour le fallback touches couleur Tizen.
  /// L'ancien code utilisait event.keyLabel directement → getter inexistant.
  static TizenAction mapEvent(KeyDownEvent event) {
    final LogicalKeyboardKey logical = event.logicalKey;

    // 1. Map principale
    final TizenAction? main = _keyMap[logical];
    if (main != null) return main;

    // 2. Chiffres
    final TizenAction? digit = _digits[logical];
    if (digit != null) return digit;

    // 3. Fallback keyLabel (String) pour touches couleur Samsung
    //    On compare String avec String — jamais mélangé avec LogicalKeyboardKey.
    final String label = logical.keyLabel;
    switch (label) {
      case 'ColorF0Red':    return TizenAction.back;        // Rouge → retour
      case 'ColorF1Green':  return TizenAction.playPause;
      case 'ColorF2Yellow': return TizenAction.rewind;
      case 'ColorF3Blue':   return TizenAction.fastForward;
    }

    return TizenAction.unknown;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool isNavigationAction(TizenAction a) =>
      a == TizenAction.up   || a == TizenAction.down ||
      a == TizenAction.left || a == TizenAction.right;

  static bool isDigitAction(TizenAction a) =>
      a.index >= TizenAction.digit0.index &&
      a.index <= TizenAction.digit9.index;

  static int? digitFromAction(TizenAction a) {
    if (!isDigitAction(a)) return null;
    return a.index - TizenAction.digit0.index;
  }
}