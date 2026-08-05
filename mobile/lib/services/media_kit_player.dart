// lib/services/media_kit_player.dart
//
// Arich Player — Implémentation media_kit de IVideoPlayer
//
// Plateformes : Android, Android TV, Windows, macOS, Linux
// NON utilisé sur Tizen (→ tizen_video_player.dart)

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'video_player_service.dart';

// ✅ Conditional import : NativePlayer uniquement sur plateformes natives
import 'media_kit_native_stub.dart'
    if (dart.library.io) 'media_kit_native_real.dart' as native_helper;

class MediaKitPlayer implements IVideoPlayer {
  late final Player _player;
  late final VideoController _controller;

  final _stateController = StreamController<VideoPlayerState>.broadcast();
  VideoPlayerState _state = const VideoPlayerState();

  final _playingCtrl    = StreamController<bool>.broadcast();
  final _bufferingCtrl  = StreamController<bool>.broadcast();
  final _completedCtrl  = StreamController<bool>.broadcast();
  final _positionCtrl   = StreamController<Duration>.broadcast();
  final _durationCtrl   = StreamController<Duration>.broadcast();
  final _errorCtrl      = StreamController<String>.broadcast();

  MediaKitPlayer({
    int bufferSize = 64 * 1024 * 1024,
    bool enableHardwareAcceleration = true,
  }) {
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: bufferSize,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: enableHardwareAcceleration,
      ),
    );
    _attachListeners();
  }

  void _attachListeners() {
    _player.stream.playing.listen((v) {
      _update(_state.copyWith(playing: v));
      if (!_playingCtrl.isClosed) _playingCtrl.add(v);
    });

    _player.stream.buffering.listen((v) {
      _update(_state.copyWith(buffering: v));
      if (!_bufferingCtrl.isClosed) _bufferingCtrl.add(v);
    });

    _player.stream.completed.listen((v) {
      _update(_state.copyWith(completed: v));
      if (!_completedCtrl.isClosed) _completedCtrl.add(v);
    });

    _player.stream.position.listen((v) {
      _update(_state.copyWith(position: v));
      if (!_positionCtrl.isClosed) _positionCtrl.add(v);
    });

    _player.stream.duration.listen((v) {
      _update(_state.copyWith(duration: v));
      if (!_durationCtrl.isClosed) _durationCtrl.add(v);
    });

    _player.stream.error.listen((err) {
      if (err.isNotEmpty) {
        _update(_state.copyWith(error: err));
        if (!_errorCtrl.isClosed) _errorCtrl.add(err);
      }
    });

    _player.stream.tracks.listen((tracks) {
      final audio = tracks.audio
          .where((t) => t.id != 'no')
          .map((t) => TrackInfo(id: t.id, title: t.title, language: t.language))
          .toList();
      final subs = tracks.subtitle
          .where((t) => t.id != 'no')
          .map((t) => TrackInfo(id: t.id, title: t.title, language: t.language))
          .toList();
      _update(_state.copyWith(audioTracks: audio, subtitleTracks: subs));
    });

    _player.stream.track.listen((track) {
      _update(_state.copyWith(
        currentAudio: TrackInfo(
          id: track.audio.id,
          title: track.audio.title,
          language: track.audio.language,
        ),
        currentSubtitle: TrackInfo(
          id: track.subtitle.id,
          title: track.subtitle.title,
          language: track.subtitle.language,
        ),
      ));
    });
  }

  void _update(VideoPlayerState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  @override
  Stream<VideoPlayerState> get stateStream => _stateController.stream;
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
  Widget buildVideoWidget({Key? key}) => Video(key: key, controller: _controller);

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    _update(_state.copyWith(
      completed: false, error: null,
      clearError: true, position: Duration.zero,
    ));
    await _player.open(Media(url, httpHeaders: headers ?? {}));
  }

  @override
  Future<void> play()   => _player.play();
  @override
  Future<void> pause()  => _player.pause();
  @override
  Future<void> togglePlay() =>
      _state.playing ? _player.pause() : _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) async {
    _update(_state.copyWith(rate: rate));
    await _player.setRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    _update(_state.copyWith(volume: volume));
    await _player.setVolume(volume * 100);
  }

  @override
  Future<void> setAudioTrack(TrackInfo track) async {
    final mkTrack = track.id == 'auto'
        ? AudioTrack.auto()
        : AudioTrack(track.id, track.title, track.language);
    await _player.setAudioTrack(mkTrack);
    _update(_state.copyWith(currentAudio: track));
  }

  @override
  Future<void> setSubtitleTrack(TrackInfo track) async {
    final mkTrack = track.id == 'no'
        ? SubtitleTrack.no()
        : track.id == 'auto'
            ? SubtitleTrack.auto()
            : SubtitleTrack(track.id, track.title, track.language);
    await _player.setSubtitleTrack(mkTrack);
    _update(_state.copyWith(currentSubtitle: track));
  }

  @override
  Future<void> setProperty(String key, String value) async {
    if (kIsWeb) return;
    try {
      await native_helper.setNativeProperty(_player, key, value);
    } catch (e) {
      debugPrint('[MediaKitPlayer] setProperty($key) error: $e');
    }
  }

  @override
  Future<void> dispose() async {
    // ⚠️ ORDRE CRITIQUE : disposer le player EN PREMIER pour stopper
    // tous les streams source (playing, buffering, position…) AVANT
    // de fermer les controllers — sinon les listeners continuent de
    // fire sur des controllers déjà fermés → "Bad state: Cannot add
    // new events after calling close"
    await _player.dispose();
    await _stateController.close();
    await _playingCtrl.close();
    await _bufferingCtrl.close();
    await _completedCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _errorCtrl.close();
  }

  @override
  bool get supportsTrackSelection => true;
  @override
  bool get supportsPlaybackRate   => true;

  Player get nativePlayer => _player;
  VideoController get nativeController => _controller;
}

// ignore: unused_element
final _registered = () {}();