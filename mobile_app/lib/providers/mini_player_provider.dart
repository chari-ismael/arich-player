// lib/providers/mini_player_provider.dart
//
// Arich Player — Mini Player Provider
// Gère l'état global du mini player persistant :
//   • Stream actif (url, titre, icon, tabIndex, streamId)
//   • Player media_kit partagé entre PlayerScreen et MiniPlayerBar
//   • Méthodes play/pause/close accessibles depuis n'importe où
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class MiniPlayerProvider with ChangeNotifier {
  // ── État du stream actif ──────────────────────────────────────────────────

  String _streamUrl  = '';
  String _title      = '';
  String _streamIcon = '';
  int    _tabIndex   = 1;
  int    _streamId   = 0;
  bool   _isVisible  = false;
  bool   _isPlaying  = false;

  // Player partagé — instancié une seule fois, réutilisé
  Player? _player;

  // ── Getters ───────────────────────────────────────────────────────────────

  String get streamUrl  => _streamUrl;
  String get title      => _title;
  String get streamIcon => _streamIcon;
  int    get tabIndex   => _tabIndex;
  int    get streamId   => _streamId;
  bool   get isVisible  => _isVisible;
  bool   get isPlaying  => _isPlaying;
  Player? get player    => _player;

  bool get hasActiveStream => _streamUrl.isNotEmpty && _isVisible;

  // ── Démarrer / reprendre un stream ───────────────────────────────────────

  /// Appelé par PlayerScreen au lancement d'un stream.
  /// Si [fromPlayerScreen] = true, le mini player est caché (le full player est ouvert).
  void setStream({
    required String streamUrl,
    required String title,
    required String streamIcon,
    required int tabIndex,
    required int streamId,
    required Player player,
    bool fromPlayerScreen = true,
  }) {
    _streamUrl  = streamUrl;
    _title      = title;
    _streamIcon = streamIcon;
    _tabIndex   = tabIndex;
    _streamId   = streamId;
    _player     = player;
    _isPlaying  = player.state.playing;
    // En mode full player, le mini player est caché
    _isVisible  = !fromPlayerScreen;

    // Écouter les changements de lecture pour mettre à jour l'état
    player.stream.playing.listen((playing) {
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// Appelé quand PlayerScreen est dépilé (back) → affiche le mini player
  void showMiniPlayer() {
    if (_streamUrl.isEmpty) return;
    _isVisible = true;
    notifyListeners();
  }

  /// Masque le mini player (sans arrêter le stream)
  void hideMiniPlayer() {
    _isVisible = false;
    notifyListeners();
  }

  /// Arrête tout et vide l'état
  void close() {
    _player?.stop();
    _streamUrl  = '';
    _title      = '';
    _streamIcon = '';
    _tabIndex   = 1;
    _streamId   = 0;
    _isVisible  = false;
    _isPlaying  = false;
    _player     = null;
    notifyListeners();
  }

  void togglePlay() {
    if (_player == null) return;
    _isPlaying ? _player!.pause() : _player!.play();
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void play()  { _player?.play();  _isPlaying = true;  notifyListeners(); }
  void pause() { _player?.pause(); _isPlaying = false; notifyListeners(); }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}