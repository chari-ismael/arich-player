// lib/services/dead_stream_checker.dart
//
// Arich Player — Dead Stream Checker v1.1
//
// Vérifie en background si les streams favoris (Live) répondent toujours.
// Stocke les résultats dans Hive (box 'stream_health').
//
// COMPORTEMENT :
//   • Vérifie uniquement les favoris LIVE (tabIndex == 1)
//   • Ping HTTP HEAD avec timeout 8s
//   • Marque dead si : status >= 400 OU 2 timeouts consécutifs OU erreur réseau franche
//   • Un timeout seul ≠ mort (faux positifs sur connexion lente → seuil = 2)
//   • Re-vérifie toutes les 2h (configurable)
//   • Limite à 20 chaînes par batch, 5 en parallèle
//
// USAGE :
//   DeadStreamChecker.start(getFavorites: () => favsList);
//   final dead = DeadStreamChecker.isDead(streamUrl);
//   DeadStreamChecker.stop();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

const _kBoxName          = 'stream_health';
const _kInterval         = Duration(hours: 2);
const _kTimeout          = Duration(seconds: 8);
const _kMaxBatch         = 20;
const _kTimeoutThreshold = 2;

class DeadStreamChecker {
  DeadStreamChecker._();

  static Timer?  _timer;
  static bool    _running = false;
  static List<Map<String, dynamic>> Function()? _getFavorites;

  static final Map<String, _StreamHealth> _cache         = {};
  static final Map<String, int>           _timeoutCounts = {};

  // ── Démarrage ─────────────────────────────────────────────────────────────

  static Future<void> start({
    required List<Map<String, dynamic>> Function() getFavorites,
    Duration interval = _kInterval,
  }) async {
    if (_running) return;
    _running      = true;
    _getFavorites = getFavorites;

    if (!Hive.isBoxOpen(_kBoxName)) {
      await Hive.openBox(_kBoxName);
    }
    _loadCache();

    Future.delayed(const Duration(seconds: 30), _runCheck);
    _timer = Timer.periodic(interval, (_) => _runCheck());
    debugPrint('[DeadStreamChecker] Démarré (interval: ${interval.inMinutes}min)');
  }

  static void stop() {
    _running = false;
    _timer?.cancel();
    _timer        = null;
    _getFavorites = null;
    _timeoutCounts.clear();
    debugPrint('[DeadStreamChecker] Arrêté');
  }

  // ── API publique ──────────────────────────────────────────────────────────

  static bool isDead(String streamUrl) {
    final h = _cache[streamUrl];
    if (h == null) return false;
    return h.isDead;
  }

  static DateTime? lastChecked(String streamUrl) => _cache[streamUrl]?.checkedAt;

  static Future<bool> checkNow(String streamUrl) async {
    final dead = await _ping(streamUrl);
    _setResult(streamUrl, isDead: dead);
    return dead;
  }

  // ── Logique interne ───────────────────────────────────────────────────────

  static Future<void> _runCheck() async {
    if (!_running || _getFavorites == null) return;
    final favorites = _getFavorites!();

    final live = favorites
        .where((f) => (f['tabIndex'] as int? ?? 0) == 1)
        .take(_kMaxBatch)
        .toList();

    if (live.isEmpty) return;

    debugPrint('[DeadStreamChecker] Vérification de ${live.length} chaînes…');
    int dead = 0;

    final batches = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < live.length; i += 5) {
      batches.add(live.sublist(i, i + 5 > live.length ? live.length : i + 5));
    }

    for (final batch in batches) {
      if (!_running) break;
      await Future.wait(batch.map((f) async {
        final url = f['streamUrl'] as String? ?? '';
        if (url.isEmpty) return;
        final isDead = await _ping(url);
        _setResult(url, isDead: isDead);
        if (isDead) dead++;
      }));
    }

    debugPrint('[DeadStreamChecker] $dead/${live.length} streams morts détectés');
  }

  static Future<bool> _ping(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(_kTimeout);
      // Réponse reçue → reset timeout counter
      _timeoutCounts.remove(url);
      // 200–399 = vivant, 400+ = mort (serveur rejette explicitement)
      return response.statusCode >= 400;
    } on TimeoutException {
      // Timeout ≠ mort immédiat : connexion lente ou serveur chargé.
      // Marque mort uniquement après _kTimeoutThreshold timeouts consécutifs.
      final count = (_timeoutCounts[url] ?? 0) + 1;
      _timeoutCounts[url] = count;
      return count >= _kTimeoutThreshold;
    } catch (_) {
      // Erreur réseau franche (DNS, connexion refusée) = mort immédiat
      _timeoutCounts.remove(url);
      return true;
    }
  }

  static void _setResult(String url, {required bool isDead}) {
    final now = DateTime.now();
    _cache[url] = _StreamHealth(isDead: isDead, checkedAt: now);
    try {
      final box = Hive.box(_kBoxName);
      box.put(url.hashCode.toString(), {
        'url':        url,
        'dead':       isDead,
        'checked_at': now.toIso8601String(),
      });
    } catch (_) {}
  }

  static void _loadCache() {
    try {
      final box = Hive.box(_kBoxName);
      for (final key in box.keys) {
        final val = box.get(key);
        if (val is Map) {
          final url       = val['url']        as String? ?? '';
          final isDead    = val['dead']        as bool?   ?? false;
          final checkedAt = val['checked_at']  as String?;
          if (url.isNotEmpty) {
            _cache[url] = _StreamHealth(
              isDead:    isDead,
              checkedAt: checkedAt != null
                  ? DateTime.tryParse(checkedAt) ?? DateTime.now()
                  : DateTime.now(),
            );
          }
        }
      }
      debugPrint('[DeadStreamChecker] Cache chargé (${_cache.length} entrées)');
    } catch (_) {}
  }

  static Future<void> purgeOld() async {
    final cutoff   = DateTime.now().subtract(const Duration(hours: 24));
    final toRemove = _cache.entries
        .where((e) => e.value.checkedAt.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    for (final url in toRemove) {
      _cache.remove(url);
      _timeoutCounts.remove(url);
    }
    try {
      final box = Hive.box(_kBoxName);
      for (final url in toRemove) {
        box.delete(url.hashCode.toString());
      }
    } catch (_) {}
    if (toRemove.isNotEmpty) {
      debugPrint('[DeadStreamChecker] Purgé ${toRemove.length} entrées anciennes');
    }
  }
}

class _StreamHealth {
  final bool     isDead;
  final DateTime checkedAt;
  const _StreamHealth({required this.isDead, required this.checkedAt});
}