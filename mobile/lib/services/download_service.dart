// lib/services/download_service.dart
//
// Arich Player — Download Service v1.0
//
// Gère le téléchargement VOD offline :
//   • Queue de téléchargement (max 3 simultanés)
//   • Pause / Resume / Cancel
//   • Persistence Hive (survit aux redémarrages)
//   • Lecture offline via chemin local
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// ── Statuts ───────────────────────────────────────────────────────────────────

enum DownloadStatus { queued, downloading, paused, completed, error }

// ── Modèle ────────────────────────────────────────────────────────────────────

class DownloadItem {
  final String id;           // streamId_episodeId ou streamId
  final String title;
  final String streamIcon;
  final String url;
  final String ext;          // mp4 / mkv / avi …
  final int    tabIndex;     // 2=film, 3=série
  final String? episodeTitle;
  final String? seasonLabel;

  DownloadStatus status;
  double         progress;   // 0.0 → 1.0
  int            totalBytes;
  int            receivedBytes;
  String?        localPath;
  String?        errorMsg;
  DateTime       addedAt;

  DownloadItem({
    required this.id,
    required this.title,
    required this.streamIcon,
    required this.url,
    required this.ext,
    required this.tabIndex,
    this.episodeTitle,
    this.seasonLabel,
    this.status       = DownloadStatus.queued,
    this.progress     = 0.0,
    this.totalBytes   = 0,
    this.receivedBytes = 0,
    this.localPath,
    this.errorMsg,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  bool get isCompleted  => status == DownloadStatus.completed;
  bool get isActive     => status == DownloadStatus.downloading;
  bool get canPlay      => isCompleted && localPath != null;

  String get displayTitle => episodeTitle != null
      ? '$title — $episodeTitle'
      : title;

  String get sizeLabel {
    if (totalBytes == 0) return '';
    final mb = totalBytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} Go'
        : '${mb.toStringAsFixed(0)} Mo';
  }

  Map<String, dynamic> toMap() => {
    'id':            id,
    'title':         title,
    'streamIcon':    streamIcon,
    'url':           url,
    'ext':           ext,
    'tabIndex':      tabIndex,
    'episodeTitle':  episodeTitle,
    'seasonLabel':   seasonLabel,
    'status':        status.index,
    'progress':      progress,
    'totalBytes':    totalBytes,
    'receivedBytes': receivedBytes,
    'localPath':     localPath,
    'errorMsg':      errorMsg,
    'addedAt':       addedAt.millisecondsSinceEpoch,
  };

  factory DownloadItem.fromMap(Map<dynamic, dynamic> m) {
    final idx = (m['status'] as int?) ?? 0;
    DownloadStatus st = DownloadStatus.values[idx.clamp(0, DownloadStatus.values.length - 1)];
    // Au redémarrage les "downloading" redeviennent "queued"
    if (st == DownloadStatus.downloading) st = DownloadStatus.queued;
    return DownloadItem(
      id:            m['id']?.toString() ?? '',
      title:         m['title']?.toString() ?? '',
      streamIcon:    m['streamIcon']?.toString() ?? '',
      url:           m['url']?.toString() ?? '',
      ext:           m['ext']?.toString() ?? 'mp4',
      tabIndex:      (m['tabIndex'] as int?) ?? 2,
      episodeTitle:  m['episodeTitle']?.toString(),
      seasonLabel:   m['seasonLabel']?.toString(),
      status:        st,
      progress:      (m['progress'] as num?)?.toDouble() ?? 0.0,
      totalBytes:    (m['totalBytes'] as int?) ?? 0,
      receivedBytes: (m['receivedBytes'] as int?) ?? 0,
      localPath:     m['localPath']?.toString(),
      errorMsg:      m['errorMsg']?.toString(),
      addedAt: m['addedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['addedAt'] as int)
          : DateTime.now(),
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class DownloadService extends ChangeNotifier {
  static const _kBoxName   = 'downloads';
  static const _kMaxActive = 2;   // max simultanés

  late Box _box;
  final List<DownloadItem> _items = [];
  final Map<String, _ActiveDownload> _active = {};

  List<DownloadItem> get items        => List.unmodifiable(_items);
  List<DownloadItem> get active       => _items.where((i) => i.isActive).toList();
  List<DownloadItem> get completed    => _items.where((i) => i.isCompleted).toList();
  List<DownloadItem> get queued       => _items.where((i) => i.status == DownloadStatus.queued).toList();
  int                get activeCount  => _active.length;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _box = await Hive.openBox(_kBoxName);
    _load();
    _processQueue();
  }

  void _load() {
    _items.clear();
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is Map) _items.add(DownloadItem.fromMap(raw));
      } catch (_) {}
    }
    _items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> _save(DownloadItem item) async {
    await _box.put(item.id, item.toMap());
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Retourne l'item existant si déjà téléchargé/en cours, sinon null.
  DownloadItem? find(String id) {
    try { return _items.firstWhere((i) => i.id == id); } catch (_) { return null; }
  }

  bool isDownloaded(String id) => find(id)?.isCompleted ?? false;
  bool isDownloading(String id) => find(id)?.isActive ?? false;
  bool isQueued(String id) => find(id)?.status == DownloadStatus.queued ?? false;

  /// Ajoute un film ou épisode à la queue.
  Future<void> enqueue(DownloadItem item) async {
    // Dédupe
    if (find(item.id) != null) return;
    _items.insert(0, item);
    await _save(item);
    notifyListeners();
    _processQueue();
  }

  /// Annule et supprime le fichier local.
  Future<void> cancel(String id) async {
    _active[id]?.cancel();
    _active.remove(id);
    final item = find(id);
    if (item != null) {
      if (item.localPath != null) {
        try { await File(item.localPath!).delete(); } catch (_) {}
      }
      _items.remove(item);
      await _box.delete(id);
      notifyListeners();
    }
    _processQueue();
  }

  /// Remet en queue un item en erreur.
  Future<void> retry(String id) async {
    final item = find(id);
    if (item == null) return;
    item.status        = DownloadStatus.queued;
    item.progress      = 0;
    item.receivedBytes = 0;
    item.errorMsg      = null;
    await _save(item);
    notifyListeners();
    _processQueue();
  }

  /// Supprime un téléchargement complété (fichier + entrée).
  Future<void> delete(String id) async {
    final item = find(id);
    if (item == null) return;
    if (item.localPath != null) {
      try { await File(item.localPath!).delete(); } catch (_) {}
    }
    _items.remove(item);
    await _box.delete(id);
    notifyListeners();
  }

  /// Supprime tous les téléchargements complétés.
  Future<void> deleteAllCompleted() async {
    final toDelete = completed.toList();
    for (final item in toDelete) {
      await delete(item.id);
    }
  }

  // ── Queue processor ────────────────────────────────────────────────────────

  void _processQueue() {
    if (_active.length >= _kMaxActive) return;
    final next = queued.take(_kMaxActive - _active.length).toList();
    for (final item in next) {
      _startDownload(item);
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    item.status = DownloadStatus.downloading;
    await _save(item);
    notifyListeners();

    final ad = _ActiveDownload();
    _active[item.id] = ad;

    try {
      final dir  = await _downloadsDir();
      final path = '${dir.path}/${item.id}.${item.ext}';
      final file = File(path);

      final client   = http.Client();
      ad.client      = client;
      final request  = http.Request('GET', Uri.parse(item.url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      item.totalBytes = response.contentLength ?? 0;
      final sink = file.openWrite();
      ad.sink    = sink;

      await for (final chunk in response.stream) {
        if (ad.cancelled) {
          await sink.close();
          try { await file.delete(); } catch (_) {}
          return;
        }
        sink.add(chunk);
        item.receivedBytes += chunk.length;
        if (item.totalBytes > 0) {
          item.progress = item.receivedBytes / item.totalBytes;
        }
        // Notifie toutes les 512 Ko pour éviter de flooder le UI
        if (item.receivedBytes % (512 * 1024) < chunk.length) {
          await _save(item);
          notifyListeners();
        }
      }

      await sink.close();
      item.localPath = path;
      item.progress  = 1.0;
      item.status    = DownloadStatus.completed;
    } catch (e) {
      if (!ad.cancelled) {
        item.status   = DownloadStatus.error;
        item.errorMsg = e.toString().replaceAll('Exception: ', '');
      }
    } finally {
      _active.remove(item.id);
      await _save(item);
      notifyListeners();
      _processQueue();
    }
  }

  Future<Directory> _downloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/arich_downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Taille totale utilisée ─────────────────────────────────────────────────

  Future<String> totalSizeLabel() async {
    int total = 0;
    for (final item in completed) {
      if (item.localPath != null) {
        try {
          total += await File(item.localPath!).length();
        } catch (_) {}
      }
    }
    final mb = total / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} Go'
        : '${mb.toStringAsFixed(0)} Mo';
  }

  @override
  void dispose() {
    for (final ad in _active.values) { ad.cancel(); }
    super.dispose();
  }
}

// ── Download handle interne ───────────────────────────────────────────────────

class _ActiveDownload {
  http.Client? client;
  IOSink?      sink;
  bool         cancelled = false;

  void cancel() {
    cancelled = true;
    try { sink?.close(); } catch (_) {}
    try { client?.close(); } catch (_) {}
  }
}