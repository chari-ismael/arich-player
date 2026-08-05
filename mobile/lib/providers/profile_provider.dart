// lib/providers/profile_provider.dart
//
// Arich Player — Profile Provider v1.0
//
// Gère les profils utilisateur multiples (max 4) :
//   • Création / édition / suppression
//   • Profil actif courant
//   • PIN parental optionnel par profil
//   • Persistence Hive dans 'settings'
//   • Favoris/historique isolés par profil (préfixe dans UserStorage)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Constantes Hive ───────────────────────────────────────────────────────────

const kProfilesKey       = 'arich_profiles';
const kActiveProfileKey  = 'arich_active_profile_id';
const kMaxProfiles       = 4;

// ── Modèle ────────────────────────────────────────────────────────────────────

class ProfileModel {
  final String id;
  String name;
  String avatar;   // emoji ex: '🎬' ou chemin fichier local si commence par '/'
  String? pin;     // 4 chiffres, null = pas de PIN
  bool   isKids;  // mode enfants (contenu filtré)

  ProfileModel({
    required this.id,
    required this.name,
    required this.avatar,
    this.pin,
    this.isKids = false,
  });

  bool get hasPin => pin != null && pin!.isNotEmpty;
  bool get isDefault => id == 'default';

  // Clé UserStorage préfixée — garantit isolation favoris/historique
  String storagePrefix(String baseKey) => '${id}_$baseKey';

  Map<String, dynamic> toMap() => {
    'id':     id,
    'name':   name,
    'avatar': avatar,
    'pin':    pin,
    'isKids': isKids,
  };

  factory ProfileModel.fromMap(Map<dynamic, dynamic> m) => ProfileModel(
    id:     m['id']?.toString() ?? 'default',
    name:   m['name']?.toString() ?? 'Profil',
    avatar: m['avatar']?.toString() ?? '👤',
    pin:    m['pin']?.toString(),
    isKids: (m['isKids'] as bool?) ?? false,
  );

  static ProfileModel defaultProfile() => ProfileModel(
    id:     'default',
    name:   'Principal',
    avatar: '🎬',
  );

  ProfileModel copyWith({
    String? name,
    String? avatar,
    String? pin,
    bool?   isKids,
  }) => ProfileModel(
    id:     id,
    name:   name   ?? this.name,
    avatar: avatar ?? this.avatar,
    pin:    pin    ?? this.pin,
    isKids: isKids ?? this.isKids,
  );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class ProfileProvider extends ChangeNotifier {
  final List<ProfileModel> _profiles = [];
  String _activeId = 'default';

  List<ProfileModel> get profiles      => List.unmodifiable(_profiles);
  int                get count         => _profiles.length;
  bool               get canAddMore    => _profiles.length < kMaxProfiles;

  ProfileModel get active {
    try {
      return _profiles.firstWhere((p) => p.id == _activeId);
    } catch (_) {
      return _profiles.isNotEmpty ? _profiles.first : ProfileModel.defaultProfile();
    }
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  void init() {
    _load();
    // Créer le profil par défaut si aucun
    if (_profiles.isEmpty) {
      _profiles.add(ProfileModel.defaultProfile());
      _save();
    }
  }

  void _load() {
    final box = Hive.box('settings');
    _activeId = box.get(kActiveProfileKey, defaultValue: 'default') as String;
    final raw = box.get(kProfilesKey);
    if (raw is List) {
      _profiles.clear();
      for (final item in raw) {
        if (item is Map) {
          try { _profiles.add(ProfileModel.fromMap(item)); } catch (_) {}
        }
      }
    }
  }

  Future<void> _save() async {
    final box = Hive.box('settings');
    await box.put(kProfilesKey, _profiles.map((p) => p.toMap()).toList());
    await box.put(kActiveProfileKey, _activeId);
  }

  // ── Switch profil ─────────────────────────────────────────────────────────

  Future<void> switchTo(String id) async {
    if (_activeId == id) return;
    _activeId = id;
    await _save();
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<bool> addProfile({
    required String name,
    required String avatar,
    String? pin,
    bool isKids = false,
  }) async {
    if (_profiles.length >= kMaxProfiles) return false;
    final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    _profiles.add(ProfileModel(
      id: id, name: name, avatar: avatar, pin: pin, isKids: isKids,
    ));
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> updateProfile(String id, {
    String? name,
    String? avatar,
    String? pin,
    bool?   isKids,
  }) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _profiles[idx] = _profiles[idx].copyWith(
      name: name, avatar: avatar, pin: pin, isKids: isKids,
    );
    await _save();
    notifyListeners();
  }

  Future<void> removeProfile(String id) async {
    if (id == 'default') return; // le profil principal ne peut pas être supprimé
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : 'default';
    }
    await _save();
    notifyListeners();
  }

  // ── PIN ───────────────────────────────────────────────────────────────────

  bool checkPin(String id, String pin) {
    try {
      final p = _profiles.firstWhere((p) => p.id == id);
      return p.pin == pin;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String id, String? pin) async {
    await updateProfile(id, pin: pin);
  }
}