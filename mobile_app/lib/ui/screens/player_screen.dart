// lib/ui/screens/player_screen.dart
//
// ARICH Player — Player Screen v10.1
//
// NOUVEAUTÉS v10 :
// [FEAT] TV : arrowLeft/arrowRight = navigation chaîne (Live) ou seek ±10s (VOD)
//        • En mode Live sur TV, ←/→ zapent vers chaîne précédente/suivante
//        • En mode VOD (Films/Séries), ←/→ continuent à seek ±10s comme avant
//        • Sur Tizen les touches directionnelles sont identiquement prises en compte
// [FEAT] Preview chaîne cible sous chaque flèche de navigation
//        • Pill glassmorphism avec logo + nom de la chaîne précédente/suivante
//        • Visible au même moment que les flèches (contrôlé par AnimatedOpacity)
//        • Bypass BackdropFilter sur Samsung Tizen
// [FEAT] PiP natif Android : setPlayerActive envoyé à MainActivity.kt
//        → auto-PiP sur Home uniquement quand le player est actif
// [PERF] Tous les fixes v9 conservés
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/iptv_provider.dart';
import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../../models/channel.dart';
import '../../core/tv_layout.dart';
import '../../core/tizen_key_mapper.dart';
import '../../services/video_player_service.dart';
import '../../services/media_kit_player.dart';
import '../../services/tizen_video_player.dart';
import 'multi_screen_view.dart';

const _kVolumeChannel     = MethodChannel('arich.iptv/volume');
const _kBrightnessChannel = MethodChannel('arich.iptv/brightness');
const _kPipChannel        = MethodChannel('arich.iptv/pip');

// ── Widget principal ─────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String streamIcon;
  final int streamId;
  final int tabIndex;
  final List<Channel>? liveChannels;
  final int? channelIndex;
  final IVideoPlayer? existingPlayer;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.streamIcon = '',
    this.streamId = 0,
    this.tabIndex = 1,
    this.liveChannels,
    this.channelIndex,
    this.existingPlayer,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  late final IVideoPlayer _player;
  bool _playerOwned = true;

  bool   _showControls         = true;
  bool   _showSettings         = false;
  bool   _hasError             = false;
  bool   _isBufferingInitial   = true;
  bool   _hasPlayedOnce        = false;
  bool   _showEndScreen        = false;
  bool   _showBufferingSpinner = false;
  String _errorMessage         = '';

  int  _retryCount               = 0;
  static const int _maxRetries   = 3;
  bool _isReconnecting           = false;
  int  _silentRetryCount         = 0;
  static const int _maxSilentRetries = 5;

  Timer? _hideTimer;
  Timer? _bufferTimeoutTimer;
  Timer? _keepAliveTimer;
  Timer? _stallWatchdog;
  Timer? _bufferSpinnerTimer;
  Duration _lastWatchdogPos = Duration.zero;

  int _stallTickCount = 0;
  static const int _stallTicksBeforeReconnect = 2;
  DateTime? _lastSilentReconnectAt;

  double _playbackSpeed = 1.0;
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  List<TrackInfo> _audioTracks  = [];
  List<TrackInfo> _subTracks    = [];
  TrackInfo _currentAudio       = TrackInfo.auto;
  TrackInfo _currentSubtitle    = TrackInfo.off;

  String _epgCurrent = '';
  String _epgNext    = '';

  late int _zapIndex;
  String   _zapTitle     = '';
  String   _zapIcon      = '';
  bool     _showZapBadge = false;
  Timer?   _zapBadgeTimer;

  late final AnimationController _settingsAnim;
  late final Animation<Offset>   _settingsSlide;

  // [v8] Pulse animation pour badge LIVE
  late final AnimationController _liveAnim;

  // Sleep Timer
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  int?   _sleepMinutes;
  DateTime? _sleepStartedAt;
  int    _sleepSecondsLeft = 0;
  static const _kSleepOptions = [15, 30, 60, 90, 120];

  bool   _showSeekOverlay  = false;
  int    _seekDeltaSeconds = 0;
  Timer? _seekOverlayTimer;

  double _currentVolume     = 0.5;
  double _currentBrightness = 0.5;
  bool   _showVolumeBar     = false;
  bool   _showBrightnessBar = false;
  Timer? _volumeBarTimer;
  Timer? _brightnessBarTimer;
  bool?  _swipeIsLeft;
  double _swipeStartDx   = 0;
  bool   _swipeIsHoriz   = false;

  bool   _showTapRipple = false;
  bool   _tapRippleLeft = true;
  Timer? _tapRippleTimer;

  bool _isSpeedBoost = false;

  // Lock screen
  bool   _isLocked      = false;
  bool   _showUnlockHint = false;
  Timer? _unlockHintTimer;

  bool get _isLive  => widget.tabIndex == 1;
  bool get _isTV    => TVDetector().isTV;
  bool get _isTizen => TVDetector().isTizen;

  static const Map<String, String> _headers = {
    'User-Agent': 'Smarters/5.1 Dalvik/2.1.0',
    'Connection': 'keep-alive',
    'Referer': '',
  };

  // ── Init / Dispose ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _zapIndex = widget.channelIndex ?? 0;
    _zapTitle = widget.title;
    _zapIcon  = widget.streamIcon;

    if (!_isTizen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    WakelockPlus.enable();
    // Notifie Android que le player est actif → autorise auto-PiP sur Home
    _setNativePipActive(true);

    if (!_isTV) _initVolumeAndBrightness();

    _settingsAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _settingsSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _settingsAnim, curve: Curves.easeOutCubic));

    // [v8] Live badge pulse
    _liveAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    if (widget.existingPlayer != null) {
      _player = widget.existingPlayer!;
      _playerOwned = false;
    } else {
      _player = _createPlayer();
      _playerOwned = true;
    }

    _setupListeners();
    _initPlayerProperties().then((_) => _openStream());

    // Touches télécommande Samsung — brancher après _createPlayer()
    if (_isTizen) {
      _registerTizenKeys();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.streamId != 0) {
        context.read<IptvProvider>().addToHistory(
          streamUrl: widget.streamUrl, title: widget.title,
          streamIcon: widget.streamIcon, tabIndex: widget.tabIndex,
          streamId: widget.streamId,
        );
      }
      if (_isLive && !_isOffline) { _loadEpg(); _startKeepAlive(); }
    });
  }

  Future<void> _initVolumeAndBrightness() async {
    try {
      final vol = await _kVolumeChannel.invokeMethod<double>('getVolume');
      final br  = await _kBrightnessChannel.invokeMethod<double>('getBrightness');
      if (mounted) setState(() {
        _currentVolume     = (vol ?? 0.5).clamp(0.0, 1.0);
        _currentBrightness = (br  ?? 0.5).clamp(0.0, 1.0);
      });
    } catch (_) {}
  }

  Future<void> _initPlayerProperties() async {
    if (!_isTizen) {
      await _player.setProperty('hwdec', 'auto-safe');
      await _player.setProperty('hwdec-codecs', 'h264,hevc,vp9,av1');
    }
  }

  void _setupListeners() {
    _player.errorStream.listen((err) {
      if (!mounted || err.isEmpty) return;
      if (_hasPlayedOnce && !_isReconnecting) { _silentReconnect(); return; }
      final lower = err.toLowerCase();
      if (lower.contains('end of file') || lower.contains('demuxer') ||
          lower.contains('generic i/o') || lower.contains('av_read_frame') ||
          lower.contains('connection timeout') || lower.contains('http error 4') ||
          lower.contains('http error 5')) {
        _onError('Stream indisponible — réessayez ou changez de source.');
      }
    });

    _player.playingStream.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _hasPlayedOnce = true; _isReconnecting = false; _silentRetryCount = 0;
        _bufferTimeoutTimer?.cancel(); _bufferSpinnerTimer?.cancel();
        _startStallWatchdog();
        setState(() { _hasError = false; _isBufferingInitial = false; _showBufferingSpinner = false; });
      }
    });

    _player.bufferingStream.listen((buffering) {
      if (!mounted) return;
      if (buffering && _hasPlayedOnce) {
        _bufferSpinnerTimer?.cancel();
        _bufferSpinnerTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted && _player.state.buffering) setState(() => _showBufferingSpinner = true);
        });
      } else {
        _bufferSpinnerTimer?.cancel();
        if (_showBufferingSpinner) setState(() => _showBufferingSpinner = false);
        if (!buffering) _bufferTimeoutTimer?.cancel();
      }
    });

    _player.completedStream.listen((completed) {
      if (!mounted || !completed || _isLive) return;
      setState(() => _showEndScreen = true);
    });

    _player.stateStream.listen((s) {
      if (!mounted) return;
      if (s.audioTracks.isNotEmpty || s.subtitleTracks.isNotEmpty) {
        setState(() {
          _audioTracks     = s.audioTracks;
          _subTracks       = s.subtitleTracks;
          _currentAudio    = s.currentAudio;
          _currentSubtitle = s.currentSubtitle;
        });
      }
    });
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 4), (_) async {
      if (!mounted || _hasError || _isReconnecting) return;
      if (!_player.state.playing && !_player.state.buffering) return;
      try {
        if (widget.streamId != 0) {
          await context.read<IptvProvider>().api.getShortEpg(widget.streamId);
        } else {
          await http.head(Uri.parse(widget.streamUrl))
              .timeout(const Duration(seconds: 5));
        }
      } catch (_) {}
    });
  }

  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _lastWatchdogPos = _player.state.position;
    _stallTickCount  = 0;
    _stallWatchdog = Timer.periodic(const Duration(seconds: 18), (_) {
      if (!mounted || !_hasPlayedOnce || _isReconnecting) return;
      if (!_player.state.playing) {
        _lastWatchdogPos = _player.state.position; _stallTickCount = 0; return;
      }
      if (_isLive && _player.state.buffering) {
        _lastWatchdogPos = _player.state.position; _stallTickCount = 0; return;
      }
      final pos = _player.state.position;
      if (pos == _lastWatchdogPos) {
        _stallTickCount++;
        if (_stallTickCount >= _stallTicksBeforeReconnect) {
          _stallTickCount = 0; _silentReconnect();
        }
      } else {
        _stallTickCount = 0;
      }
      _lastWatchdogPos = pos;
    });
  }

  void _silentReconnect() {
    if (_isReconnecting || !mounted) return;
    final now = DateTime.now();
    if (_lastSilentReconnectAt != null &&
        now.difference(_lastSilentReconnectAt!).inSeconds < 30) return;
    if (_silentRetryCount >= _maxSilentRetries) {
      _onError('Stream instable après plusieurs reconnexions.\nVérifiez votre réseau.'); return;
    }
    _isReconnecting = true; _silentRetryCount++; _lastSilentReconnectAt = now;
    _stallWatchdog?.cancel();
    Future.delayed(Duration(seconds: 2 + _silentRetryCount), () {
      if (!mounted) { _isReconnecting = false; return; }
      _player.open(widget.streamUrl, headers: _headers).then((_) {
        _isReconnecting = false; if (mounted) _startStallWatchdog();
      }).catchError((_) {
        _isReconnecting = false; if (mounted) _startStallWatchdog();
      });
    });
  }

  bool get _isOffline => widget.streamUrl.startsWith('file://');

  void _openStream() {
    setState(() {
      _hasError = false; _errorMessage = ''; _isBufferingInitial = true;
      _hasPlayedOnce = false; _isReconnecting = false;
      _showEndScreen = false; _showBufferingSpinner = false;
    });
    _startBufferTimeout();
    // Lecture offline : pas de headers réseau, pas de keep-alive
    final headers = _isOffline ? <String, String>{} : _headers;
    _player.open(widget.streamUrl, headers: headers).then((_) {
      if (!_isLive && widget.streamId != 0 && mounted) {
        final pos = context.read<IptvProvider>().getResumePosition(widget.streamId, widget.tabIndex);
        if (pos > 5) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _player.seek(Duration(seconds: pos));
          });
        }
      }
    });
    _startHideTimer();
  }

  void _startBufferTimeout() {
    _bufferTimeoutTimer?.cancel();
    _bufferTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _player.state.playing) return;
      _retryCount < _maxRetries ? _retry()
          : _onError('Le stream ne répond pas.\nVérifiez votre connexion.');
    });
  }

  void _onError(String msg) {
    _bufferTimeoutTimer?.cancel(); _stallWatchdog?.cancel(); _bufferSpinnerTimer?.cancel();
    if (!mounted) return;
    setState(() { _hasError = true; _errorMessage = msg; _showBufferingSpinner = false; });
  }

  void _retry() {
    if (_retryCount >= _maxRetries) {
      _onError('Échec après $_maxRetries tentatives.\nVérifiez votre connexion.'); return;
    }
    _retryCount++; _stallWatchdog?.cancel();
    Future.delayed(Duration(seconds: _retryCount), () { if (mounted) _openStream(); });
  }

  void _manualRetry() {
    _retryCount = 0; _silentRetryCount = 0; _isReconnecting = false;
    _stallTickCount = 0; _lastSilentReconnectAt = null;
    _stallWatchdog?.cancel(); _bufferTimeoutTimer?.cancel();
    setState(() { _hasError = false; _errorMessage = ''; });
    _openStream();
  }

  Future<void> _loadEpg() async {
    if (!_isLive || widget.streamId == 0) return;
    try {
      final epg = await context.read<IptvProvider>().api.getShortEpg(widget.streamId);
      if (!mounted) return;
      final programs = epg['epg_listings'] as List?;
      if (programs != null && programs.isNotEmpty) {
        setState(() {
          _epgCurrent = programs[0]['title']?.toString() ?? '';
          _epgNext = programs.length > 1 ? (programs[1]['title']?.toString() ?? '') : '';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (!_isTizen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
      ]);
    }
    // Notifie Android que le player est fermé → plus d'auto-PiP sur Home
    _setNativePipActive(false);
    WakelockPlus.disable();
    _hideTimer?.cancel(); _bufferTimeoutTimer?.cancel(); _keepAliveTimer?.cancel();
    _stallWatchdog?.cancel(); _bufferSpinnerTimer?.cancel(); _zapBadgeTimer?.cancel();
    _seekOverlayTimer?.cancel(); _volumeBarTimer?.cancel(); _brightnessBarTimer?.cancel();
    _unlockHintTimer?.cancel();
    _tapRippleTimer?.cancel(); _settingsAnim.dispose(); _liveAnim.dispose();
    _sleepTimer?.cancel(); _sleepCountdownTimer?.cancel();

    if (!_isLive && widget.streamId != 0) {
      final pos = _player.state.position.inSeconds;
      final dur = _player.state.duration.inSeconds;
      if (pos > 5 && dur > 0 && pos < dur * 0.95) {
        try {
          context.read<IptvProvider>().updateHistoryPosition(
            streamId: widget.streamId, tabIndex: widget.tabIndex,
            positionSeconds: pos, totalDurationSeconds: dur,
          );
        } catch (_) {}
      }
    }

    if (_playerOwned) _player.dispose();
    // Libérer les touches Samsung pour l'écran suivant
    if (_isTizen) TizenKeyMapper.instance.clearHandlers();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTRÔLES (logique métier — inchangée)
  // ═══════════════════════════════════════════════════════════════════════════

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
    final timeout = _isTV ? 8 : 4;
    _hideTimer = Timer(Duration(seconds: timeout), () {
      if (mounted && !_showSettings) setState(() => _showControls = false);
    });
  }

  void _onTapVideo() {
    if (_isTV) return;
    if (_showSettings) { _closeSettings(); return; }
    if (_showControls) { _hideTimer?.cancel(); setState(() => _showControls = false); }
    else { _startHideTimer(); }
  }

  void _togglePlay() {
    _player.togglePlay();
    _startHideTimer();
  }

  void _seek(Duration delta) {
    if (_isLive) return;
    _player.seek(_player.state.position + delta);
    _startHideTimer();
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);
  }

  Future<void> _tvVolumeUp()   => _adjustVolume(0.1);
  Future<void> _tvVolumeDown() => _adjustVolume(-0.1);

  /// Indique au natif si le player est actif (pour l'auto-PiP sur Home)
  void _setNativePipActive(bool active) {
    if (_isTizen) return;
    try {
      _kPipChannel.invokeMethod('setPlayerActive', {'active': active});
    } catch (_) {}
  }

  Future<void> _enterPip() async {
    if (_isTizen) return;
    try { await _kPipChannel.invokeMethod('enterPip'); } catch (_) {}
  }

  void _startSpeedBoost() {
    if (_isLive || _isSpeedBoost || _isTV) return;
    setState(() => _isSpeedBoost = true);
    _player.setRate(2.0);
  }

  void _stopSpeedBoost() {
    if (!_isSpeedBoost) return;
    setState(() => _isSpeedBoost = false);
    _player.setRate(_playbackSpeed);
  }

  void _onDoubleTapSeek(TapDownDetails details) {
    if (_isLive || _isTV) return;
    final screenW = MediaQuery.of(context).size.width;
    final isLeft  = details.localPosition.dx < screenW / 2;
    setState(() { _tapRippleLeft = isLeft; _showTapRipple = true; });
    _tapRippleTimer?.cancel();
    _tapRippleTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showTapRipple = false);
    });
    _seek(isLeft ? const Duration(seconds: -10) : const Duration(seconds: 10));
    _showSeekFeedback(isLeft ? -10 : 10);
  }

  void _onPanStart(DragStartDetails d) {
    if (_isTV) return;
    _swipeStartDx = d.localPosition.dx; _swipeIsLeft = null; _swipeIsHoriz = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_showSettings || _isTV) return;
    final dx = d.delta.dx; final dy = d.delta.dy;
    if (_swipeIsLeft == null && (dx.abs() + dy.abs()) > 8) {
      _swipeIsHoriz = dx.abs() > dy.abs() * 1.5;
      if (!_swipeIsHoriz) {
        final screenW = MediaQuery.of(context).size.width;
        _swipeIsLeft = _swipeStartDx < screenW / 2;
      }
    }
    if (_swipeIsHoriz) {
      if (!_isLive) { _seekDeltaSeconds += (dx * 0.5).round(); _showSeekFeedback(_seekDeltaSeconds, persist: true); }
    } else if (_swipeIsLeft != null) {
      final s = -dy / 300.0;
      if (_swipeIsLeft!) _adjustVolume(s); else _adjustBrightness(s);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_isTV) return;
    if (_swipeIsHoriz && !_isLive && _seekDeltaSeconds != 0) {
      _seek(Duration(seconds: _seekDeltaSeconds));
    }
    _seekDeltaSeconds = 0; _swipeIsLeft = null; _swipeIsHoriz = false;
    if (_showSeekOverlay) {
      _seekOverlayTimer?.cancel();
      _seekOverlayTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showSeekOverlay = false);
      });
    }
  }

  void _showSeekFeedback(int seconds, {bool persist = false}) {
    setState(() { _seekDeltaSeconds = seconds; _showSeekOverlay = true; });
    if (!persist) {
      _seekOverlayTimer?.cancel();
      _seekOverlayTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() { _showSeekOverlay = false; _seekDeltaSeconds = 0; });
      });
    }
  }

  Future<void> _adjustVolume(double delta) async {
    final v = (_currentVolume + delta).clamp(0.0, 1.0);
    setState(() { _currentVolume = v; _showVolumeBar = true; _showBrightnessBar = false; });
    _volumeBarTimer?.cancel();
    _volumeBarTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showVolumeBar = false);
    });
    if (!_isTizen) {
      try { await _kVolumeChannel.invokeMethod('setVolume', {'value': v}); } catch (_) {}
    } else {
      await _player.setVolume(v);
    }
  }

  Future<void> _adjustBrightness(double delta) async {
    if (_isTV) return;
    final b = (_currentBrightness + delta).clamp(0.0, 1.0);
    setState(() { _currentBrightness = b; _showBrightnessBar = true; _showVolumeBar = false; });
    _brightnessBarTimer?.cancel();
    _brightnessBarTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showBrightnessBar = false);
    });
    try { await _kBrightnessChannel.invokeMethod('setBrightness', {'value': b}); } catch (_) {}
  }

  // ── Touches télécommande Samsung ──────────────────────────────────────────
  void _registerTizenKeys() {
    final mapper = TizenKeyMapper.instance;

    // Touches media → contrôle lecture
    mapper.onPlayPause   = _togglePlay;
    mapper.onStop        = () => Navigator.pop(context);
    mapper.onRewind      = () => _seek(const Duration(seconds: -30));
    mapper.onFastForward = () => _seek(const Duration(seconds: 30));

    // Chaîne suivante / précédente (Live uniquement)
    mapper.onNext     = _isLive ? () => _zapRelative(1)  : null;
    mapper.onPrevious = _isLive ? () => _zapRelative(-1) : null;

    // Info → affiche l'overlay EPG
    mapper.onInfo = () {
      _startHideTimer();
      // Affiche les contrôles — l'EPG y est visible
    };

    // Boutons couleur → settings, favoris, etc.
    // Ces actions sont gérées par HomeScreen quand on n'est pas dans le player.
    // Dans le player, on garde les couleurs pour les shortcuts media.
    mapper.onRed    = _openSettings;
    mapper.onGreen  = () {
      // Toggle favori de la chaîne courante
      if (widget.streamId != 0) {
        try {
          context.read<IptvProvider>().toggleFavorite(
            // Créer un Channel minimal pour toggleFavorite
            _currentChannelForFav(),
            widget.tabIndex,
          );
          _startHideTimer();
        } catch (_) {}
      }
    };
    mapper.onYellow = null; // réservé
    mapper.onBlue   = null; // réservé

    // Numpad → zap direct par numéro (futur)
    mapper.onDigit = null; // TODO : saisie numérique canal
  }

  // Helper : Channel minimal pour toggleFavorite
  Channel _currentChannelForFav() {
    return Channel(
      streamId:            widget.streamId,
      name:                widget.title,
      streamIcon:          widget.streamIcon,
      categoryId:          '',
      containerExtension:  '',
      streamUrl:           widget.streamUrl,
    );
  }
  void _lockScreen() {
    _hideTimer?.cancel();
    setState(() { _isLocked = true; _showUnlockHint = false; _showControls = false; });
  }

  void _unlockScreen() {
    setState(() { _isLocked = false; _showUnlockHint = false; });
    _unlockHintTimer?.cancel();
    _startHideTimer();
  }

  void _onTapWhenLocked() {
    _unlockHintTimer?.cancel();
    setState(() => _showUnlockHint = true);
    _unlockHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showUnlockHint = false);
    });
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel(); _sleepCountdownTimer?.cancel();
    setState(() { _sleepMinutes = minutes; _sleepStartedAt = DateTime.now(); _sleepSecondsLeft = minutes * 60; });
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (mounted) Navigator.pop(context);
    });
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() { _sleepSecondsLeft = (_sleepSecondsLeft - 1).clamp(0, minutes * 60); });
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel(); _sleepCountdownTimer?.cancel();
    setState(() { _sleepMinutes = null; _sleepStartedAt = null; _sleepSecondsLeft = 0; });
  }

  String _fmtSleep(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onSwipeZap(DragEndDetails d) {
    if (!_isLive || _isTV) return;
    final channels = widget.liveChannels;
    if (channels == null || channels.isEmpty) return;
    if ((d.primaryVelocity ?? 0).abs() < 300) return;
    final next = (d.primaryVelocity! > 0)
        ? (_zapIndex - 1 + channels.length) % channels.length
        : (_zapIndex + 1) % channels.length;
    _zapTo(next);
  }

  /// Zap relatif : +1 = chaîne suivante, -1 = précédente.
  /// Utilisé par TizenKeyMapper (touches ChannelUp/ChannelDown télécommande).
  void _zapRelative(int delta) {
    final channels = widget.liveChannels;
    if (channels == null || channels.isEmpty) return;
    final next = (_zapIndex + delta).clamp(0, channels.length - 1);
    if (next == _zapIndex) return;
    _zapTo(next);
  }

  void _zapTo(int index) {
    final channels = widget.liveChannels;
    if (channels == null || index < 0 || index >= channels.length) return;
    final ch = channels[index]; final prov = context.read<IptvProvider>();
    final url = prov.getStreamUrl(ch, tabIndex: 1);
    setState(() {
      _zapIndex = index; _zapTitle = ch.name; _zapIcon = ch.streamIcon;
      _hasError = false; _isBufferingInitial = true; _hasPlayedOnce = false; _showZapBadge = true;
    });
    if (ch.streamId != 0) {
      prov.addToHistory(streamUrl: url, title: ch.name, streamIcon: ch.streamIcon, tabIndex: 1, streamId: ch.streamId);
    }
    _stallWatchdog?.cancel(); _stallTickCount = 0; _lastSilentReconnectAt = null;
    _silentRetryCount = 0; _isReconnecting = false; _bufferTimeoutTimer?.cancel();
    _player.open(url, headers: _headers);
    _startBufferTimeout();
    _zapBadgeTimer?.cancel();
    _zapBadgeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showZapBadge = false);
    });
  }

  void _openSettings() {
    setState(() => _showSettings = true);
    _settingsAnim.forward();
    _hideTimer?.cancel();
    if (!_showControls) setState(() => _showControls = true);
  }

  void _closeSettings() {
    _settingsAnim.reverse().then((_) { if (mounted) setState(() => _showSettings = false); });
    _startHideTimer();
  }

  void _setAudioTrack(TrackInfo t) {
    _player.setAudioTrack(t);
    setState(() => _currentAudio = t);
  }

  void _setSubtitleTrack(TrackInfo t) {
    _player.setSubtitleTrack(t);
    setState(() => _currentSubtitle = t);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_showEndScreen) return _buildEndScreen();
    if (_hasError)      return _buildErrorScreen();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        _buildPlayerBody(),
        if (_isBufferingInitial) _buildLoadingOverlay(),
      ]),
    );
  }

  Widget _buildPlayerBody() {
    final sizes = context.tvSizes;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        _startHideTimer();
        switch (event.logicalKey) {
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.enter:
            if (_showSettings) { _closeSettings(); return KeyEventResult.handled; }
            _togglePlay(); return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowLeft:
            if (!_showSettings) {
              if (_isLive && widget.liveChannels != null) {
                // Live TV : flèche gauche = chaîne précédente
                if (_zapIndex > 0) _zapTo(_zapIndex - 1);
              } else if (!_isLive) {
                _seek(const Duration(seconds: -10));
                _showSeekFeedback(-10);
              }
              return KeyEventResult.handled;
            }
          case LogicalKeyboardKey.arrowRight:
            if (!_showSettings) {
              if (_isLive && widget.liveChannels != null) {
                // Live TV : flèche droite = chaîne suivante
                final channels = widget.liveChannels!;
                if (_zapIndex < channels.length - 1) _zapTo(_zapIndex + 1);
              } else if (!_isLive) {
                _seek(const Duration(seconds: 10));
                _showSeekFeedback(10);
              }
              return KeyEventResult.handled;
            }

          case LogicalKeyboardKey.arrowUp:
            if (!_showSettings) {
              if (_isLive && widget.liveChannels != null) {
                final channels = widget.liveChannels!;
                _zapTo((_zapIndex - 1 + channels.length) % channels.length);
              } else {
                _tvVolumeUp();
              }
              return KeyEventResult.handled;
            }
          case LogicalKeyboardKey.arrowDown:
            if (!_showSettings) {
              if (_isLive && widget.liveChannels != null) {
                final channels = widget.liveChannels!;
                _zapTo((_zapIndex + 1) % channels.length);
              } else {
                _tvVolumeDown();
              }
              return KeyEventResult.handled;
            }

          case LogicalKeyboardKey.goBack:
          case LogicalKeyboardKey.escape:
          case LogicalKeyboardKey.backspace:
            if (_showSettings) { _closeSettings(); return KeyEventResult.handled; }
            Navigator.pop(context); return KeyEventResult.handled;

          case LogicalKeyboardKey.f5:
          case LogicalKeyboardKey.contextMenu:
            if (_showSettings) { _closeSettings(); } else { _openSettings(); }
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isLocked ? _onTapWhenLocked : _onTapVideo,
        onDoubleTapDown: (_isTV || _isLocked) ? null : _onDoubleTapSeek,
        onLongPressStart: (_isTV || _isLocked) ? null : (_) => _startSpeedBoost(),
        onLongPressEnd:   (_isTV || _isLocked) ? null : (_) => _stopSpeedBoost(),
        onPanStart:  (_isTV || _isLocked) ? null : _onPanStart,
        onPanUpdate: (_isTV || _isLocked) ? null : _onPanUpdate,
        onPanEnd:    (_isTV || _isLocked) ? null : _onPanEnd,
        onVerticalDragEnd: (_isLive && !_isTV && !_isLocked) ? _onSwipeZap : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _player.buildVideoWidget(),
            AnimatedOpacity(
              opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _isTV ? _buildTVOverlay(sizes) : _buildMobileOverlay(),
              ),
            ),
            // [v8] Buffering spinner violet avec fond glassmorphism
            if (_showBufferingSpinner && !_showControls && !_isSpeedBoost)
              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      width: 56, height: 56,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(AppTheme.violet.withOpacity(0.9)),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            if (_showSeekOverlay)   _buildSeekOverlay(),
            if (!_isTV && _showVolumeBar)
              _buildSideBar(
                icon: _currentVolume == 0 ? Icons.volume_off_rounded
                    : _currentVolume < 0.5 ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                value: _currentVolume, color: Colors.white, isLeft: true),
            if (!_isTV && _showBrightnessBar)
              _buildSideBar(icon: Icons.brightness_6_rounded, value: _currentBrightness,
                  color: AppTheme.gold, isLeft: false),
            if (!_isTV && _showTapRipple) _buildTapRipple(),
            if (!_isTV && _isSpeedBoost)  _buildSpeedBoostBadge(),
            if (_showSettings)
              Positioned.fill(child: GestureDetector(onTap: _closeSettings,
                  child: Container(color: Colors.transparent))),
            _buildSettingsPanel(sizes),
            _buildZapBadge(),
            // Lock screen overlay
            if (_isLocked) _buildLockOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Lock screen overlay ───────────────────────────────────────────────────
  Widget _buildLockOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _isLocked ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Stack(children: [
          // Fond semi-transparent léger
          Container(color: Colors.black.withOpacity(0.15)),

          // Bouton unlock centré (visible seulement si hint)
          if (_showUnlockHint)
            Center(
              child: GestureDetector(
                onTap: _unlockScreen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.4), blurRadius: 20)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      context.read<LanguageProvider>().l10n.t('player_unlock'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ).animate()
                  .fadeIn(duration: 180.ms)
                  .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1),
                      duration: 220.ms, curve: Curves.easeOutBack),
            ),

          // Icône lock en bas à droite — toujours visible
          Positioned(
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            right: 20,
            child: GestureDetector(
              onTap: _onTapWhenLocked,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _showUnlockHint
                      ? AppTheme.violet.withOpacity(0.3)
                      : Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _showUnlockHint
                        ? AppTheme.violet.withOpacity(0.7)
                        : Colors.white.withOpacity(0.2),
                  ),
                  boxShadow: _showUnlockHint
                      ? [BoxShadow(
                          color: AppTheme.violet.withOpacity(0.4),
                          blurRadius: 12)]
                      : null,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  color: _showUnlockHint ? AppTheme.violet : Colors.white70,
                  size: 18,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Overlay MOBILE ────────────────────────────────────────────────────────

  Widget _buildMobileOverlay() {
    final l = context.read<LanguageProvider>().l10n;
    return Column(
      children: [
        // ── Top band (gradient cinématique + contenu) ──
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xD8000000), Color(0x80000000), Colors.transparent],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: Row(children: [
                _circleBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context), size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(_zapTitle.isNotEmpty ? _zapTitle : widget.title,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 12, color: Colors.black)],
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (_isLive && (_epgCurrent.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_epgCurrent,
                            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ]),
                ),
                // Sleep badge
                if (_sleepMinutes != null) ...[
                  GestureDetector(
                    onTap: _cancelSleepTimer,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.gold.withOpacity(0.5)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.timer_rounded, color: AppTheme.gold, size: 12),
                        const SizedBox(width: 4),
                        Text(_fmtSleep(_sleepSecondsLeft),
                            style: const TextStyle(color: AppTheme.gold, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ],
                if (_isLive) ...[_liveBadge(), const SizedBox(width: 8)],
                if (_isOffline) ...[_offlineBadge(), const SizedBox(width: 8)],
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 18),
                  ),
                  color: const Color(0xF012101E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (v) {
                    switch (v) {
                      case 'settings': _showSettings ? _closeSettings() : _openSettings();
                      case 'lock': _lockScreen();
                      case 'pip': if (!_isTizen) _enterPip();
                      case 'multi': if (_isLive && widget.liveChannels != null) {
                        final channel = Channel(
                          name: widget.title, streamUrl: widget.streamUrl,
                          streamIcon: widget.streamIcon, streamId: widget.streamId, categoryId: '',
                        );
                        Navigator.pushReplacement(context, PageRouteBuilder(
                          pageBuilder: (_, __, ___) => MultiScreenView(
                            initialChannel: channel, liveChannels: widget.liveChannels),
                          transitionDuration: const Duration(milliseconds: 300),
                          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
                        ));
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'settings', child: Row(children: [
                      const Icon(Icons.tune_rounded, color: Colors.white70, size: 18),
                      const SizedBox(width: 10),
                      Text('Paramètres', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ])),
                    PopupMenuItem(value: 'lock', child: const Row(children: [
                      Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text('Verrouiller', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ])),
                    if (!_isTizen)
                      const PopupMenuItem(value: 'pip', child: Row(children: [
                        Icon(Icons.picture_in_picture_rounded, color: Colors.white70, size: 18),
                        SizedBox(width: 10),
                        Text('Picture-in-Picture', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ])),
                    if (_isLive && widget.liveChannels != null)
                      const PopupMenuItem(value: 'multi', child: Row(children: [
                        Icon(Icons.grid_view_rounded, color: Colors.white70, size: 18),
                        SizedBox(width: 10),
                        Text('Multi-écrans', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ])),
                  ],
                ),
              ]),
            ),
          ),
        ),
        // EPG séparé (si live et EPG suivant)
        if (_isLive && _epgNext.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Align(alignment: Alignment.centerLeft, child: _buildEpgNextBadge()),
          ),
        // ── Zone centrale (boutons play/seek + flèches nav chaînes) ──
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Boutons play/seek centraux
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!_isLive) ...[
                    _seekBtn(Icons.replay_10_rounded, () => _seek(const Duration(seconds: -10)), size: 28),
                    const SizedBox(width: 24),
                  ],
                  _buildPlayPause(btnSize: 64, iconSize: 34),
                  if (!_isLive) ...[
                    const SizedBox(width: 24),
                    _seekBtn(Icons.forward_10_rounded, () => _seek(const Duration(seconds: 10)), size: 28),
                  ],
                ]),
              ),
              // Flèches navigation chaînes (Live uniquement)
              if (_isLive && widget.liveChannels != null && widget.liveChannels!.length > 1)
                _buildChannelNavArrows(),
            ],
          ),
        ),
        // ── Bottom band (gradient cinématique + progress) ──
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Color(0xF0000000), Color(0x90000000), Colors.transparent],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              child: _buildProgressArea(),
            ),
          ),
        ),
      ],
    );
  }

  // ── Flèches navigation chaînes ────────────────────────────────────────────
  // Affichées en Live uniquement, côté gauche = précédente, côté droit = suivante.
  // Masquées si première (pas de gauche) ou dernière chaîne (pas de droite).
  // Preview nom + logo de la chaîne cible sous chaque flèche.
  Widget _buildChannelNavArrows({bool isTV = false, TVSizes? tvSizes}) {
    final channels   = widget.liveChannels!;
    final hasPrev    = _zapIndex > 0;
    final hasNext    = _zapIndex < channels.length - 1;
    final btnSize    = isTV ? (tvSizes?.btnSize ?? 56.0) : 48.0;
    final iconSize   = isTV ? 28.0 : 22.0;
    final isTizen    = Platform.operatingSystem == 'tizen';

    // Pill de preview : logo + nom de la chaîne cible
    Widget channelPreview(Channel ch) {
      final logoSize = isTV ? 20.0 : 16.0;
      final fs       = isTV ? (tvSizes?.labelFontSize ?? 10.0) : 9.0;
      Widget pill = Container(
        constraints: BoxConstraints(maxWidth: isTV ? 130.0 : 96.0),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(isTizen ? 0.65 : 0.42),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: ch.streamIcon.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: ch.streamIcon,
                    width: logoSize, height: logoSize,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 80),
                    errorWidget: (_, __, ___) => Icon(
                        Icons.live_tv_rounded, color: Colors.white38, size: logoSize))
                : Icon(Icons.live_tv_rounded, color: Colors.white38, size: logoSize),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(ch.name,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: fs,
                    fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
      if (!isTizen) {
        pill = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: pill,
          ),
        );
      }
      return pill;
    }

    Widget navBtn({required bool isPrev, required VoidCallback onTap}) {
      Widget btn = GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: btnSize, height: btnSize,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(isTizen ? 0.65 : 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
          ),
          child: Icon(
            isPrev ? Icons.arrow_back_ios_new_rounded : Icons.arrow_forward_ios_rounded,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      );

      // Glassmorphism (bypass Tizen)
      if (!isTizen) {
        btn = ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: btn,
          ),
        );
      }
      return btn;
    }

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTV ? 40.0 : 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flèche gauche — chaîne précédente + preview
            if (hasPrev)
              Column(mainAxisSize: MainAxisSize.min, children: [
                navBtn(isPrev: true, onTap: () => _zapTo(_zapIndex - 1)),
                const SizedBox(height: 8),
                channelPreview(channels[_zapIndex - 1]),
              ])
            else
              SizedBox(width: btnSize),

            // Espace central — ne rien mettre pour ne pas bloquer le play/pause
            const Spacer(),

            // Flèche droite — chaîne suivante + preview
            if (hasNext)
              Column(mainAxisSize: MainAxisSize.min, children: [
                navBtn(isPrev: false, onTap: () => _zapTo(_zapIndex + 1)),
                const SizedBox(height: 8),
                channelPreview(channels[_zapIndex + 1]),
              ])
            else
              SizedBox(width: btnSize),
          ],
        ),
      ),
    );
  }

  // Badge EPG "suivant" inline
  Widget _buildEpgNextBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _epgBadge('SUIVANT', Colors.white.withOpacity(0.1)),
        const SizedBox(width: 6),
        Flexible(child: Text(_epgNext,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── Overlay TV (Android TV + Samsung Tizen) ───────────────────────────────

  Widget _buildTVOverlay(TVSizes sizes) {
    final l = context.read<LanguageProvider>().l10n;
    return Column(children: [
      // ── Top bar TV ──────────────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xD8000000), Color(0x70000000), Colors.transparent],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        padding: EdgeInsets.fromLTRB(sizes.contentPadding.left, 28, sizes.contentPadding.right, 24),
        child: Row(children: [
          _tvCircleBtn(Icons.arrow_back_rounded, () => Navigator.pop(context), sizes),
          SizedBox(width: sizes.cardGap * 1.5),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(_zapTitle.isNotEmpty ? _zapTitle : widget.title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: sizes.titleFontSize * 0.7,
                  fontWeight: FontWeight.w800,
                  shadows: const [Shadow(blurRadius: 16, color: Colors.black)],
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_isLive && _epgCurrent.isNotEmpty) ...[
              SizedBox(height: 4),
              Text(_epgCurrent,
                  style: TextStyle(color: Colors.white.withOpacity(0.5),
                      fontSize: sizes.bodyFontSize * 0.9),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ])),
          if (_sleepMinutes != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: EdgeInsets.only(right: sizes.cardGap),
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.gold.withOpacity(0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_rounded, color: AppTheme.gold, size: sizes.iconSize * 0.7),
                SizedBox(width: sizes.cardGap / 2),
                Text(_fmtSleep(_sleepSecondsLeft),
                    style: TextStyle(color: AppTheme.gold, fontSize: sizes.bodyFontSize,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
          if (_isLive) ...[_liveBadge(large: true, sizes: sizes), SizedBox(width: sizes.cardGap)],
          // Multi-écrans TV
          if (_isLive && widget.liveChannels != null) ...[
            _tvCircleBtn(Icons.grid_view_rounded, () {
              final channel = Channel(
                name: widget.title,
                streamUrl: widget.streamUrl,
                streamIcon: widget.streamIcon,
                streamId: widget.streamId,
                categoryId: '',
              );
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => MultiScreenView(
                    initialChannel: channel,
                    liveChannels: widget.liveChannels,
                  ),
                  transitionDuration: const Duration(milliseconds: 300),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                ),
              );
            }, sizes),
            SizedBox(width: sizes.cardGap),
          ],
          _tvCircleBtn(Icons.tune_rounded, _showSettings ? _closeSettings : _openSettings, sizes,
              active: _showSettings),
        ]),
      ),

      // ── Contrôles centraux TV ───────────────────────────────────────────
      Expanded(child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!_isLive) ...[
              _tvSeekBtn(Icons.replay_10_rounded, () {
                _seek(const Duration(seconds: -10)); _showSeekFeedback(-10);
              }, sizes),
              SizedBox(width: sizes.cardGap * 3),
            ],
            _buildPlayPause(btnSize: sizes.playerBtnSize, iconSize: sizes.playerIconSize),
            if (!_isLive) ...[
              SizedBox(width: sizes.cardGap * 3),
              _tvSeekBtn(Icons.forward_10_rounded, () {
                _seek(const Duration(seconds: 10)); _showSeekFeedback(10);
              }, sizes),
            ],
          ])),
          // Flèches navigation chaînes TV (Live uniquement)
          if (_isLive && widget.liveChannels != null && widget.liveChannels!.length > 1)
            _buildChannelNavArrows(isTV: true, tvSizes: sizes),
        ],
      )),

      // ── Bottom TV ───────────────────────────────────────────────────────
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Color(0xF0000000), Color(0x70000000), Colors.transparent],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        padding: EdgeInsets.fromLTRB(
            sizes.contentPadding.left, 0, sizes.contentPadding.right, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildProgressAreaTV(sizes),
          if (_isTizen) ...[
            SizedBox(height: 12),
            _buildTizenHint(sizes),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildTizenHint(TVSizes sizes) {
    final hints = _isLive
        ? '↑↓ Chaîne précédente/suivante  ·  OK Lecture/Pause  ·  ← Retour'
        : '←→ ±10s  ·  OK Lecture/Pause  ·  ↑↓ Volume  ·  ← Retour';
    return Text(hints,
        style: TextStyle(color: Colors.white.withOpacity(0.3),
            fontSize: sizes.labelFontSize, letterSpacing: 0.5));
  }

  Widget _buildProgressAreaTV(TVSizes sizes) {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _player.state.duration;
        final pct = (!_isLive && dur.inMilliseconds > 0)
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (!_isLive) ...[
            Row(children: [
              Text(_fmt(pos), style: TextStyle(color: Colors.white70, fontSize: sizes.bodyFontSize)),
              const Spacer(),
              if (_playbackSpeed != 1.0)
                Container(
                  margin: EdgeInsets.only(right: sizes.cardGap),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientHorizontal,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '×${_playbackSpeed % 1 == 0 ? _playbackSpeed.toInt() : _playbackSpeed}',
                    style: TextStyle(color: Colors.white, fontSize: sizes.bodyFontSize,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              Text(_fmt(dur), style: TextStyle(color: Colors.white70, fontSize: sizes.bodyFontSize)),
            ]),
            SizedBox(height: sizes.cardGap / 2),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const _GradientTrackShape(),
                thumbShape: _GlowThumbShape(enabledThumbRadius: sizes.sliderThumbRadius),
                trackHeight: sizes.sliderTrackHeight,
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: AppTheme.violet,
                inactiveTrackColor: Colors.white.withOpacity(0.15),
                thumbColor: Colors.white,
              ),
              child: Slider(value: pct, onChanged: (v) {
                if (dur.inMilliseconds > 0)
                  _player.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
              }),
            ),
          ] else Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.7), blurRadius: 10)],
            ),
          ),
        ]);
      },
    );
  }

  // ── Settings Panel ────────────────────────────────────────────────────────

  Widget _buildSettingsPanel(TVSizes sizes) {
    final panelWidth = _isTV ? sizes.sidebarWidth + 60 : 290.0;
    final l = context.read<LanguageProvider>().l10n;
    return Positioned(
      top: 0, right: 0, bottom: 0, width: panelWidth,
      child: SlideTransition(
        position: _settingsSlide,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xF512101E), Color(0xF30D0D16)],
              ),
              border: Border(
                left: BorderSide(color: AppTheme.violet.withOpacity(0.35), width: 1.5),
              ),
              boxShadow: [
                BoxShadow(color: AppTheme.violet.withOpacity(0.06), blurRadius: 40, spreadRadius: 8),
              ],
            ),
            child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(18, _isTV ? 24 : 14, 14, 12),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientPrimary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.4), blurRadius: 10)],
                    ),
                    child: Icon(Icons.tune_rounded, color: Colors.white, size: _isTV ? sizes.iconSize * 0.7 : 14),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text(context.read<LanguageProvider>().l10n.t('player_playing'),
                      style: TextStyle(color: Colors.white,
                          fontSize: _isTV ? sizes.subtitleFontSize : 14,
                          fontWeight: FontWeight.w800))),
                  GestureDetector(onTap: _closeSettings,
                    child: Container(
                      width: _isTV ? sizes.btnSize * 0.5 : 28,
                      height: _isTV ? sizes.btnSize * 0.5 : 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(Icons.close_rounded, color: Colors.white54,
                          size: _isTV ? sizes.iconSize * 0.7 : 14),
                    ),
                  ),
                ]),
              ),
              Container(height: 1, color: Colors.white.withOpacity(0.06)),
              Expanded(child: ListView(padding: EdgeInsets.fromLTRB(18, 16, 18, 24), children: [
                // Vitesse
                if (!_isLive) ...[
                  _label(context.read<LanguageProvider>().l10n.t('player_speed'), sizes), SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: _speeds.map((s) {
                    final lbl = s == 1.0 ? 'Normal' : s % 1 == 0 ? '×${s.toInt()}' : '×$s';
                    return _chip(lbl, selected: _playbackSpeed == s, onTap: () => _setSpeed(s), sizes: sizes);
                  }).toList()),
                  SizedBox(height: 18),
                ],
                // Audio & sous-titres
                if (_player.supportsTrackSelection) ...[
                  if (_audioTracks.isNotEmpty) ...[
                    _label(context.read<LanguageProvider>().l10n.t('player_audio'), sizes), SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _chip('Auto', selected: _currentAudio.id == 'auto',
                          onTap: () => _setAudioTrack(TrackInfo.auto), sizes: sizes),
                      ..._audioTracks.asMap().entries.map((e) {
                        final t = e.value; if (t.id == 'auto') return const SizedBox.shrink();
                        return _chip(t.displayName, selected: _currentAudio.id == t.id,
                            onTap: () => _setAudioTrack(t), sizes: sizes);
                      }),
                    ]),
                    SizedBox(height: 18),
                  ],
                  _label(context.read<LanguageProvider>().l10n.t('player_subtitles'), sizes), SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip('Désactivé', selected: _currentSubtitle.id == 'no',
                        onTap: () => _setSubtitleTrack(TrackInfo.off), sizes: sizes),
                    _chip('Auto', selected: _currentSubtitle.id == 'auto',
                        onTap: () => _setSubtitleTrack(TrackInfo.auto), sizes: sizes),
                    ..._subTracks.asMap().entries.map((e) {
                      final t = e.value; if (t.id == 'auto' || t.id == 'no') return const SizedBox.shrink();
                      return _chip(t.displayName, selected: _currentSubtitle.id == t.id,
                          onTap: () => _setSubtitleTrack(t), sizes: sizes);
                    }),
                  ]),
                  SizedBox(height: 18),
                ] else ...[
                  _label('PISTES AUDIO / SOUS-TITRES', sizes), SizedBox(height: 8),
                  Text(context.read<LanguageProvider>().l10n.t('player_samsung_auto'),
                      style: TextStyle(color: Colors.white.withOpacity(0.35),
                          fontSize: _isTV ? sizes.bodyFontSize : 11)),
                  SizedBox(height: 18),
                ],
                // Sleep timer
                _label('SLEEP TIMER', sizes), SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _kSleepOptions.map((m) {
                  return _chip('${m}min', selected: _sleepMinutes == m,
                      onTap: () { _setSleepTimer(m); _closeSettings(); }, sizes: sizes);
                }).toList()),
                if (_sleepMinutes != null) ...[
                  SizedBox(height: 8),
                  GestureDetector(onTap: _cancelSleepTimer,
                    child: Text('${context.read<LanguageProvider>().l10n.t('cancel')} (${_fmtSleep(_sleepSecondsLeft)})',
                        style: TextStyle(color: AppTheme.red,
                            fontSize: _isTV ? sizes.bodyFontSize : 11,
                            fontWeight: FontWeight.w600))),
                ],
                SizedBox(height: 18),
                _label(context.read<LanguageProvider>().l10n.t('player_info'), sizes), SizedBox(height: 8),
                _infoRow('Type', _isLive ? 'Direct' : widget.tabIndex == 2 ? 'Film' : 'Série', sizes),
                _infoRow('Plateforme', _isTizen ? 'Samsung Tizen' : Platform.isAndroid ? 'Android' : 'Mobile', sizes),
              ])),
            ])),
          ),
        ),
      ),
    );
  }

  // ── Seek overlay ─────────────────────────────────────────────────────────

  Widget _buildSeekOverlay() {
    final isForward = _seekDeltaSeconds >= 0;
    final abs = _seekDeltaSeconds.abs();
    final sizes = context.tvSizes;
    final accentColor = isForward ? AppTheme.violet : AppTheme.red;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_isTV ? 20 : 16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: _isTV ? 32 : 22, vertical: _isTV ? 18 : 13),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(_isTV ? 20 : 16),
              border: Border.all(color: accentColor.withOpacity(0.55), width: 1.5),
              boxShadow: [
                BoxShadow(color: accentColor.withOpacity(0.18), blurRadius: 24, spreadRadius: 2),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                  color: accentColor, size: _isTV ? sizes.iconSize * 1.2 : 26,
                ),
              ),
              SizedBox(width: _isTV ? 14 : 10),
              Text(
                '${isForward ? '+' : '-'}${abs}s',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _isTV ? sizes.titleFontSize * 0.8 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Progress area mobile ─────────────────────────────────────────────────

  Widget _buildProgressArea() {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _player.state.duration;
        final pct = (!_isLive && dur.inMilliseconds > 0)
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (!_isLive) ...[
            Row(children: [
              Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const Spacer(),
              if (_playbackSpeed != 1.0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientHorizontal,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '×${_playbackSpeed % 1 == 0 ? _playbackSpeed.toInt() : _playbackSpeed}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const _GradientTrackShape(),
                thumbShape: const _GlowThumbShape(enabledThumbRadius: 6),
                trackHeight: 2.5,
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: AppTheme.violet,
                inactiveTrackColor: Colors.white.withOpacity(0.15),
                thumbColor: Colors.white,
              ),
              child: Slider(value: pct, onChanged: (v) {
                if (dur.inMilliseconds > 0)
                  _player.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
              }),
            ),
          ] else Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.7), blurRadius: 10)],
            ),
          ),
        ]);
      },
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────

  // [v8] Bouton play/pause : gradient+glow en pause, frosted en lecture
  Widget _buildPlayPause({required double btnSize, required double iconSize}) {
    return StreamBuilder<bool>(
      stream: _player.playingStream,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return GestureDetector(
          onTap: _togglePlay,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween(begin: 0.82, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: anim, child: child)),
            child: playing
                ? ClipOval(
                    key: const ValueKey(true),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: btnSize, height: btnSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                        ),
                        child: Icon(Icons.pause_rounded, size: iconSize, color: Colors.white),
                      ),
                    ),
                  )
                : Container(
                    key: const ValueKey(false),
                    width: btnSize, height: btnSize,
                    decoration: BoxDecoration(
                      gradient: AppTheme.gradientPrimary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppTheme.violet.withOpacity(0.55), blurRadius: 28, spreadRadius: 2),
                        BoxShadow(color: AppTheme.violet.withOpacity(0.2), blurRadius: 50, spreadRadius: 8),
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                    ),
                    child: Icon(Icons.play_arrow_rounded, size: iconSize, color: Colors.white),
                  ),
          ),
        );
      },
    );
  }

  // [v8] Boutons circulaires glassmorphism
  Widget _circleBtn(IconData icon, VoidCallback onTap, {double size = 34}) {
    final inner = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_isTizen ? 0.16 : 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.44),
    );
    return GestureDetector(
      onTap: onTap,
      child: _isTizen ? inner : ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: inner,
        ),
      ),
    );
  }

  // [v8] Boutons TV glassmorphism + gradient actif
  Widget _tvCircleBtn(IconData icon, VoidCallback onTap, TVSizes sizes, {bool active = false}) {
    final inner = Container(
      width: sizes.btnSize, height: sizes.btnSize,
      decoration: BoxDecoration(
        gradient: active ? AppTheme.gradientPrimary : null,
        color: active ? null : Colors.white.withOpacity(_isTizen ? 0.15 : 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? AppTheme.violet.withOpacity(0.8) : Colors.white.withOpacity(0.22),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 16)]
            : null,
      ),
      child: Icon(icon, color: active ? Colors.white : Colors.white70, size: sizes.iconSize),
    );
    return GestureDetector(
      onTap: onTap,
      child: _isTizen ? inner : ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: inner,
        ),
      ),
    );
  }

  // [v8] Seek buttons glassmorphism
  Widget _seekBtn(IconData icon, VoidCallback onTap, {required double size}) {
    final inner = Container(
      padding: EdgeInsets.all(size * 0.35),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_isTizen ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Icon(icon, color: Colors.white, size: size),
    );
    return GestureDetector(
      onTap: onTap,
      child: _isTizen ? inner : ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: inner,
        ),
      ),
    );
  }

  Widget _tvSeekBtn(IconData icon, VoidCallback onTap, TVSizes sizes) {
    final inner = Container(
      width: sizes.seekBtnSize, height: sizes.seekBtnSize,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_isTizen ? 0.14 : 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Icon(icon, color: Colors.white, size: sizes.seekIconSize),
    );
    return GestureDetector(
      onTap: onTap,
      child: _isTizen ? inner : ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: inner,
        ),
      ),
    );
  }

  // [v8] LIVE badge avec dot pulsant animé
  Widget _liveBadge({bool large = false, TVSizes? sizes}) {
    final fs = large && sizes != null ? sizes.labelFontSize : 9.0;
    final ps = large && sizes != null
        ? EdgeInsets.symmetric(horizontal: 12, vertical: 5)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 3);
    return Container(
      padding: ps,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF5252)]),
        borderRadius: BorderRadius.circular(5),
        boxShadow: [BoxShadow(color: AppTheme.red.withOpacity(0.5), blurRadius: 10, spreadRadius: 0)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _liveAnim,
          builder: (_, child) => Transform.scale(
            scale: 0.75 + 0.45 * _liveAnim.value,
            child: Opacity(opacity: 0.6 + 0.4 * _liveAnim.value, child: child),
          ),
          child: Icon(Icons.circle, color: Colors.white, size: large ? 9 : 6),
        ),
        SizedBox(width: 4),
        Text(context.read<LanguageProvider>().l10n.t('player_live'), style: TextStyle(
          color: Colors.white, fontSize: fs,
          fontWeight: FontWeight.w800, letterSpacing: 1.2,
        )),
      ]),
    );
  }

  Widget _offlineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.success.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.download_done_rounded,
            color: AppTheme.success, size: 10),
        SizedBox(width: 4),
        Text(context.read<LanguageProvider>().l10n.t('player_offline_badge'), style: TextStyle(
          color: AppTheme.success, fontSize: 9,
          fontWeight: FontWeight.w800, letterSpacing: 1.0,
        )),
      ]),
    );
  }

  // [v8] EPG overlay avec backdrop blur
  Widget _buildEpgOverlay({bool large = false, TVSizes? sizes}) {
    final fs1 = large && sizes != null ? sizes.bodyFontSize : 11.0;
    final fs2 = large && sizes != null ? sizes.bodyFontSize * 0.9 : 10.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.48),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (_epgCurrent.isNotEmpty)
              Row(children: [
                _epgBadge('EN COURS', AppTheme.red),
                const SizedBox(width: 6),
                Flexible(child: Text(_epgCurrent,
                    style: TextStyle(color: Colors.white, fontSize: fs1, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            if (_epgNext.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                _epgBadge('SUIVANT', Colors.white.withOpacity(0.1)),
                const SizedBox(width: 6),
                Flexible(child: Text(_epgNext,
                    style: TextStyle(color: Colors.white54, fontSize: fs2),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _epgBadge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)));

  // [v8] Zap badge glassmorphism + accent gauche gradient
  Widget _buildZapBadge() {
    final sizes = context.tvSizes;
    return Positioned(
      right: 20, bottom: 76,
      child: AnimatedOpacity(
        opacity: _showZapBadge ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
              ),
              child: IntrinsicHeight(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Left accent gradient
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
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: _isTV ? 14 : 10, vertical: _isTV ? 14 : 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: _zapIcon.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _zapIcon,
                                width: _isTV ? 54 : 38, height: _isTV ? 54 : 38,
                                fit: BoxFit.cover,
                                fadeInDuration: const Duration(milliseconds: 100),
                                errorWidget: (_, __, ___) => Icon(Icons.live_tv_rounded,
                                    color: Colors.white38, size: _isTV ? 40 : 28))
                            : Icon(Icons.live_tv_rounded, color: Colors.white38,
                                size: _isTV ? 40 : 28),
                      ),
                      SizedBox(width: _isTV ? 12 : 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${context.read<LanguageProvider>().l10n.t('player_channel_num')} ${_zapIndex + 1}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: _isTV ? sizes.labelFontSize : 10,
                              fontWeight: FontWeight.w500,
                            )),
                        const SizedBox(height: 2),
                        Text(_zapTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _isTV ? sizes.subtitleFontSize : 14,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Tap ripple / Speed boost ──────────────────────────────────────────────

  Widget _buildTapRipple() {
    return Positioned.fill(child: IgnorePointer(
        child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: _tapRippleLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: _tapRippleLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [(_tapRippleLeft ? AppTheme.red : AppTheme.violet).withOpacity(0.18), Colors.transparent],
              stops: const [0.0, 0.5],
            )),
            child: Align(
              alignment: _tapRippleLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_tapRippleLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                        color: Colors.white.withOpacity(0.85), size: 48),
                    const SizedBox(height: 4),
                    Text(_tapRippleLeft ? '-10s' : '+10s',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ])),
            ))));
  }

  // [v8] Sidebar volume/luminosité BackdropFilter pill
  Widget _buildSideBar({required IconData icon, required double value, required Color color, required bool isLeft}) {
    return Positioned(
      left: isLeft ? 20 : null, right: isLeft ? null : 20, top: 0, bottom: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 11),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: RotatedBox(quarterTurns: -1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.white.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 4,
                        ),
                      )),
                ),
                const SizedBox(height: 8),
                Text('${(value * 100).round()}',
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedBoostBadge() {
    return Positioned(top: 16, left: 0, right: 0, child: Center(
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 20, spreadRadius: 2)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(context.read<LanguageProvider>().l10n.t('player_speed_boost'), style: TextStyle(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ]))));
  }

  // ── Screens fin / erreur / chargement ────────────────────────────────────

  Widget _buildEndScreen() {
    final l = context.read<LanguageProvider>().l10n;
    final sizes = context.tvSizes;
    return Scaffold(backgroundColor: Colors.black, body: Center(
      child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: _isTV ? 90 : 68, height: _isTV ? 90 : 68,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.gradientPrimary,
                  boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 32, spreadRadius: 4)]),
              child: Icon(Icons.check_rounded, color: Colors.white, size: _isTV ? 44 : 34)),
          SizedBox(height: _isTV ? 32 : 22),
          Text(context.read<LanguageProvider>().l10n.t('player_ended'), style: TextStyle(color: Colors.white,
              fontSize: _isTV ? sizes.titleFontSize : 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(widget.title, style: TextStyle(color: Colors.white54,
              fontSize: _isTV ? sizes.bodyFontSize : 13),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          SizedBox(height: _isTV ? 48 : 36),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _actionBtn(Icons.arrow_back_rounded, context.read<LanguageProvider>().l10n.t('back'),
                color: Colors.white.withOpacity(0.1), onTap: () => Navigator.pop(context), sizes: sizes),
            SizedBox(width: 12),
            _actionBtn(Icons.replay_rounded, context.read<LanguageProvider>().l10n.t('retry'), gradient: AppTheme.gradientPrimary,
                onTap: () { setState(() => _showEndScreen = false); _manualRetry(); }, sizes: sizes),
          ]),
        ]),
      ),
    ));
  }

  Widget _buildErrorScreen() {
    final l = context.read<LanguageProvider>().l10n;
    final sizes = context.tvSizes;
    return Scaffold(backgroundColor: Colors.black, body: Center(
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
        child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(opacity: v,
              child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: _isTV ? 96 : 76, height: _isTV ? 96 : 76,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: AppTheme.red.withOpacity(0.1),
                    border: Border.all(color: AppTheme.red.withOpacity(0.4), width: 1.5)),
                child: Icon(Icons.signal_wifi_bad_rounded, color: AppTheme.red,
                    size: _isTV ? 44 : 34)),
            SizedBox(height: _isTV ? 32 : 22),
            Text(context.read<LanguageProvider>().l10n.t('player_impossible'), style: TextStyle(color: Colors.white,
                fontSize: _isTV ? sizes.titleFontSize : 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_errorMessage, style: TextStyle(color: Colors.white54,
                fontSize: _isTV ? sizes.bodyFontSize : 13, height: 1.5),
                textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
            SizedBox(height: _isTV ? 48 : 30),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _actionBtn(Icons.arrow_back_rounded, 'Retour',
                  color: Colors.white.withOpacity(0.1), onTap: () => Navigator.pop(context), sizes: sizes),
              const SizedBox(width: 12),
              _actionBtn(Icons.refresh_rounded, 'Réessayer',
                  gradient: AppTheme.gradientPrimary, onTap: _manualRetry, sizes: sizes),
            ]),
          ]),
        ),
      ),
    ));
  }

  // [v8] Loading overlay premium
  Widget _buildLoadingOverlay() {
    final sizes = context.tvSizes;
    return Container(
      color: Colors.black,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Icône chaîne avec border gradient
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 24)],
          ),
          child: Container(
            width: (_isTV ? 96 : 76) - 6,
            height: (_isTV ? 96 : 76) - 6,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: widget.streamIcon.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(imageUrl: widget.streamIcon, fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        errorWidget: (_, __, ___) => Icon(Icons.play_circle_outline_rounded,
                            color: Colors.white24, size: _isTV ? 48 : 36)))
                : Icon(Icons.play_circle_outline_rounded, color: Colors.white24,
                    size: _isTV ? 48 : 36),
          ),
        ),
        SizedBox(height: _isTV ? 28 : 20),
        Text(widget.title, style: TextStyle(color: Colors.white,
            fontSize: _isTV ? sizes.subtitleFontSize : 15, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        SizedBox(height: 6),
        Text(_isLive ? context.read<LanguageProvider>().l10n.t('player_connecting') : 'Chargement...',
            style: TextStyle(color: Colors.white.withOpacity(0.35),
                fontSize: _isTV ? sizes.bodyFontSize : 12)),
        SizedBox(height: _isTV ? 40 : 28),
        // Progress bar gradient animée
        SizedBox(
          width: _isTV ? 200 : 140,
          height: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              backgroundColor: Colors.white.withOpacity(0.07),
              valueColor: AlwaysStoppedAnimation(AppTheme.violet.withOpacity(0.7)),
              minHeight: 2,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Helpers texte/chips ───────────────────────────────────────────────────

  Widget _label(String text, TVSizes sizes) => Padding(padding: const EdgeInsets.only(bottom: 1),
      child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.35),
          fontSize: _isTV ? sizes.labelFontSize : 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.9)));

  // [v8] Chip avec gradient actif
  Widget _chip(String label, {required bool selected, required VoidCallback onTap, required TVSizes sizes}) {
    final fs = _isTV ? sizes.bodyFontSize : 12.0;
    final py = _isTV ? 10.0 : 7.0;
    final px = _isTV ? 16.0 : 12.0;
    return GestureDetector(onTap: onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
            decoration: BoxDecoration(
              gradient: selected ? AppTheme.gradientPrimary : null,
              color: selected ? null : Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                  color: selected ? AppTheme.violet.withOpacity(0.6) : Colors.white.withOpacity(0.1)),
              boxShadow: selected
                  ? [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 10)]
                  : null,
            ),
            child: Text(label, style: TextStyle(
                color: selected ? Colors.white : Colors.white.withOpacity(0.55),
                fontSize: fs, fontWeight: selected ? FontWeight.w700 : FontWeight.w400))));
  }

  Widget _infoRow(String key, String value, TVSizes sizes) =>
      Padding(padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text(key, style: TextStyle(color: Colors.white.withOpacity(0.3),
                fontSize: _isTV ? sizes.bodyFontSize : 11)),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(color: Colors.white70,
                fontSize: _isTV ? sizes.bodyFontSize : 11, fontWeight: FontWeight.w500)),
          ]));

  Widget _actionBtn(IconData icon, String label, {
    Color? color, LinearGradient? gradient, required VoidCallback onTap, required TVSizes sizes,
  }) {
    final fs = _isTV ? sizes.bodyFontSize : 13.0;
    final py = _isTV ? 14.0 : 11.0;
    final px = _isTV ? 24.0 : 18.0;
    return GestureDetector(onTap: onTap,
        child: Container(padding: EdgeInsets.symmetric(horizontal: px, vertical: py),
            decoration: BoxDecoration(
                color: gradient == null ? color : null, gradient: gradient,
                borderRadius: BorderRadius.circular(_isTV ? 16 : 12),
                boxShadow: gradient != null
                    ? [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 16)]
                    : null),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: _isTV ? sizes.iconSize * 0.8 : 16),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w600, fontSize: fs)),
            ])));
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  IVideoPlayer _createPlayer() {
    if (Platform.operatingSystem == 'tizen') {
      return TizenVideoPlayer();
    }
    return MediaKitPlayer(
      bufferSize: 64 * 1024 * 1024,
      enableHardwareAcceleration: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM SLIDER SHAPES — Track gradient violet→red + Thumb glow violet
// ═══════════════════════════════════════════════════════════════════════════════

class _GradientTrackShape extends RoundedRectSliderTrackShape {
  const _GradientTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = true,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.5;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(trackHeight / 2);
    final canvas = context.canvas;

    // Inactive track
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(thumbCenter.dx, trackRect.top, trackRect.right, trackRect.bottom),
        radius,
      ),
      Paint()..color = Colors.white.withOpacity(0.15),
    );

    // Active track — gradient violet→red
    final activeRect = Rect.fromLTRB(
        trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom);
    if (activeRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()
          ..shader = const LinearGradient(
            colors: [AppTheme.violet, AppTheme.red],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(activeRect),
      );
    }
  }
}

class _GlowThumbShape extends RoundSliderThumbShape {
  const _GlowThumbShape({super.enabledThumbRadius = 6});

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // Glow extérieur violet
    canvas.drawCircle(
      center,
      enabledThumbRadius + 5,
      Paint()
        ..color = AppTheme.violet.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Halo blanc subtil
    canvas.drawCircle(
      center,
      enabledThumbRadius + 2,
      Paint()..color = Colors.white.withOpacity(0.15),
    );
    // Thumb blanc
    canvas.drawCircle(center, enabledThumbRadius, Paint()..color = Colors.white);
  }
}