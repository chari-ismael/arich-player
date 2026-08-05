// lib/providers/theme_provider.dart
// ARICH Player — v2
// [FIX] AppTheme.getTheme() intégré ici pour éviter la dépendance circulaire.
// [FIX] Consumer<ThemeProvider> dans main.dart → le changement de thème
//       reconstruit maintenant le MaterialApp.

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../core/theme.dart';

const kPrefTheme = 'pref_theme';

class ThemeProvider extends ChangeNotifier {
  String _key;

  ThemeProvider() : _key = _readKey();

  static String _readKey() {
    try {
      return Hive.box('settings').get(kPrefTheme, defaultValue: 'dark') as String;
    } catch (_) {
      return 'dark';
    }
  }

  String get themeKey => _key;

  // Retourne le ThemeData correspondant à la clé.
  // Si AppTheme.getTheme n'existe pas encore, on fallback sur AppTheme.darkTheme.
  ThemeData get themeData {
    try {
      return AppTheme.getTheme(_key);
    } catch (_) {
      return AppTheme.darkTheme;
    }
  }

  bool get isDark  => _key == 'dark';
  bool get isPrime => _key == 'prime';
  bool get isBlue  => _key == 'blue';

  Future<void> setTheme(String key) async {
    if (_key == key) return;
    _key = key;
    await Hive.box('settings').put(kPrefTheme, key);
    notifyListeners();
  }
}