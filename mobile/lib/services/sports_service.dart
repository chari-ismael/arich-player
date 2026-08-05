// lib/services/sports_service.dart
//
// Arich Player — Sports Service
//
// Charge les matchs du jour via football-data.org (API gratuite, token inclus).
//
// ⚠️  SERVICE NON BRANCHÉ — dead code intentionnel.
//     Prévu pour une future section "Sport en direct" dans home_screen.dart.
//     Pour activer :
//       1. Importer dans home_screen.dart
//       2. Appeler SportsService.getTodayMatches() dans initState
//       3. Afficher les résultats dans un widget dédié (ex: _SportsBanner)
//
// API : https://www.football-data.org/documentation/quickstart
// Token gratuit : 37456dbe6c304322ac002e8ee3853025 (10 req/min)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SportMatch {
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final String time;
  final String status;
  final int?   homeScore;
  final int?   awayScore;

  const SportMatch({
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.time,
    required this.status,
    this.homeScore,
    this.awayScore,
  });

  /// true si le match est en cours (IN_PLAY ou PAUSED)
  bool get isLive => status == 'IN_PLAY' || status == 'PAUSED';

  /// true si terminé
  bool get isFinished => status == 'FINISHED';

  /// true si à venir
  bool get isUpcoming =>
      status == 'SCHEDULED' || status == 'TIMED';

  /// Score formaté "1 - 2" ou null si pas encore joué
  String? get scoreLabel {
    if (homeScore == null || awayScore == null) return null;
    return '$homeScore - $awayScore';
  }
}

class SportsService {
  static const String _token = '37456dbe6c304322ac002e8ee3853025';
  static const String _baseUrl = 'https://api.football-data.org/v4';

  /// Compétitions prioritaires à afficher en premier (IDs football-data.org)
  /// 2015 = Ligue 1, 2001 = Champions League, 2021 = Premier League,
  /// 2014 = La Liga, 2002 = Bundesliga, 2019 = Serie A
  static const _priorityCompetitionIds = {2015, 2001, 2021, 2014, 2002, 2019};

  /// Charge les matchs du jour (dateFrom = dateTo = aujourd'hui)
  static Future<List<SportMatch>> getTodayMatches() async {
    try {
      final today = DateTime.now();
      final date =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final uri = Uri.parse(
          '$_baseUrl/matches?dateFrom=$date&dateTo=$date');

      final response = await http.get(uri, headers: {
        'X-Auth-Token': _token,
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[SportsService] HTTP ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMatches = (data['matches'] as List?) ?? [];

      // Construire la liste de SportMatch
      final matches = rawMatches.map((m) {
        final home = m['homeTeam']?['shortName'] ??
            m['homeTeam']?['name'] ??
            '?';
        final away = m['awayTeam']?['shortName'] ??
            m['awayTeam']?['name'] ??
            '?';
        final comp = m['competition']?['name'] ?? '';
        final status = m['status'] as String? ?? '';
        final utcDate = m['utcDate'] as String? ?? '';

        String time = '';
        try {
          final dt = DateTime.parse(utcDate).toLocal();
          time =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } catch (_) {}

        // Score : halfTime si IN_PLAY/PAUSED, fullTime si FINISHED
        final scoreNode = (status == 'FINISHED')
            ? m['score']?['fullTime']
            : m['score']?['fullTime'] ?? m['score']?['halfTime'];

        final homeScore = scoreNode?['home'] as int?;
        final awayScore = scoreNode?['away'] as int?;

        return SportMatch(
          homeTeam: home,
          awayTeam: away,
          competition: comp,
          time: time,
          status: status,
          homeScore: homeScore,
          awayScore: awayScore,
        );
      }).toList();

      // Trier : en cours > à venir > terminés, puis compétitions prioritaires
      matches.sort((a, b) {
        int priority(SportMatch m) {
          if (m.isLive) return 0;
          if (m.isUpcoming) return 1;
          return 2;
        }
        final cmp = priority(a).compareTo(priority(b));
        if (cmp != 0) return cmp;
        return 0; // conserver l'ordre API pour les égalités
      });

      return matches;
    } catch (e) {
      debugPrint('[SportsService] error: $e');
      return [];
    }
  }

  /// Charge les matchs d'une date spécifique
  static Future<List<SportMatch>> getMatchesForDate(DateTime date) async {
    try {
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final uri = Uri.parse(
          '$_baseUrl/matches?dateFrom=$dateStr&dateTo=$dateStr');

      final response = await http.get(uri, headers: {
        'X-Auth-Token': _token,
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMatches = (data['matches'] as List?) ?? [];

      return rawMatches.map((m) {
        final home = m['homeTeam']?['shortName'] ??
            m['homeTeam']?['name'] ?? '?';
        final away = m['awayTeam']?['shortName'] ??
            m['awayTeam']?['name'] ?? '?';
        final comp = m['competition']?['name'] ?? '';
        final status = m['status'] as String? ?? '';
        final utcDate = m['utcDate'] as String? ?? '';

        String time = '';
        try {
          final dt = DateTime.parse(utcDate).toLocal();
          time =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } catch (_) {}

        final scoreNode = m['score']?['fullTime'];
        return SportMatch(
          homeTeam: home,
          awayTeam: away,
          competition: comp,
          time: time,
          status: status,
          homeScore: scoreNode?['home'] as int?,
          awayScore: scoreNode?['away'] as int?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[SportsService] getMatchesForDate error: $e');
      return [];
    }
  }
}