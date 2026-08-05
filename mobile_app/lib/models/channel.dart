// lib/models/channel.dart

import '../services/country_detector.dart';

class Channel {
  final int    streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String containerExtension;

  /// URL directe — renseignée uniquement pour les sources M3U.
  final String streamUrl;

  /// Identifiant EPG tvg-id (M3U)
  final String tvgId;

  /// group-title M3U ou nom de catégorie Xtream.
  final String groupTitle;

  /// Code pays/région ISO détecté automatiquement depuis [groupTitle] et [name].
  /// Ex: "FR", "ARAB", "DE", null si non détecté.
  final String? countryCode;

  /// Emoji drapeau correspondant au [countryCode], null si inconnu.
  final String? countryFlag;

  /// Nom pays/région localisé, null si inconnu.
  final String? countryName;

  /// Nom de base normalisé : sans suffixe qualité (SD/HD/FHD/4K/UHD).
  String get baseName => _extractBaseName(name);

  /// Suffixe qualité extrait du nom : SD / HD / FHD / 4K / UHD / ''
  String get qualityTag => _extractQuality(name);

  const Channel({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    this.containerExtension = 'mp4',
    this.streamUrl   = '',
    this.tvgId       = '',
    this.groupTitle  = '',
    this.countryCode = null,
    this.countryFlag = null,
    this.countryName = null,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    final groupTitle = json['category_name']?.toString() ?? '';
    final name       = json['name']?.toString() ?? 'Inconnu';
    final country    = _detectCountry(groupTitle, name);

    return Channel(
      streamId:           json['stream_id'] ?? (json['series_id'] ?? 0),
      name:               name,
      streamIcon:         json['stream_icon']?.toString() ?? (json['cover']?.toString() ?? ''),
      categoryId:         json['category_id']?.toString() ?? '0',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      streamUrl:          json['url']?.toString() ?? '',
      tvgId:              json['epg_channel_id']?.toString() ?? '',
      groupTitle:         groupTitle,
      countryCode:        country?.code,
      countryFlag:        country?.flag,
      countryName:        country?.name,
    );
  }

  /// Regroupe une liste de chaînes par [baseName].
  static Map<String, List<Channel>> groupBySource(List<Channel> channels) {
    final map = <String, List<Channel>>{};
    for (final ch in channels) {
      map.putIfAbsent(ch.baseName, () => []).add(ch);
    }
    const order = ['SD', 'HD', 'FHD', '4K', 'UHD', ''];
    for (final list in map.values) {
      list.sort((a, b) {
        final ai = order.indexOf(a.qualityTag);
        final bi = order.indexOf(b.qualityTag);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });
    }
    return map;
  }

  /// Regroupe une liste de chaînes par pays détecté.
  /// Clé = countryCode (ou '__unknown__' si non détecté).
  static Map<String, List<Channel>> groupByCountry(List<Channel> channels) {
    final map = <String, List<Channel>>{};
    for (final ch in channels) {
      final key = ch.countryCode ?? '__unknown__';
      map.putIfAbsent(key, () => []).add(ch);
    }
    return map;
  }
}

// ── Détection pays ────────────────────────────────────────────────────────────

CountryInfo? _detectCountry(String groupTitle, String channelName) {
  // Priorité 1 : depuis le group-title
  if (groupTitle.isNotEmpty) {
    final fromGroup = CountryDetector.detect(groupTitle);
    if (fromGroup != null) return fromGroup;
  }
  // Priorité 2 : depuis le nom de la chaîne (moins fiable, seulement contains)
  if (channelName.isNotEmpty) {
    final fromName = CountryDetector.detect(channelName);
    if (fromName != null) return fromName;
  }
  return null;
}

// ── Helpers qualité ────────────────────────────────────────────────────────────

final _qualityRe = RegExp(
  r'\s*[\[\(]?\s*(4K|UHD|FHD|HD|SD|720p?|1080[pi]?|2160p?|4096p?)\s*[\]\)]?\s*$',
  caseSensitive: false,
);

String _extractBaseName(String name) => name.replaceAll(_qualityRe, '').trim();

String _extractQuality(String name) {
  final m = _qualityRe.firstMatch(name);
  if (m == null) return '';
  final raw = m.group(1)?.toUpperCase() ?? '';
  if (raw == '720P' || raw == '720') return 'HD';
  if (raw == '1080P' || raw == '1080I' || raw == '1080') return 'FHD';
  if (raw == '2160P' || raw == '4096P') return '4K';
  return raw;
}