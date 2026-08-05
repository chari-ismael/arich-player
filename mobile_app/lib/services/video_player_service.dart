// lib/services/video_player_service.dart
//
// Arich Player — Abstraction lecteur vidéo v2.1
//
// Architecture :
//   player_screen.dart._createPlayer() :
//     Platform.operatingSystem == 'tizen' → TizenVideoPlayer()
//     Autres                              → MediaKitPlayer()
//
// Cette interface est implémentée par :
//   - media_kit_player.dart     (Android, Android TV)
//   - tizen_video_player.dart   (Samsung SmartTV / Tizen)
// ────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';

// ── Track info ────────────────────────────────────────────────────────────────

class TrackInfo {
  final String id;
  final String? title;
  final String? language;
  const TrackInfo({required this.id, this.title, this.language});

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (language != null && language!.isNotEmpty) return language!.toUpperCase();
    return id;
  }

  static const TrackInfo auto = TrackInfo(id: 'auto', title: 'Auto');
  static const TrackInfo off  = TrackInfo(id: 'no',   title: 'Désactivé');
}

// ── État du player ────────────────────────────────────────────────────────────

class VideoPlayerState {
  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final List<TrackInfo> audioTracks;
  final List<TrackInfo> subtitleTracks;
  final TrackInfo currentAudio;
  final TrackInfo currentSubtitle;
  final String? error;

  const VideoPlayerState({
    this.playing          = false,
    this.buffering        = false,
    this.completed        = false,
    this.position         = Duration.zero,
    this.duration         = Duration.zero,
    this.volume           = 1.0,
    this.rate             = 1.0,
    this.audioTracks      = const [],
    this.subtitleTracks   = const [],
    this.currentAudio     = TrackInfo.auto,
    this.currentSubtitle  = TrackInfo.off,
    this.error,
  });

  VideoPlayerState copyWith({
    bool?            playing,
    bool?            buffering,
    bool?            completed,
    Duration?        position,
    Duration?        duration,
    double?          volume,
    double?          rate,
    List<TrackInfo>? audioTracks,
    List<TrackInfo>? subtitleTracks,
    TrackInfo?       currentAudio,
    TrackInfo?       currentSubtitle,
    String?          error,
    bool             clearError = false,
  }) => VideoPlayerState(
    playing:         playing         ?? this.playing,
    buffering:       buffering       ?? this.buffering,
    completed:       completed       ?? this.completed,
    position:        position        ?? this.position,
    duration:        duration        ?? this.duration,
    volume:          volume          ?? this.volume,
    rate:            rate            ?? this.rate,
    audioTracks:     audioTracks     ?? this.audioTracks,
    subtitleTracks:  subtitleTracks  ?? this.subtitleTracks,
    currentAudio:    currentAudio    ?? this.currentAudio,
    currentSubtitle: currentSubtitle ?? this.currentSubtitle,
    error:           clearError ? null : (error ?? this.error),
  );
}

// ── Interface abstraite ───────────────────────────────────────────────────────

abstract class IVideoPlayer {
  Stream<VideoPlayerState> get stateStream;
  VideoPlayerState get state;
  Stream<bool>     get playingStream;
  Stream<bool>     get bufferingStream;
  Stream<bool>     get completedStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<String>   get errorStream;

  Widget buildVideoWidget({Key? key});

  Future<void> open(String url, {Map<String, String>? headers});
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlay();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setAudioTrack(TrackInfo track);
  Future<void> setSubtitleTrack(TrackInfo track);
  Future<void> setProperty(String key, String value);
  Future<void> dispose();

  bool get supportsTrackSelection;
  bool get supportsPlaybackRate;
}