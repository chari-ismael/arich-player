// lib/services/tizen_video_player.dart
//
// Arich Player — Implémentation Tizen de IVideoPlayer
//
// Plateformes : Samsung Tizen (SmartTV)
// Utilise video_player + video_player_tizen (pub.dev)
//
// pubspec.yaml requis :
//   video_player: ^2.9.2
//   video_player_tizen: ^4.1.0
//
// ────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'video_player_service.dart';

class TizenVideoPlayer implements IVideoPlayer {
  VideoPlayerController? _controller;
  VideoPlayerState _state = const VideoPlayerState();

  final _stateCtrl    = StreamController<VideoPlayerState>.broadcast();
  final _playingCtrl  = StreamController<bool>.broadcast();
  final _bufferingCtrl= StreamController<bool>.broadcast();
  final _completedCtrl= StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _errorCtrl    = StreamController<String>.broadcast();

  // Polling position toutes les 500ms (video_player ne stream pas la position)
  Timer? _positionTimer;

  TizenVideoPlayer();

  // ── Listener interne ───────────────────────────────────────────────────────

  void _onControllerUpdate() {
    final ctrl = _controller;
    if (ctrl == null) return;

    final v = ctrl.value;
    final playing   = v.isPlaying;
    final buffering = v.isBuffering;
    final completed = v.position >= v.duration && v.duration > Duration.zero;
    final position  = v.position;
    final duration  = v.duration;

    final newState = _state.copyWith(
      playing:   playing,
      buffering: buffering,
      completed: completed,
      position:  position,
      duration:  duration,
      error:     v.hasError ? v.errorDescription : null,
    );

    final wasPlaying   = _state.playing;
    final wasBuffering = _state.buffering;
    final wasCompleted = _state.completed;

    _state = newState;
    _stateCtrl.add(newState);

    if (playing != wasPlaying) _playingCtrl.add(playing);
    if (buffering != wasBuffering) _bufferingCtrl.add(buffering);
    if (completed && !wasCompleted) _completedCtrl.add(true);
    _positionCtrl.add(position);

    if (v.hasError && v.errorDescription != null) {
      _errorCtrl.add(v.errorDescription!);
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _onControllerUpdate();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  Future<void> _disposeController() async {
    _stopPositionTimer();
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
  }

  // ── IVideoPlayer ──────────────────────────────────────────────────────────

  @override
  Stream<VideoPlayerState> get stateStream  => _stateCtrl.stream;
  @override
  VideoPlayerState get state => _state;
  @override
  Stream<bool>     get playingStream   => _playingCtrl.stream;
  @override
  Stream<bool>     get bufferingStream => _bufferingCtrl.stream;
  @override
  Stream<bool>     get completedStream => _completedCtrl.stream;
  @override
  Stream<Duration> get positionStream  => _positionCtrl.stream;
  @override
  Stream<Duration> get durationStream  => _durationCtrl.stream;
  @override
  Stream<String>   get errorStream     => _errorCtrl.stream;

  @override
  Widget buildVideoWidget({Key? key}) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Container(key: key, color: Colors.black);
    }
    return FittedBox(
      key: key,
      fit: BoxFit.contain,
      child: SizedBox(
        width:  ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
    );
  }

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    await _disposeController();

    _state = const VideoPlayerState(buffering: true);
    _stateCtrl.add(_state);

    // video_player_tizen supporte les headers HTTP
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? {},
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );

    _controller!.addListener(_onControllerUpdate);

    try {
      await _controller!.initialize();
      _update(_state.copyWith(
        buffering: false,
        duration: _controller!.value.duration,
      ));
      _durationCtrl.add(_controller!.value.duration);
      await _controller!.play();
      _startPositionTimer();
    } catch (e) {
      final msg = 'Erreur initialisation Tizen player: $e';
      _update(_state.copyWith(error: msg));
      _errorCtrl.add(msg);
    }
  }

  @override
  Future<void> play() async {
    await _controller?.play();
    _update(_state.copyWith(playing: true));
    _playingCtrl.add(true);
    _startPositionTimer();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
    _update(_state.copyWith(playing: false));
    _playingCtrl.add(false);
    _stopPositionTimer();
  }

  @override
  Future<void> togglePlay() async {
    if (_state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
    _update(_state.copyWith(position: position));
    _positionCtrl.add(position);
  }

  @override
  Future<void> setRate(double rate) async {
    await _controller?.setPlaybackSpeed(rate);
    _update(_state.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    await _controller?.setVolume(volume);
    _update(_state.copyWith(volume: volume));
  }

  // Tizen : tracks audio/sous-titres non accessibles via video_player API
  @override
  Future<void> setAudioTrack(TrackInfo track) async {
    // No-op sur Tizen — sélection auto par le MediaPlayer natif
    debugPrint('[TizenVideoPlayer] setAudioTrack: non supporté via video_player');
  }

  @override
  Future<void> setSubtitleTrack(TrackInfo track) async {
    // No-op sur Tizen
    debugPrint('[TizenVideoPlayer] setSubtitleTrack: non supporté via video_player');
  }

  @override
  Future<void> setProperty(String key, String value) async {
    // No-op sur Tizen — pas d'accès MPV
    debugPrint('[TizenVideoPlayer] setProperty($key) ignoré sur Tizen');
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    await _stateCtrl.close();
    await _playingCtrl.close();
    await _bufferingCtrl.close();
    await _completedCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _errorCtrl.close();
  }

  @override
  bool get supportsTrackSelection => false; // Tizen MediaPlayer gère ça nativement
  @override
  bool get supportsPlaybackRate   => true;  // video_player_tizen supporte setPlaybackSpeed

  void _update(VideoPlayerState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }
}