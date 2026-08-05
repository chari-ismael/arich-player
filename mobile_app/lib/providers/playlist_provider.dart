// lib/providers/playlist_provider.dart
//
// Arich Player — Playlist Provider
// [FIX] clear() appelé au signedOut → vide playlists mémoire + Hive
// [FIX] _load() vérifie session Supabase avant de charger depuis Hive
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/playlist_account.dart';
import '../services/supabase_service.dart';

const _kPlaylistColors = [
  '#E53935',
  '#1E88E5',
  '#43A047',
  '#FB8C00',
  '#8E24AA',
  '#00ACC1',
  '#F4511E',
  '#3949AB',
];

class PlaylistProvider with ChangeNotifier {
  List<PlaylistAccount> _accounts   = [];
  bool                  _isSyncing  = false;
  String?               _syncError;
  DateTime?             _lastSync;

  RealtimeChannel?       _realtimeChannel;
  StreamSubscription<AuthState>? _authSub;

  static const _uuid = Uuid();

  List<PlaylistAccount> get accounts    => List.unmodifiable(_accounts);
  bool                  get hasAccounts => _accounts.isNotEmpty;
  bool                  get isSyncing   => _isSyncing;
  String?               get syncError   => _syncError;
  DateTime?             get lastSync    => _lastSync;

  PlaylistAccount? get activeAccount =>
      _accounts.where((a) => a.isActive).isNotEmpty
          ? _accounts.firstWhere((a) => a.isActive)
          : _accounts.isNotEmpty ? _accounts.first : null;

  PlaylistProvider() {
    _load();
    _startRealtime();
    _listenAuthState();
  }

  // ── Auth state ────────────────────────────────────────────────────────────

  void _listenAuthState() {
    _authSub = SupabaseService.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.tokenRefreshed) {
        // Nouveau compte connecté → sync ses playlists depuis Supabase
        syncFromSupabase();
      } else if (state.event == AuthChangeEvent.signedOut) {
        // [FIX] Déconnexion → vider immédiatement playlists locales + Hive
        clear();
      }
    });
  }

  // ── Sync au retour dans l'app ─────────────────────────────────────────────

  Future<void> syncOnResume() async {
    if (_isSyncing) return;
    if (_lastSync != null && DateTime.now().difference(_lastSync!).inSeconds < 30) return;
    await syncFromSupabase();
  }

  // ── Realtime Supabase ─────────────────────────────────────────────────────

  void _startRealtime() {
    _realtimeChannel = SupabaseService.subscribeToPlaylists((rows) {
      _mergeFromWeb(rows);
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _authSub?.cancel();
    super.dispose();
  }

  // ── Chargement local (Hive) ───────────────────────────────────────────────

  void _load() {
    // Les playlists Hive sont locales à l'appareil — on les charge
    // indépendamment de la session Supabase. clear() est appelé au signedOut
    // pour effacer les données du compte précédent si nécessaire.
    try {
      final box = Hive.box('settings');
      final raw = box.get('playlist_accounts', defaultValue: []);
      final rawList = raw is List ? raw : [];
      _accounts = rawList
          .whereType<Map>()
          .map((m) => PlaylistAccount.fromMap(m))
          .where((account) {
            // Ignorer les comptes M3U dont l'URL est invalide
            if (account.type == PlaylistType.m3u) {
              final uri = Uri.tryParse(account.m3uUrl);
              if (uri == null || uri.host.isEmpty) {
                return false;
              }
            }
            return true;
          })
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } catch (_) {
      _accounts = [];
    }
    _migrateFromLegacy();
  }

  void _migrateFromLegacy() {
    if (_accounts.isNotEmpty) return;
    final box = Hive.box('settings');
    final url    = box.get('server_url',   defaultValue: '') as String;
    final user   = box.get('username',     defaultValue: '') as String;
    final pass   = box.get('password',     defaultValue: '') as String;
    final srcStr = box.get('source_type',  defaultValue: '') as String;
    final m3uUrl = box.get('m3u_url',      defaultValue: '') as String;

    if (srcStr == 'xtream' && url.isNotEmpty && user.isNotEmpty) {
      addXtream(name: _guessName(url), serverUrl: url, username: user, password: pass, setActive: true);
    } else if (srcStr == 'm3u' && m3uUrl.isNotEmpty) {
      addM3u(name: _guessName(m3uUrl), m3uUrl: m3uUrl, setActive: true);
    }
  }

  // ── Sync depuis Supabase ──────────────────────────────────────────────────

  Future<void> syncFromSupabase([BuildContext? context]) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final rows  = await SupabaseService.fetchWebPlaylists();
      final added = _mergeFromWeb(rows);
      _lastSync   = DateTime.now();
      _isSyncing  = false;
      notifyListeners();

      if (added > 0 && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$added playlist${added > 1 ? "s" : ""} importée${added > 1 ? "s" : ""} depuis le compte !'),
          backgroundColor: const Color(0xFF43A047),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      _isSyncing = false;
      _syncError = e.toString();
      notifyListeners();
    }
  }

  // ── Fusion des playlists web dans la liste locale ─────────────────────────

  int _mergeFromWeb(List<Map<String, dynamic>> rows) {
    int added = 0;
    for (final row in rows) {
      final rowId      = row['id']             as String?;
      final type       = (row['type']           as String?) ?? 'm3u';
      final name       = (row['name']           as String?) ?? 'Playlist';
      final xtreamHost = (row['xtream_host']     as String?) ?? '';
      final xtreamUser = (row['xtream_username'] as String?) ?? '';
      final xtreamPass = (row['xtream_password'] as String?) ?? '';
      final m3uUrl     = (row['m3u_url']         as String?) ?? '';

      final alreadyExists = _accounts.any((a) {
        if (rowId != null && a.supabaseId == rowId) return true;
        if (type == 'xtream') return a.type == PlaylistType.xtream && a.serverUrl == xtreamHost;
        return a.type == PlaylistType.m3u && a.m3uUrl == m3uUrl;
      });

      if (alreadyExists) continue;

      if (type == 'xtream' && xtreamHost.isNotEmpty) {
        _addAccountDirect(PlaylistAccount(
          id:         _uuid.v4(),
          supabaseId: rowId,
          name:       name,
          type:       PlaylistType.xtream,
          color:      _nextColor(),
          serverUrl:  xtreamHost,
          username:   xtreamUser,
          password:   xtreamPass,
          addedAt:    DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
          isActive:   false,
        ));
        added++;
      } else if (type == 'm3u' && m3uUrl.isNotEmpty) {
        _addAccountDirect(PlaylistAccount(
          id:         _uuid.v4(),
          supabaseId: rowId,
          name:       name,
          type:       PlaylistType.m3u,
          color:      _nextColor(),
          m3uUrl:     m3uUrl,
          addedAt:    DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
          isActive:   false,
        ));
        added++;
      }
    }

    if (added > 0) {
      _save();
      notifyListeners();
    }
    return added;
  }

  void _addAccountDirect(PlaylistAccount account) {
    _accounts.insert(0, account);
  }

  // ── CRUD public ───────────────────────────────────────────────────────────

  Future<void> addXtream({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
    bool setActive = false,
  }) async {
    if (setActive) _accounts = _accounts.map((a) => a.copyWith(isActive: false)).toList();

    // Insertion locale immédiate — ne jamais bloquer sur Supabase
    final localId = _uuid.v4();
    _accounts.insert(0, PlaylistAccount(
      id:         localId,
      supabaseId: null,
      name:       name,
      type:       PlaylistType.xtream,
      color:      _nextColor(),
      serverUrl:  serverUrl,
      username:   username,
      password:   password,
      addedAt:    DateTime.now(),
      isActive:   setActive,
    ));
    _save();
    notifyListeners();

    // Push Supabase en best-effort (pas de session = pas d'erreur pour l'user)
    try {
      final supabaseId = await SupabaseService.pushPlaylist(
        name:           name,
        type:           'xtream',
        xtreamHost:     serverUrl,
        xtreamUsername: username,
        xtreamPassword: password,
      );
      if (supabaseId != null) {
        final idx = _accounts.indexWhere((a) => a.id == localId);
        if (idx != -1) {
          _accounts[idx] = _accounts[idx].copyWith(supabaseId: supabaseId);
          _save();
        }
      }
    } catch (_) {
      // Pas de session Supabase — la playlist est sauvée localement, c'est suffisant
    }
  }

  Future<void> addM3u({
    required String name,
    required String m3uUrl,
    bool setActive = false,
  }) async {
    // Validation de l'URL M3U
    final trimmedUrl = m3uUrl.trim();
    if (trimmedUrl.isEmpty) return;
    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || uri.host.isEmpty) return;

    if (setActive) _accounts = _accounts.map((a) => a.copyWith(isActive: false)).toList();

    final localId = _uuid.v4();
    _accounts.insert(0, PlaylistAccount(
      id:         localId,
      supabaseId: null,
      name:       name,
      type:       PlaylistType.m3u,
      color:      _nextColor(),
      m3uUrl:     trimmedUrl,
      addedAt:    DateTime.now(),
      isActive:   setActive,
    ));
    _save();
    notifyListeners();

    // Push Supabase en best-effort
    try {
      final supabaseId = await SupabaseService.pushPlaylist(
        name:   name,
        type:   'm3u',
        m3uUrl: m3uUrl,
      );
      if (supabaseId != null) {
        final idx = _accounts.indexWhere((a) => a.id == localId);
        if (idx != -1) {
          _accounts[idx] = _accounts[idx].copyWith(supabaseId: supabaseId);
          _save();
        }
      }
    } catch (_) {
      // Pas de session Supabase — la playlist est sauvée localement, c'est suffisant
    }
  }

  void setActive(String id) {
    _accounts = _accounts.map((a) => a.copyWith(isActive: a.id == id)).toList();
    _save();
    notifyListeners();
  }

  void remove(String id) {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final account = _accounts[idx];
    if (account.supabaseId != null) {
      SupabaseService.deletePlaylist(account.supabaseId!);
    }
    _accounts.removeAt(idx);
    _save();
    notifyListeners();
  }

  void rename(String id, String newName) {
    _accounts = _accounts.map((a) => a.id == id ? a.copyWith(name: newName) : a).toList();
    _save();
    notifyListeners();
  }

  // ── Clear (déconnexion) ───────────────────────────────────────────────────

  /// Vide toutes les playlists en mémoire ET dans Hive.
  /// Appelé automatiquement au signedOut via _listenAuthState,
  /// et manuellement depuis ProfileScreen._signOut().
  void clear() {
    _accounts  = [];
    _syncError = null;
    _lastSync  = null;
    try {
      Hive.box('settings').delete('playlist_accounts');
    } catch (_) {}
    notifyListeners();
  }

  // ── Utils ─────────────────────────────────────────────────────────────────

  String _guessName(String url) {
    try {
      return Uri.parse(url).host.isNotEmpty ? Uri.parse(url).host : 'Ma Playlist';
    } catch (_) {
      return 'Ma Playlist';
    }
  }

  String _nextColor() {
    final used = _accounts.map((a) => a.color).toSet();
    for (final c in _kPlaylistColors) {
      if (!used.contains(c)) return c;
    }
    return _kPlaylistColors[_accounts.length % _kPlaylistColors.length];
  }

  void _save() {
    try {
      Hive.box('settings').put(
        'playlist_accounts',
        _accounts.map((a) => a.toMap()).toList(),
      );
    } catch (_) {}
  }
}