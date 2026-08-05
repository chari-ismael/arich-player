import 'package:flutter/material.dart';

enum PlaylistType { xtream, m3u }

class PlaylistAccount {
  final String id;         // UUID unique
  final String name;       // Nom affiché (ex: "Mon IPTV FR")
  final PlaylistType type;
  final String color;      // Couleur hex pour l'avatar

  // Xtream
  final String serverUrl;
  final String username;
  final String password;

  // M3U
  final String m3uUrl;

  final DateTime addedAt;
  final bool isActive;     // Compte actuellement chargé

  final String? supabaseId; // ID de la ligne dans Supabase (null si pas encore synchronisé)

  const PlaylistAccount({
    required this.id,
    required this.name,
    required this.type,
    this.color = '#E53935',
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.m3uUrl = '',
    required this.addedAt,
    this.isActive = false,
    this.supabaseId,
  });

  String get displayUrl {
    if (type == PlaylistType.xtream) return serverUrl;
    return m3uUrl;
  }

  String get subtitle {
    if (type == PlaylistType.xtream) return username.isNotEmpty ? '@$username' : serverUrl;
    final uri = Uri.tryParse(m3uUrl);
    return uri?.host ?? m3uUrl;
  }

  String get typeLabel => type == PlaylistType.xtream ? 'Xtream' : 'M3U';

  IconData get typeIcon =>
      type == PlaylistType.xtream ? Icons.stream_rounded : Icons.list_alt_rounded;

  PlaylistAccount copyWith({
    bool? isActive,
    String? name,
    String? color,
    String? supabaseId,
  }) =>
      PlaylistAccount(
        id: id,
        name: name ?? this.name,
        type: type,
        color: color ?? this.color,
        serverUrl: serverUrl,
        username: username,
        password: password,
        m3uUrl: m3uUrl,
        addedAt: addedAt,
        isActive: isActive ?? this.isActive,
        supabaseId: supabaseId ?? this.supabaseId,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'color': color,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'isActive': isActive,
        'supabaseId': supabaseId,
      };

  factory PlaylistAccount.fromMap(Map map) => PlaylistAccount(
        id: map['id'] ?? '',
        name: map['name'] ?? 'Playlist',
        type: map['type'] == 'xtream' ? PlaylistType.xtream : PlaylistType.m3u,
        color: map['color'] ?? '#E53935',
        serverUrl: map['serverUrl'] ?? '',
        username: map['username'] ?? '',
        password: map['password'] ?? '',
        m3uUrl: map['m3uUrl'] ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] ?? 0),
        isActive: map['isActive'] ?? false,
        supabaseId: map['supabaseId'] as String?,
      );
}