// lib/providers/language_provider.dart
//
// Arich Player — Provider de langue
// • Persiste le code langue dans Hive ('pref_lang_code')
// • Expose l'instance AppL10n courante
// • Un seul appel notifyListeners() reconstruit tout l'arbre
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/l10n.dart';

const _kLangCode    = 'pref_lang_code';
const _kLangChosen  = 'pref_lang_chosen'; // true après le 1er choix

class LanguageProvider with ChangeNotifier {
  late String    _code;
  late AppL10n   _l10n;
  late bool      _languageChosen;

  LanguageProvider() {
    final box       = Hive.box('settings');
    _code           = box.get(_kLangCode,   defaultValue: 'fr') as String;
    _languageChosen = box.get(_kLangChosen, defaultValue: false) as bool;
    _l10n           = AppL10n.forCode(_code);
  }

  AppL10n get l10n           => _l10n;
  String  get currentCode    => _code;
  bool    get languageChosen => _languageChosen;

  /// Change la langue et notifie les widgets.
  void setLanguage(String code) {
    if (_code == code) return;
    _code = code;
    _l10n = AppL10n.forCode(code);
    Hive.box('settings').put(_kLangCode, code);
    notifyListeners();
  }

  /// Appelé une fois après le choix initial (popup 1er lancement).
  void markLanguageChosen() {
    if (_languageChosen) return;
    _languageChosen = true;
    Hive.box('settings').put(_kLangChosen, true);
    // Pas de notifyListeners() nécessaire ici
  }
}               