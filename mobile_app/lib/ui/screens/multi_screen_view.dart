// lib/ui/screens/multi_screen_view.dart
//
// Arich Player — Multi-Screen View v1.0
//
// Features :
//   • Layouts 2 / 3 / 4 écrans
//   • Focus tap → audio ON sur l'écran actif, muet sur les autres
//   • Bordure accent 3px sur le slot en focus
//   • Channel picker slide-up par slot (liste chaînes live)
//   • Swap via bouton dans l'overlay de chaque slot
//   • D-pad TV compatible (navigation entre slots)
//   • PiP natif Android sur quitter
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../core/tv_layout.dart';
import '../../models/channel.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/multi_screen_provider.dart';
import '../../services/media_kit_player.dart';
import '../../services/video_player_service.dart';

// ── Constantes ────────────────────────────────────────────────────────────────

const _kFocusBorderWidth = 3.0;
const _kCornerRadius     = 8.0;
const _kPipChannel       = MethodChannel('arich.iptv/pip');

// ── Entrée publique — wrappée avec son propre provider ────────────────────────
// Fournit MultiScreenProvider localement pour éviter l'erreur
// "Could not find Provider<MultiScreenProvider>" lors d'un pushReplacement.

class MultiScreenView extends StatelessWidget {
  final Channel?       initialChannel;
  final IVideoPlayer?  initialPlayer;
  final List<Channel>? liveChannels;

  const MultiScreenView({
    super.key,
    this.initialChannel,
    this.initialPlayer,
    this.liveChannels,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MultiScreenProvider(),
      child: _MultiScreenBody(
        initialChannel: initialChannel,
        initialPlayer:  initialPlayer,
        liveChannels:   liveChannels,
      ),
    );
  }
}

class _MultiScreenBody extends StatefulWidget {
  final Channel?       initialChannel;
  final IVideoPlayer?  initialPlayer;
  final List<Channel>? liveChannels;

  const _MultiScreenBody({
    this.initialChannel,
    this.initialPlayer,
    this.liveChannels,
  });

  @override
  State<_MultiScreenBody> createState() => _MultiScreenBodyState();
}

class _MultiScreenBodyState extends State<_MultiScreenBody>
    with TickerProviderStateMixin {

  late final MultiScreenProvider _msp;
  bool _showTopBar  = true;
  Timer? _hideTimer;

  // Overlay par slot (overlay contrôles mini)
  final Map<int, bool> _slotOverlay = {};

  // Channel picker
  int?           _pickerSlotId;
  bool           _showPicker = false;
  late final AnimationController _pickerAnim;
  late final Animation<Offset>   _pickerSlide;

  // Swap pending : premier slot sélectionné pour le swap
  int? _swapSource;

  bool get _isTV => TVDetector().isTV;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _msp = context.read<MultiScreenProvider>();

    _pickerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _pickerSlide = Tween<Offset>(
      begin: const Offset(0.0, 1.0), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pickerAnim, curve: Curves.easeOutCubic));

    if (!_isTV) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    WakelockPlus.enable();

    // [FIX] activate() et _startHideTimer() appellent notifyListeners()/setState()
    // ce qui est interdit pendant le build initial → tout différé au premier frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _msp.activate(
        layout:         MultiScreenLayout.split2,
        initialChannel: widget.initialChannel,
        initialPlayer:  widget.initialPlayer,
      );
      // Si on a une chaîne initiale mais pas de player transféré → lancer la lecture
      if (widget.initialChannel != null && widget.initialPlayer == null) {
        _loadChannelInSlot(0, widget.initialChannel!);
      } else if (widget.initialPlayer != null) {
        widget.initialPlayer!.setVolume(1.0);
      }
      _startHideTimer();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pickerAnim.dispose();
    _pickerSearchCtrl.dispose();
    WakelockPlus.disable();
    if (!_isTV) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
    }
    // Deactivate libère tous les players non-transférés
    _msp.deactivate();
    super.dispose();
  }

  // ── Timer UI ─────────────────────────────────────────────────────────────────

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_showTopBar) setState(() => _showTopBar = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_showPicker) setState(() => _showTopBar = false);
    });
  }

  void _onScreenTap() {
    _startHideTimer();
    if (_showPicker) return;
  }

  // ── Slot player creation ──────────────────────────────────────────────────────

  Future<void> _loadChannelInSlot(int slotId, Channel channel) async {
    final prov = context.read<IptvProvider>();
    final url  = prov.getStreamUrl(channel, tabIndex: 1);

    _msp.setSlotLoading(slotId, true);

    // Crée un nouveau player MediaKit
    final player = MediaKitPlayer(bufferSize: 32 * 1024 * 1024);

    try {
      await player.setProperty('hwdec', 'auto-safe');
      await player.setProperty('hwdec-codecs', 'h264,hevc,vp9,av1');
    } catch (_) {}

    _msp.setSlot(slotId, channel: channel, player: player);
    _msp.setSlotLoading(slotId, false);

    player.open(url, headers: const {
      'User-Agent': 'Smarters/5.1 Dalvik/2.1.0',
      'Connection': 'keep-alive',
    });

    // Écoute les erreurs
    player.errorStream.listen((err) {
      if (err.isNotEmpty) _msp.setSlotError(slotId, true);
    });
  }

  // ── Channel picker ────────────────────────────────────────────────────────────

  void _openPicker(int slotId) {
    setState(() {
      _pickerSlotId = slotId;
      _showPicker   = true;
    });
    _pickerAnim.forward();
    _hideTimer?.cancel();
    if (!_showTopBar) setState(() => _showTopBar = true);
  }

  void _closePicker() {
    _pickerAnim.reverse().then((_) {
      if (mounted) setState(() {
        _showPicker        = false;
        _pickerSlotId      = null;
        _pickerSearchQuery = '';
        _pickerSearchCtrl.clear();
      });
    });
    _startHideTimer();
  }

  void _onPickerChannelSelected(Channel ch) {
    final slotId = _pickerSlotId;
    _closePicker();
    if (slotId == null) return;
    _loadChannelInSlot(slotId, ch);
  }

  // ── Swap ──────────────────────────────────────────────────────────────────────

  void _initiateSwap(int slotId) {
    if (_swapSource == null) {
      setState(() => _swapSource = slotId);
      _startHideTimer();
    } else {
      if (_swapSource != slotId) {
        _msp.swapSlots(_swapSource!, slotId);
      }
      setState(() => _swapSource = null);
    }
  }

  // ── Layout change ─────────────────────────────────────────────────────────────

  void _cycleLayout() {
    final layouts = MultiScreenLayout.values;
    final idx     = layouts.indexOf(_msp.layout);
    _msp.setLayout(layouts[(idx + 1) % layouts.length]);
    _startHideTimer();
  }

  // ── D-pad TV ──────────────────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _startHideTimer();
    final count = _msp.slotCount;
    final focus = _msp.focusSlot;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _msp.setFocus((focus + 1) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _msp.setFocus((focus - 1 + count) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (count == 4) _msp.setFocus(focus < 2 ? focus : focus - 2);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (count == 4) _msp.setFocus(focus < 2 ? focus + 2 : focus);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        if (_showPicker) { _closePicker(); return KeyEventResult.handled; }
        _openPicker(focus);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.backspace:
        if (_showPicker) { _closePicker(); return KeyEventResult.handled; }
        Navigator.pop(context);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) => _onKeyEvent(e),
        child: GestureDetector(
          onTap: _onScreenTap,
          child: Stack(
            children: [
              // ── Grille vidéo ──
              _buildGrid(),
              // ── Top bar ──
              AnimatedOpacity(
                opacity: _showTopBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_showTopBar,
                  child: _buildTopBar(),
                ),
              ),
              // ── Channel picker ──
              if (_showPicker) _buildPickerOverlay(),
              // ── Swap hint ──
              if (_swapSource != null) _buildSwapHint(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Grid ─────────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    return Consumer<MultiScreenProvider>(
      builder: (_, msp, __) {
        switch (msp.layout) {
          case MultiScreenLayout.split2:
            return Row(
              children: [
                Expanded(child: _buildCell(0)),
                const SizedBox(width: 2),
                Expanded(child: _buildCell(1)),
              ],
            );
          case MultiScreenLayout.split3:
            return Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildCell(0),
                ),
                const SizedBox(height: 2),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(child: _buildCell(1)),
                      const SizedBox(width: 2),
                      Expanded(child: _buildCell(2)),
                    ],
                  ),
                ),
              ],
            );
          case MultiScreenLayout.split4:
            return Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildCell(0)),
                      const SizedBox(width: 2),
                      Expanded(child: _buildCell(1)),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildCell(2)),
                      const SizedBox(width: 2),
                      Expanded(child: _buildCell(3)),
                    ],
                  ),
                ),
              ],
            );
        }
      },
    );
  }

  // ── Cell ─────────────────────────────────────────────────────────────────────

  Widget _buildCell(int slotId) {
    return Consumer<MultiScreenProvider>(
      builder: (_, msp, __) {
        final slot    = msp.slots[slotId];
        final focused = msp.focusSlot == slotId;
        final isSwapSrc = _swapSource == slotId;

        return GestureDetector(
          onTap: () {
            _msp.setFocus(slotId);
            setState(() => _slotOverlay[slotId] = !(_slotOverlay[slotId] ?? false));
            _startHideTimer();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(_kCornerRadius),
              border: Border.all(
                color: isSwapSrc
                    ? AppTheme.gold
                    : focused
                        ? AppTheme.violet
                        : Colors.transparent,
                width: _kFocusBorderWidth,
              ),
              boxShadow: focused
                  ? [BoxShadow(
                      color: AppTheme.violet.withOpacity(0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    )]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  (_kCornerRadius - _kFocusBorderWidth).clamp(0, _kCornerRadius)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Vidéo ──
                  if (slot.hasPlayer)
                    slot.player!.buildVideoWidget()
                  else
                    _buildEmptySlot(slotId, focused),

                  // ── Loading ──
                  if (slot.isLoading)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(AppTheme.violet),
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),

                  // ── Error ──
                  if (slot.hasError && !slot.isLoading)
                    _buildErrorOverlay(slotId),

                  // ── Slot overlay (controls) ──
                  if (_showTopBar || (_slotOverlay[slotId] ?? false))
                    _buildSlotOverlay(slotId, slot, focused),

                  // ── Focus badge ──
                  if (focused && slot.hasPlayer)
                    _buildFocusBadge(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Empty slot ────────────────────────────────────────────────────────────────

  Widget _buildEmptySlot(int slotId, bool focused) {
    final l = context.read<LanguageProvider>().l10n;
    return Container(
      color: AppTheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: focused ? AppTheme.gradientPrimary : null,
              color: focused ? null : AppTheme.surfaceHigh,
              border: Border.all(
                color: focused
                    ? AppTheme.violet.withOpacity(0.6)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Icon(Icons.add_rounded,
                color: focused ? Colors.white : Colors.white38, size: 26),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _openPicker(slotId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: focused ? AppTheme.gradientPrimary : null,
                color: focused ? null : AppTheme.surfaceTop,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(context.read<LanguageProvider>().l10n.t('multiscreen_add_channel'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Slot overlay ─────────────────────────────────────────────────────────────

  Widget _buildSlotOverlay(int slotId, MultiScreenSlot slot, bool focused) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            // Logo + nom
            if (slot.channel != null) ...[
              if (slot.channel!.streamIcon.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: slot.channel!.streamIcon,
                  width: 20, height: 20, fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const SizedBox(),
                  fadeInDuration: const Duration(milliseconds: 80),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(slot.channel!.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ] else
              const Spacer(),

            // Bouton changer chaîne
            _slotIconBtn(
              icon: Icons.tv_rounded,
              onTap: () => _openPicker(slotId),
              active: false,
            ),
            const SizedBox(width: 4),
            // Bouton swap
            _slotIconBtn(
              icon: Icons.swap_horiz_rounded,
              onTap: () => _initiateSwap(slotId),
              active: _swapSource == slotId,
              activeColor: AppTheme.gold,
            ),
            const SizedBox(width: 4),
            // Bouton fermer slot
            if (slotId != 0 || _msp.slots[0].hasPlayer)
              _slotIconBtn(
                icon: Icons.close_rounded,
                onTap: () => _msp.clearSlot(slotId),
                active: false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required bool active,
    Color activeColor = AppTheme.violet,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withOpacity(0.25)
              : Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? activeColor.withOpacity(0.8)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Icon(icon,
            color: active ? activeColor : Colors.white70,
            size: 13),
      ),
    );
  }

  // ── Focus badge ───────────────────────────────────────────────────────────────

  Widget _buildFocusBadge() {
    return Positioned(
      bottom: 6, right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white, size: 10),
          const SizedBox(width: 3),
          Text(context.read<LanguageProvider>().l10n.t('multi_live_badge'), style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  // ── Error overlay ─────────────────────────────────────────────────────────────

  Widget _buildErrorOverlay(int slotId) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.signal_wifi_off_rounded, color: Colors.white38, size: 32),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final slot = _msp.slots[slotId];
              if (slot.channel != null) {
                _msp.setSlotError(slotId, false);
                _loadChannelInSlot(slotId, slot.channel!);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(context.read<LanguageProvider>().l10n.t('retry'),
                  style: TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final l = context.read<LanguageProvider>().l10n;
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xC8000000), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              // Back
              _topBtn(Icons.arrow_back_ios_new_rounded,
                  () => Navigator.pop(context)),
              const SizedBox(width: 12),

              // Titre
              ShaderMask(
                shaderCallback: (b) => AppTheme.gradientHorizontal
                    .createShader(Rect.fromLTWH(0, 0, 120, 20)),
                child: Text(context.read<LanguageProvider>().l10n.t('multiscreen_title'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              const Spacer(),

              // Layout switcher
              Consumer<MultiScreenProvider>(builder: (_, msp, __) {
                return GestureDetector(
                  onTap: _cycleLayout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_layoutIcon(msp.layout),
                          color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(_layoutLabel(msp.layout, l),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                );
              }),
              const SizedBox(width: 10),

              // PiP
              if (!Platform.isAndroid ? false : true)
                _topBtn(Icons.picture_in_picture_rounded, () async {
                  try { await _kPipChannel.invokeMethod('enterPip'); } catch (_) {}
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  IconData _layoutIcon(MultiScreenLayout l) {
    switch (l) {
      case MultiScreenLayout.split2: return Icons.view_column_rounded;
      case MultiScreenLayout.split3: return Icons.view_agenda_rounded;
      case MultiScreenLayout.split4: return Icons.grid_view_rounded;
    }
  }

  String _layoutLabel(MultiScreenLayout l, AppL10n loc) {
    switch (l) {
      case MultiScreenLayout.split2: return loc.t('multiscreen_layout_2');
      case MultiScreenLayout.split3: return loc.t('multiscreen_layout_3');
      case MultiScreenLayout.split4: return loc.t('multiscreen_layout_4');
    }
  }

  // ── Channel picker overlay ────────────────────────────────────────────────────

  // Recherche dans le picker
  final TextEditingController _pickerSearchCtrl = TextEditingController();
  String _pickerSearchQuery = '';

  Widget _buildPickerOverlay() {
    final allChannels = widget.liveChannels
        ?? context.read<IptvProvider>().allLive;
    final channels = _pickerSearchQuery.isEmpty
        ? allChannels
        : allChannels.where((c) =>
            c.name.toLowerCase().contains(_pickerSearchQuery.toLowerCase())).toList();
    final l = context.read<LanguageProvider>().l10n;

    return GestureDetector(
      onTap: _closePicker,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _pickerSlide,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                height: MediaQuery.of(context).size.height * 0.80,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    // Handle
                    Container(
                      width: 36, height: 3,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Titre + fermer
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                      child: Row(
                        children: [
                          ShaderMask(
                            shaderCallback: (b) => AppTheme.gradientHorizontal
                                .createShader(Rect.fromLTWH(0, 0, 160, 20)),
                            child: Text(context.read<LanguageProvider>().l10n.t('multiscreen_pick_channel'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: AppTheme.gradientHorizontal,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${channels.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _closePicker,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceHigh,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white60, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Barre de recherche
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _pickerSearchQuery.isNotEmpty
                                ? AppTheme.violet.withOpacity(0.5)
                                : Colors.white.withOpacity(0.08),
                            width: _pickerSearchQuery.isNotEmpty ? 1.5 : 1,
                          ),
                          boxShadow: _pickerSearchQuery.isNotEmpty
                              ? [BoxShadow(color: AppTheme.violet.withOpacity(0.2), blurRadius: 10)]
                              : null,
                        ),
                        child: TextField(
                          controller: _pickerSearchCtrl,
                          autofocus: false,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: context.read<LanguageProvider>().l10n.t('search_hint'),
                            hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.25), fontSize: 12.5),
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.search_rounded,
                                color: _pickerSearchQuery.isNotEmpty
                                    ? AppTheme.violet : Colors.white24,
                                size: 16),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            suffixIcon: _pickerSearchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _pickerSearchCtrl.clear();
                                      setState(() => _pickerSearchQuery = '');
                                    },
                                    child: const Icon(Icons.close_rounded,
                                        color: Colors.white38, size: 15),
                                  )
                                : null,
                          ),
                          onChanged: (v) => setState(() => _pickerSearchQuery = v),
                        ),
                      ),
                    ),
                    // Liste
                    Expanded(
                      child: channels.isEmpty
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.search_off_rounded,
                                    color: Colors.white24, size: 32),
                                const SizedBox(height: 10),
                                Text(
                                  _pickerSearchQuery.isNotEmpty
                                      ? 'Aucun résultat'
                                      : context.read<LanguageProvider>().l10n.t('no_channels'),
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13)),
                              ]))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              itemCount: channels.length,
                              itemBuilder: (_, i) =>
                                  _buildPickerItem(channels[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerItem(Channel ch) {
    return GestureDetector(
      onTap: () => _onPickerChannelSelected(ch),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 30,
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ch.streamIcon.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: ch.streamIcon,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 80),
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.live_tv_rounded,
                            color: Colors.white24, size: 16),
                      ),
                    )
                  : const Icon(Icons.live_tv_rounded,
                      color: Colors.white24, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(ch.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.add_rounded, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Swap hint ─────────────────────────────────────────────────────────────────

  Widget _buildSwapHint() {
    final l = context.read<LanguageProvider>().l10n;
    return Positioned(
      bottom: 16, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.gold.withOpacity(0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.swap_horiz_rounded,
                color: AppTheme.gold, size: 16),
            const SizedBox(width: 8),
            Text(context.read<LanguageProvider>().l10n.t('multiscreen_swap_hint'),
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}