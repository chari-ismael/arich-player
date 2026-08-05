// lib/providers/multi_screen_provider.dart
//
// Arich Player — Multi-Screen Provider v1.0
//
// Gère l'état global du mode multi-écrans :
//   • Slots actifs (2, 3 ou 4)
//   • Slot en focus (audio ON, bordure accent)
//   • Layout courant (split2, split3, split4)
//   • Swap de slots
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/channel.dart';
import '../services/video_player_service.dart';

// ── Layout disponibles ────────────────────────────────────────────────────────

enum MultiScreenLayout {
  split2,   // 2 écrans côte à côte (1 ligne × 2 colonnes)
  split3,   // 3 écrans : 1 large en haut + 2 petits en bas
  split4,   // 4 écrans (2 lignes × 2 colonnes)
}

// ── Un slot = un player + une chaîne ─────────────────────────────────────────

class MultiScreenSlot {
  final int id;
  final Channel? channel;
  final IVideoPlayer? player;
  final bool isLoading;
  final bool hasError;

  const MultiScreenSlot({
    required this.id,
    this.channel,
    this.player,
    this.isLoading = false,
    this.hasError  = false,
  });

  bool get isEmpty   => channel == null;
  bool get hasPlayer => player != null;

  MultiScreenSlot copyWith({
    Channel?      channel,
    IVideoPlayer? player,
    bool?         isLoading,
    bool?         hasError,
    bool          clearChannel = false,
    bool          clearPlayer  = false,
  }) {
    return MultiScreenSlot(
      id:        id,
      channel:   clearChannel ? null : (channel  ?? this.channel),
      player:    clearPlayer  ? null : (player   ?? this.player),
      isLoading: isLoading ?? this.isLoading,
      hasError:  hasError  ?? this.hasError,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

class MultiScreenProvider extends ChangeNotifier {
  MultiScreenLayout _layout    = MultiScreenLayout.split2;
  int               _focusSlot = 0;
  bool              _active    = false;

  late List<MultiScreenSlot> _slots;

  MultiScreenProvider() {
    _slots = List.generate(4, (i) => MultiScreenSlot(id: i));
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  MultiScreenLayout       get layout    => _layout;
  int                     get focusSlot => _focusSlot;
  bool                    get isActive  => _active;
  List<MultiScreenSlot>   get slots     => List.unmodifiable(_slots);
  int                     get slotCount => _slotCountForLayout(_layout);

  List<MultiScreenSlot> get activeSlots =>
      _slots.sublist(0, slotCount);

  // ── Activation / désactivation ─────────────────────────────────────────────

  void activate({
    MultiScreenLayout layout = MultiScreenLayout.split2,
    Channel? initialChannel,
    IVideoPlayer? initialPlayer,
  }) {
    _active    = true;
    _layout    = layout;
    _focusSlot = 0;
    _slots     = List.generate(4, (i) => MultiScreenSlot(id: i));

    if (initialChannel != null) {
      _slots[0] = MultiScreenSlot(
        id:      0,
        channel: initialChannel,
        player:  initialPlayer,
      );
    }
    notifyListeners();
  }

  void deactivate() {
    _disposeAllPlayers();
    _active    = false;
    _focusSlot = 0;
    _slots     = List.generate(4, (i) => MultiScreenSlot(id: i));
    notifyListeners();
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  void setLayout(MultiScreenLayout layout) {
    final oldCount = slotCount;
    _layout        = layout;
    final newCount = slotCount;

    // Si on réduit le nombre de slots : dispose les players excédentaires
    if (newCount < oldCount) {
      for (int i = newCount; i < oldCount; i++) {
        _slots[i].player?.dispose();
        _slots[i] = MultiScreenSlot(id: i);
      }
      if (_focusSlot >= newCount) _focusSlot = 0;
    }
    notifyListeners();
  }

  // ── Focus ──────────────────────────────────────────────────────────────────

  void setFocus(int slotId) {
    if (slotId == _focusSlot) return;
    _focusSlot = slotId;
    _syncVolumes();
    notifyListeners();
  }

  // ── Slot management ────────────────────────────────────────────────────────

  void setSlot(int slotId, {
    required Channel channel,
    required IVideoPlayer player,
  }) {
    if (slotId < 0 || slotId >= 4) return;
    // Dispose l'ancien player si existant et différent
    final old = _slots[slotId];
    if (old.player != null && old.player != player) {
      old.player!.dispose();
    }
    _slots[slotId] = MultiScreenSlot(
      id:      slotId,
      channel: channel,
      player:  player,
    );
    _syncVolumes();
    notifyListeners();
  }

  void setSlotLoading(int slotId, bool loading) {
    if (slotId < 0 || slotId >= 4) return;
    _slots[slotId] = _slots[slotId].copyWith(isLoading: loading);
    notifyListeners();
  }

  void setSlotError(int slotId, bool error) {
    if (slotId < 0 || slotId >= 4) return;
    _slots[slotId] = _slots[slotId].copyWith(hasError: error);
    notifyListeners();
  }

  void clearSlot(int slotId) {
    if (slotId < 0 || slotId >= 4) return;
    _slots[slotId].player?.dispose();
    _slots[slotId] = MultiScreenSlot(id: slotId);
    if (_focusSlot == slotId) _focusSlot = 0;
    notifyListeners();
  }

  // ── Swap ───────────────────────────────────────────────────────────────────

  void swapSlots(int a, int b) {
    if (a == b) return;
    if (a < 0 || a >= 4 || b < 0 || b >= 4) return;
    final tmp  = _slots[a];
    _slots[a]  = MultiScreenSlot(id: a, channel: _slots[b].channel,
        player: _slots[b].player, isLoading: _slots[b].isLoading);
    _slots[b]  = MultiScreenSlot(id: b, channel: tmp.channel,
        player: tmp.player, isLoading: tmp.isLoading);
    if (_focusSlot == a) _focusSlot = b;
    else if (_focusSlot == b) _focusSlot = a;
    _syncVolumes();
    notifyListeners();
  }

  // ── Volume sync ────────────────────────────────────────────────────────────
  // Focus = volume plein, autres = muets

  void _syncVolumes() {
    for (int i = 0; i < 4; i++) {
      final p = _slots[i].player;
      if (p == null) continue;
      p.setVolume(i == _focusSlot ? 1.0 : 0.0);
    }
  }

  // ── Utils ──────────────────────────────────────────────────────────────────

  int _slotCountForLayout(MultiScreenLayout l) {
    switch (l) {
      case MultiScreenLayout.split2: return 2;
      case MultiScreenLayout.split3: return 3;
      case MultiScreenLayout.split4: return 4;
    }
  }

  void _disposeAllPlayers() {
    for (final slot in _slots) {
      slot.player?.dispose();
    }
  }

  @override
  void dispose() {
    _disposeAllPlayers();
    super.dispose();
  }
}