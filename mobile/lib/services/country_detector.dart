// lib/services/country_detector.dart
//
// Détecteur de pays/région robuste pour les group-title M3U IPTV.
//
// Stratégie (par ordre de priorité) :
//   1. Token exact  → match sur code ISO ou nom complet normalisé
//   2. Préfixe/suffixe délimité → "|AR|", "AR:", "AR -", "[AR]", etc.
//   3. Contient un nom de pays complet (≥ 4 caractères)
//
// RÈGLES CRITIQUES :
//   • "ar" seul → Arabe (pas Argentine — en IPTV AR = Arabic invariablement)
//   • "arg" / "argentina" → Argentine
//   • "de" seul → Allemagne (Deutsch), pas un code pays ambigu
//   • "in" seul → Inde uniquement si confirmé par contexte, sinon ignoré
//   • Les codes 2 lettres isolés sont traités comme LANGUE en priorité

class CountryInfo {
  final String code;
  final String flag;
  final String name;

  const CountryInfo({
    required this.code,
    required this.flag,
    required this.name,
  });
}

class CountryDetector {
  // ── API publique ────────────────────────────────────────────────────────────

  /// Détecte le pays/région depuis un group-title M3U.
  /// Retourne null si non reconnu.
  static CountryInfo? detect(String groupTitle) {
    if (groupTitle.isEmpty) return null;
    final normalized = _normalize(groupTitle);
    if (normalized.isEmpty) return null;

    // 1. Token extrait du délimiteur (|XX|, [XX], XX:, XX -, - XX)
    final token = _extractToken(normalized);

    // 2. Match exact sur token court (codes, abréviations)
    if (token != null) {
      final match = _exactMatch(token);
      if (match != null) return match;
    }

    // 3. Match exact sur toute la chaîne normalisée
    final full = _exactMatch(normalized);
    if (full != null) return full;

    // 4. La chaîne normalisée COMMENCE par un identifiant connu
    final prefix = _prefixMatch(normalized);
    if (prefix != null) return prefix;

    // 5. La chaîne normalisée CONTIENT un nom de pays complet (≥ 4 chars)
    final contains = _containsMatch(normalized);
    if (contains != null) return contains;

    return null;
  }

  /// Retire le préfixe/suffixe pays des group-titles formatés.
  /// Ex: "| FR | TF1 HD" → "TF1 HD"   "FR: Canal+" → "Canal+"
  static String stripCountryToken(String groupTitle) {
    // Retire les blocs délimités en début : |XX|, [XX], (XX), XX:, XX -
    var s = groupTitle.trim();
    s = s.replaceAll(RegExp(r'^\s*[\|\[\(]\s*[A-Za-z]{2,4}\s*[\|\]\)]\s*[-:·|]?\s*'), '');
    s = s.replaceAll(RegExp(r'^\s*[A-Za-z]{2,4}\s*[-:·|]\s*'), '');
    return s.trim().isEmpty ? groupTitle.trim() : s.trim();
  }

  // ── Normalisation ──────────────────────────────────────────────────────────

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõöø]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ß]'), 'ss')
        .replaceAll(RegExp(r'[^a-z0-9\s\|\[\]\(\)\-_:·•]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Extraction du token délimité ──────────────────────────────────────────

  static final _tokenRe = RegExp(
    r'[\|\[\(]\s*([a-z]{2,5})\s*[\|\]\)]'   // |XX|  [XX]  (XX)
    r'|^([a-z]{2,5})\s*[-:·|]'               // XX:  XX-  XX|  en début
    r'|[-:·|]\s*([a-z]{2,5})\s*$',           // en fin :XX  |XX
  );

  static String? _extractToken(String normalized) {
    final m = _tokenRe.firstMatch(normalized);
    if (m == null) return null;
    return (m.group(1) ?? m.group(2) ?? m.group(3))?.trim();
  }

  // ── Tables de mapping ─────────────────────────────────────────────────────
  //
  // ATTENTION : Les codes 2 lettres ISO 639-1 (langues) sont traités en
  // PRIORITÉ sur les codes ISO 3166-1 alpha-2 (pays) quand ils sont
  // identiques — notamment :
  //   ar = Arabe  (pas Argentine  → Argentina = ARG / argentina)
  //   de = Allemand
  //   fr = Français / France
  //   es = Espagnol / Espagne
  //   it = Italien / Italie
  //   pt = Portugais / Portugal
  //   nl = Néerlandais / Pays-Bas
  //   tr = Turquie (seul cas non ambigu)
  //   ru = Russie
  //   pl = Pologne
  //   ro = Roumanie

  static final _exact = <String, CountryInfo>{
    // ── Monde Arabe ────────────────────────────────────────────────────────
    'ar':           CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arab':         CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arabic':       CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arabe':        CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arabian':      CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arab world':   CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'monde arabe':  CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),

    // ── France ─────────────────────────────────────────────────────────────
    'fr':           CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'fra':          CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'france':       CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'french':       CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'francais':     CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'francaise':    CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),

    // ── Allemagne ─────────────────────────────────────────────────────────
    'de':           CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'deu':          CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'ger':          CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'germany':      CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'allemagne':    CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'deutsch':      CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'german':       CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'allemand':     CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),

    // ── Espagne / Espagnol ─────────────────────────────────────────────────
    'es':           CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'esp':          CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'spain':        CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'espagne':      CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'espana':       CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'spanish':      CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'espanol':      CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),

    // ── Italie ────────────────────────────────────────────────────────────
    'it':           CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'ita':          CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italy':        CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italia':       CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italie':       CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italian':      CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italiano':     CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italienne':    CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),

    // ── Portugal / Portugais ───────────────────────────────────────────────
    'pt':           CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),
    'por':          CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),
    'portugal':     CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),
    'portuguese':   CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),
    'portugais':    CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),

    // ── Brésil ────────────────────────────────────────────────────────────
    'br':           CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'bra':          CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'brazil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'brasil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'bresil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'brazilian':    CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'bresilien':    CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),

    // ── Royaume-Uni ───────────────────────────────────────────────────────
    'gb':           CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'uk':           CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'gbr':          CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'eng':          CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'england':      CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'british':      CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'united kingdom': CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'royaume uni':  CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),

    // ── États-Unis ────────────────────────────────────────────────────────
    'us':           CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),
    'usa':          CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),
    'etats unis':   CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),
    'american':     CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),
    'americain':    CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),
    'united states': CountryInfo(code: 'US', flag: '🇺🇸', name: 'États-Unis'),

    // ── Belgique ─────────────────────────────────────────────────────────
    'be':           CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),
    'bel':          CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),
    'belgium':      CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),
    'belgique':     CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),
    'belgie':       CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),
    'belge':        CountryInfo(code: 'BE', flag: '🇧🇪', name: 'Belgique'),

    // ── Suisse ────────────────────────────────────────────────────────────
    'ch':           CountryInfo(code: 'CH', flag: '🇨🇭', name: 'Suisse'),
    'sui':          CountryInfo(code: 'CH', flag: '🇨🇭', name: 'Suisse'),
    'suisse':       CountryInfo(code: 'CH', flag: '🇨🇭', name: 'Suisse'),
    'switzerland':  CountryInfo(code: 'CH', flag: '🇨🇭', name: 'Suisse'),
    'swiss':        CountryInfo(code: 'CH', flag: '🇨🇭', name: 'Suisse'),

    // ── Pays-Bas ─────────────────────────────────────────────────────────
    'nl':           CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'nld':          CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'netherlands':  CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'pays bas':     CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'dutch':        CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'holland':      CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),
    'hollandais':   CountryInfo(code: 'NL', flag: '🇳🇱', name: 'Pays-Bas'),

    // ── Turquie ────────────────────────────────────────────────────────────
    'tr':           CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'tur':          CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turkey':       CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turquie':      CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turk':         CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turkish':      CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turc':         CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),

    // ── Russie ────────────────────────────────────────────────────────────
    'ru':           CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'rus':          CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'russia':       CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'russie':       CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'russian':      CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'russe':        CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),

    // ── Pologne ───────────────────────────────────────────────────────────
    'pl':           CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),
    'pol':          CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),
    'poland':       CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),
    'pologne':      CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),
    'polish':       CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),
    'polonais':     CountryInfo(code: 'PL', flag: '🇵🇱', name: 'Pologne'),

    // ── Roumanie ──────────────────────────────────────────────────────────
    'ro':           CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),
    'rou':          CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),
    'romania':      CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),
    'roumanie':     CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),
    'romanian':     CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),
    'roumain':      CountryInfo(code: 'RO', flag: '🇷🇴', name: 'Roumanie'),

    // ── Hongrie ───────────────────────────────────────────────────────────
    'hu':           CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),
    'hun':          CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),
    'hungary':      CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),
    'hongrie':      CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),
    'hungarian':    CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),
    'hongrois':     CountryInfo(code: 'HU', flag: '🇭🇺', name: 'Hongrie'),

    // ── République Tchèque ────────────────────────────────────────────────
    'cz':           CountryInfo(code: 'CZ', flag: '🇨🇿', name: 'Tchéquie'),
    'cze':          CountryInfo(code: 'CZ', flag: '🇨🇿', name: 'Tchéquie'),
    'czech':        CountryInfo(code: 'CZ', flag: '🇨🇿', name: 'Tchéquie'),
    'czechia':      CountryInfo(code: 'CZ', flag: '🇨🇿', name: 'Tchéquie'),
    'tcheque':      CountryInfo(code: 'CZ', flag: '🇨🇿', name: 'Tchéquie'),

    // ── Slovaquie ─────────────────────────────────────────────────────────
    'sk':           CountryInfo(code: 'SK', flag: '🇸🇰', name: 'Slovaquie'),
    'svk':          CountryInfo(code: 'SK', flag: '🇸🇰', name: 'Slovaquie'),
    'slovakia':     CountryInfo(code: 'SK', flag: '🇸🇰', name: 'Slovaquie'),
    'slovak':       CountryInfo(code: 'SK', flag: '🇸🇰', name: 'Slovaquie'),
    'slovaquie':    CountryInfo(code: 'SK', flag: '🇸🇰', name: 'Slovaquie'),

    // ── Serbie ────────────────────────────────────────────────────────────
    'rs':           CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),
    'srb':          CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),
    'serbia':       CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),
    'serbie':       CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),
    'serbian':      CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),
    'serbe':        CountryInfo(code: 'RS', flag: '🇷🇸', name: 'Serbie'),

    // ── Croatie ───────────────────────────────────────────────────────────
    'hr':           CountryInfo(code: 'HR', flag: '🇭🇷', name: 'Croatie'),
    'hrv':          CountryInfo(code: 'HR', flag: '🇭🇷', name: 'Croatie'),
    'croatia':      CountryInfo(code: 'HR', flag: '🇭🇷', name: 'Croatie'),
    'croatie':      CountryInfo(code: 'HR', flag: '🇭🇷', name: 'Croatie'),
    'croatian':     CountryInfo(code: 'HR', flag: '🇭🇷', name: 'Croatie'),

    // ── Bosnie ────────────────────────────────────────────────────────────
    'ba':           CountryInfo(code: 'BA', flag: '🇧🇦', name: 'Bosnie'),
    'bih':          CountryInfo(code: 'BA', flag: '🇧🇦', name: 'Bosnie'),
    'bosnia':       CountryInfo(code: 'BA', flag: '🇧🇦', name: 'Bosnie'),
    'bosnie':       CountryInfo(code: 'BA', flag: '🇧🇦', name: 'Bosnie'),

    // ── Albanie ───────────────────────────────────────────────────────────
    'al':           CountryInfo(code: 'AL', flag: '🇦🇱', name: 'Albanie'),
    'alb':          CountryInfo(code: 'AL', flag: '🇦🇱', name: 'Albanie'),
    'albania':      CountryInfo(code: 'AL', flag: '🇦🇱', name: 'Albanie'),
    'albanie':      CountryInfo(code: 'AL', flag: '🇦🇱', name: 'Albanie'),
    'albanian':     CountryInfo(code: 'AL', flag: '🇦🇱', name: 'Albanie'),

    // ── Grèce ─────────────────────────────────────────────────────────────
    'gr':           CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),
    'gre':          CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),
    'greece':       CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),
    'grece':        CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),
    'greek':        CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),
    'grec':         CountryInfo(code: 'GR', flag: '🇬🇷', name: 'Grèce'),

    // ── Suède ────────────────────────────────────────────────────────────
    'se':           CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),
    'swe':          CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),
    'sweden':       CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),
    'suede':        CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),
    'swedish':      CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),
    'suedois':      CountryInfo(code: 'SE', flag: '🇸🇪', name: 'Suède'),

    // ── Norvège ───────────────────────────────────────────────────────────
    'no':           CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),
    'nor':          CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),
    'norway':       CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),
    'norvege':      CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),
    'norwegian':    CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),
    'norvegien':    CountryInfo(code: 'NO', flag: '🇳🇴', name: 'Norvège'),

    // ── Danemark ─────────────────────────────────────────────────────────
    'dk':           CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),
    'dnk':          CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),
    'denmark':      CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),
    'danemark':     CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),
    'danish':       CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),
    'danois':       CountryInfo(code: 'DK', flag: '🇩🇰', name: 'Danemark'),

    // ── Finlande ─────────────────────────────────────────────────────────
    'fi':           CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),
    'fin':          CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),
    'finland':      CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),
    'finlande':     CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),
    'finnish':      CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),
    'finlandais':   CountryInfo(code: 'FI', flag: '🇫🇮', name: 'Finlande'),

    // ── Maroc ────────────────────────────────────────────────────────────
    'ma':           CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'mar':          CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'maroc':        CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'morocco':      CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'marocain':     CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),

    // ── Algérie ───────────────────────────────────────────────────────────
    'dz':           CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'dza':          CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'algerie':      CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'algeria':      CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'algerien':     CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),

    // ── Tunisie ───────────────────────────────────────────────────────────
    'tn':           CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'tun':          CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'tunisie':      CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'tunisia':      CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'tunisien':     CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),

    // ── Égypte ────────────────────────────────────────────────────────────
    'eg':           CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'egy':          CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'egypt':        CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'egypte':       CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'egyptien':     CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),

    // ── Arabie Saoudite ───────────────────────────────────────────────────
    'sa':           CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),
    'ksa':          CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),
    'saudi':        CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),
    'arabie saoudite': CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),
    'saudi arabia': CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),

    // ── Qatar ─────────────────────────────────────────────────────────────
    'qa':           CountryInfo(code: 'QA', flag: '🇶🇦', name: 'Qatar'),
    'qat':          CountryInfo(code: 'QA', flag: '🇶🇦', name: 'Qatar'),
    'qatar':        CountryInfo(code: 'QA', flag: '🇶🇦', name: 'Qatar'),

    // ── Émirats ───────────────────────────────────────────────────────────
    'ae':           CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'uae':          CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'emirates':     CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'emirats':      CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'dubai':        CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'abu dhabi':    CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),

    // ── Koweït ───────────────────────────────────────────────────────────
    'kw':           CountryInfo(code: 'KW', flag: '🇰🇼', name: 'Koweït'),
    'kwt':          CountryInfo(code: 'KW', flag: '🇰🇼', name: 'Koweït'),
    'kuwait':       CountryInfo(code: 'KW', flag: '🇰🇼', name: 'Koweït'),
    'koweit':       CountryInfo(code: 'KW', flag: '🇰🇼', name: 'Koweït'),

    // ── Irak ─────────────────────────────────────────────────────────────
    'iq':           CountryInfo(code: 'IQ', flag: '🇮🇶', name: 'Irak'),
    'irq':          CountryInfo(code: 'IQ', flag: '🇮🇶', name: 'Irak'),
    'iraq':         CountryInfo(code: 'IQ', flag: '🇮🇶', name: 'Irak'),
    'iraqi':        CountryInfo(code: 'IQ', flag: '🇮🇶', name: 'Irak'),

    // ── Iran ─────────────────────────────────────────────────────────────
    'ir':           CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'irn':          CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'iran':         CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'iranian':      CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'persia':       CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'persian':      CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'perse':        CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),

    // ── Liban ────────────────────────────────────────────────────────────
    'lb':           CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'lbn':          CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'liban':        CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'lebanon':      CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'lebanese':     CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'libanais':     CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),

    // ── Syrie ────────────────────────────────────────────────────────────
    'sy':           CountryInfo(code: 'SY', flag: '🇸🇾', name: 'Syrie'),
    'syr':          CountryInfo(code: 'SY', flag: '🇸🇾', name: 'Syrie'),
    'syria':        CountryInfo(code: 'SY', flag: '🇸🇾', name: 'Syrie'),
    'syrie':        CountryInfo(code: 'SY', flag: '🇸🇾', name: 'Syrie'),
    'syrian':       CountryInfo(code: 'SY', flag: '🇸🇾', name: 'Syrie'),

    // ── Jordanie ─────────────────────────────────────────────────────────
    'jo':           CountryInfo(code: 'JO', flag: '🇯🇴', name: 'Jordanie'),
    'jor':          CountryInfo(code: 'JO', flag: '🇯🇴', name: 'Jordanie'),
    'jordan':       CountryInfo(code: 'JO', flag: '🇯🇴', name: 'Jordanie'),
    'jordanie':     CountryInfo(code: 'JO', flag: '🇯🇴', name: 'Jordanie'),

    // ── Palestine ────────────────────────────────────────────────────────
    'ps':           CountryInfo(code: 'PS', flag: '🇵🇸', name: 'Palestine'),
    'pse':          CountryInfo(code: 'PS', flag: '🇵🇸', name: 'Palestine'),
    'palestine':    CountryInfo(code: 'PS', flag: '🇵🇸', name: 'Palestine'),
    'palestinien':  CountryInfo(code: 'PS', flag: '🇵🇸', name: 'Palestine'),

    // ── Inde ─────────────────────────────────────────────────────────────
    'in':           CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'ind':          CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'india':        CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'inde':         CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'indian':       CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'hindi':        CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'bollywood':    CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),

    // ── Pakistan ──────────────────────────────────────────────────────────
    'pk':           CountryInfo(code: 'PK', flag: '🇵🇰', name: 'Pakistan'),
    'pak':          CountryInfo(code: 'PK', flag: '🇵🇰', name: 'Pakistan'),
    'pakistan':     CountryInfo(code: 'PK', flag: '🇵🇰', name: 'Pakistan'),
    'pakistani':    CountryInfo(code: 'PK', flag: '🇵🇰', name: 'Pakistan'),

    // ── Afghanistan ────────────────────────────────────────────────────────
    'af':           CountryInfo(code: 'AF', flag: '🇦🇫', name: 'Afghanistan'),
    'afg':          CountryInfo(code: 'AF', flag: '🇦🇫', name: 'Afghanistan'),
    'afghanistan':  CountryInfo(code: 'AF', flag: '🇦🇫', name: 'Afghanistan'),

    // ── Chine ────────────────────────────────────────────────────────────
    'cn':           CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'chn':          CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'china':        CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'chine':        CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'chinese':      CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'chinois':      CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),

    // ── Japon ────────────────────────────────────────────────────────────
    'jp':           CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'jpn':          CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'japan':        CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'japon':        CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'japanese':     CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'japonais':     CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),

    // ── Corée ────────────────────────────────────────────────────────────
    'kr':           CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'kor':          CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'korea':        CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'coree':        CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'korean':       CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'coreen':       CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),

    // ── Thaïlande ────────────────────────────────────────────────────────
    'th':           CountryInfo(code: 'TH', flag: '🇹🇭', name: 'Thaïlande'),
    'tha':          CountryInfo(code: 'TH', flag: '🇹🇭', name: 'Thaïlande'),
    'thailand':     CountryInfo(code: 'TH', flag: '🇹🇭', name: 'Thaïlande'),
    'thailande':    CountryInfo(code: 'TH', flag: '🇹🇭', name: 'Thaïlande'),
    'thai':         CountryInfo(code: 'TH', flag: '🇹🇭', name: 'Thaïlande'),

    // ── Vietnam ───────────────────────────────────────────────────────────
    'vn':           CountryInfo(code: 'VN', flag: '🇻🇳', name: 'Vietnam'),
    'vnm':          CountryInfo(code: 'VN', flag: '🇻🇳', name: 'Vietnam'),
    'vietnam':      CountryInfo(code: 'VN', flag: '🇻🇳', name: 'Vietnam'),
    'viet':         CountryInfo(code: 'VN', flag: '🇻🇳', name: 'Vietnam'),
    'vietnamese':   CountryInfo(code: 'VN', flag: '🇻🇳', name: 'Vietnam'),

    // ── Philippines ───────────────────────────────────────────────────────
    'ph':           CountryInfo(code: 'PH', flag: '🇵🇭', name: 'Philippines'),
    'phl':          CountryInfo(code: 'PH', flag: '🇵🇭', name: 'Philippines'),
    'philippines':  CountryInfo(code: 'PH', flag: '🇵🇭', name: 'Philippines'),
    'philippine':   CountryInfo(code: 'PH', flag: '🇵🇭', name: 'Philippines'),
    'filipino':     CountryInfo(code: 'PH', flag: '🇵🇭', name: 'Philippines'),

    // ── Indonésie ─────────────────────────────────────────────────────────
    'id':           CountryInfo(code: 'ID', flag: '🇮🇩', name: 'Indonésie'),
    'idn':          CountryInfo(code: 'ID', flag: '🇮🇩', name: 'Indonésie'),
    'indonesia':    CountryInfo(code: 'ID', flag: '🇮🇩', name: 'Indonésie'),
    'indonesie':    CountryInfo(code: 'ID', flag: '🇮🇩', name: 'Indonésie'),
    'indonesian':   CountryInfo(code: 'ID', flag: '🇮🇩', name: 'Indonésie'),

    // ── Australie ────────────────────────────────────────────────────────
    'au':           CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),
    'aus':          CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),
    'australia':    CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),
    'australie':    CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),

    // ── Argentine ── ATTENTION : 'ar' seul = Arabe, pas Argentine ─────────
    'arg':          CountryInfo(code: 'AR', flag: '🇦🇷', name: 'Argentine'),
    'argentina':    CountryInfo(code: 'AR', flag: '🇦🇷', name: 'Argentine'),
    'argentine':    CountryInfo(code: 'AR', flag: '🇦🇷', name: 'Argentine'),

    // ── Mexique ───────────────────────────────────────────────────────────
    'mx':           CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'mex':          CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'mexico':       CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'mexique':      CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'mexicain':     CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),

    // ── Colombie ──────────────────────────────────────────────────────────
    'co':           CountryInfo(code: 'CO', flag: '🇨🇴', name: 'Colombie'),
    'col':          CountryInfo(code: 'CO', flag: '🇨🇴', name: 'Colombie'),
    'colombia':     CountryInfo(code: 'CO', flag: '🇨🇴', name: 'Colombie'),
    'colombie':     CountryInfo(code: 'CO', flag: '🇨🇴', name: 'Colombie'),

    // ── Venezuela ─────────────────────────────────────────────────────────
    've':           CountryInfo(code: 'VE', flag: '🇻🇪', name: 'Venezuela'),
    'ven':          CountryInfo(code: 'VE', flag: '🇻🇪', name: 'Venezuela'),
    'venezuela':    CountryInfo(code: 'VE', flag: '🇻🇪', name: 'Venezuela'),

    // ── Chili ────────────────────────────────────────────────────────────
    'cl':           CountryInfo(code: 'CL', flag: '🇨🇱', name: 'Chili'),
    'chl':          CountryInfo(code: 'CL', flag: '🇨🇱', name: 'Chili'),
    'chile':        CountryInfo(code: 'CL', flag: '🇨🇱', name: 'Chili'),
    'chili':        CountryInfo(code: 'CL', flag: '🇨🇱', name: 'Chili'),

    // ── Pérou ────────────────────────────────────────────────────────────
    'pe':           CountryInfo(code: 'PE', flag: '🇵🇪', name: 'Pérou'),
    'per':          CountryInfo(code: 'PE', flag: '🇵🇪', name: 'Pérou'),
    'peru':         CountryInfo(code: 'PE', flag: '🇵🇪', name: 'Pérou'),
    'perou':        CountryInfo(code: 'PE', flag: '🇵🇪', name: 'Pérou'),

    // ── Nigeria ───────────────────────────────────────────────────────────
    'ng':           CountryInfo(code: 'NG', flag: '🇳🇬', name: 'Nigeria'),
    'nga':          CountryInfo(code: 'NG', flag: '🇳🇬', name: 'Nigeria'),
    'nigeria':      CountryInfo(code: 'NG', flag: '🇳🇬', name: 'Nigeria'),
    'nigerian':     CountryInfo(code: 'NG', flag: '🇳🇬', name: 'Nigeria'),

    // ── Ghana ────────────────────────────────────────────────────────────
    'gh':           CountryInfo(code: 'GH', flag: '🇬🇭', name: 'Ghana'),
    'gha':          CountryInfo(code: 'GH', flag: '🇬🇭', name: 'Ghana'),
    'ghana':        CountryInfo(code: 'GH', flag: '🇬🇭', name: 'Ghana'),

    // ── Sénégal ───────────────────────────────────────────────────────────
    'sn':           CountryInfo(code: 'SN', flag: '🇸🇳', name: 'Sénégal'),
    'sen':          CountryInfo(code: 'SN', flag: '🇸🇳', name: 'Sénégal'),
    'senegal':      CountryInfo(code: 'SN', flag: '🇸🇳', name: 'Sénégal'),

    // ── Cameroun ─────────────────────────────────────────────────────────
    'cm':           CountryInfo(code: 'CM', flag: '🇨🇲', name: 'Cameroun'),
    'cmr':          CountryInfo(code: 'CM', flag: '🇨🇲', name: 'Cameroun'),
    'cameroon':     CountryInfo(code: 'CM', flag: '🇨🇲', name: 'Cameroun'),
    'cameroun':     CountryInfo(code: 'CM', flag: '🇨🇲', name: 'Cameroun'),

    // ── Côte d'Ivoire ─────────────────────────────────────────────────────
    'ci':           CountryInfo(code: 'CI', flag: '🇨🇮', name: "Côte d'Ivoire"),
    'civ':          CountryInfo(code: 'CI', flag: '🇨🇮', name: "Côte d'Ivoire"),
    'ivory coast':  CountryInfo(code: 'CI', flag: '🇨🇮', name: "Côte d'Ivoire"),
    'cote ivoire':  CountryInfo(code: 'CI', flag: '🇨🇮', name: "Côte d'Ivoire"),

    // ── Afrique du Sud ────────────────────────────────────────────────────
    'za':           CountryInfo(code: 'ZA', flag: '🇿🇦', name: 'Afrique du Sud'),
    'zaf':          CountryInfo(code: 'ZA', flag: '🇿🇦', name: 'Afrique du Sud'),
    'south africa': CountryInfo(code: 'ZA', flag: '🇿🇦', name: 'Afrique du Sud'),
    'afrique du sud': CountryInfo(code: 'ZA', flag: '🇿🇦', name: 'Afrique du Sud'),

    // ── Kenya ────────────────────────────────────────────────────────────
    'ke':           CountryInfo(code: 'KE', flag: '🇰🇪', name: 'Kenya'),
    'ken':          CountryInfo(code: 'KE', flag: '🇰🇪', name: 'Kenya'),
    'kenya':        CountryInfo(code: 'KE', flag: '🇰🇪', name: 'Kenya'),

    // ── Éthiopie ─────────────────────────────────────────────────────────
    'et':           CountryInfo(code: 'ET', flag: '🇪🇹', name: 'Éthiopie'),
    'eth':          CountryInfo(code: 'ET', flag: '🇪🇹', name: 'Éthiopie'),
    'ethiopia':     CountryInfo(code: 'ET', flag: '🇪🇹', name: 'Éthiopie'),
    'ethiopie':     CountryInfo(code: 'ET', flag: '🇪🇹', name: 'Éthiopie'),

    // ── Libyan  ───────────────────────────────────────────────────────────
    'ly':           CountryInfo(code: 'LY', flag: '🇱🇾', name: 'Libye'),
    'lba':          CountryInfo(code: 'LY', flag: '🇱🇾', name: 'Libye'),
    'libya':        CountryInfo(code: 'LY', flag: '🇱🇾', name: 'Libye'),
    'libye':        CountryInfo(code: 'LY', flag: '🇱🇾', name: 'Libye'),

    // ── Canada ────────────────────────────────────────────────────────────
    'ca':           CountryInfo(code: 'CA', flag: '🇨🇦', name: 'Canada'),
    'can':          CountryInfo(code: 'CA', flag: '🇨🇦', name: 'Canada'),
    'canada':       CountryInfo(code: 'CA', flag: '🇨🇦', name: 'Canada'),
    'canadien':     CountryInfo(code: 'CA', flag: '🇨🇦', name: 'Canada'),

    // ── International / Multi ─────────────────────────────────────────────
    'int':          CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
    'international': CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
    'multi':        CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
    'world':        CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
    'monde':        CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
  };

  // ── Noms complets (≥ 4 chars) pour le match "contains" ───────────────────
  // Sous-ensemble des noms univoques uniquement (pas les codes courts)
  static final _containsMap = <String, CountryInfo>{
    'france':       CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'french':       CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'francais':     CountryInfo(code: 'FR', flag: '🇫🇷', name: 'France'),
    'germany':      CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'allemagne':    CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'deutsch':      CountryInfo(code: 'DE', flag: '🇩🇪', name: 'Allemagne'),
    'spain':        CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'espagne':      CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'espana':       CountryInfo(code: 'ES', flag: '🇪🇸', name: 'Espagne'),
    'italy':        CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italia':       CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'italie':       CountryInfo(code: 'IT', flag: '🇮🇹', name: 'Italie'),
    'portugal':     CountryInfo(code: 'PT', flag: '🇵🇹', name: 'Portugal'),
    'brazil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'brasil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'bresil':       CountryInfo(code: 'BR', flag: '🇧🇷', name: 'Brésil'),
    'england':      CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'british':      CountryInfo(code: 'GB', flag: '🇬🇧', name: 'Royaume-Uni'),
    'turkey':       CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'turquie':      CountryInfo(code: 'TR', flag: '🇹🇷', name: 'Turquie'),
    'russia':       CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'russie':       CountryInfo(code: 'RU', flag: '🇷🇺', name: 'Russie'),
    'arabic':       CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'arabe':        CountryInfo(code: 'ARAB', flag: '🌍', name: 'Arabe'),
    'maroc':        CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'morocco':      CountryInfo(code: 'MA', flag: '🇲🇦', name: 'Maroc'),
    'algerie':      CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'algeria':      CountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algérie'),
    'tunisie':      CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'tunisia':      CountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisie'),
    'egypt':        CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'egypte':       CountryInfo(code: 'EG', flag: '🇪🇬', name: 'Égypte'),
    'saudi':        CountryInfo(code: 'SA', flag: '🇸🇦', name: 'Arabie Saoudite'),
    'qatar':        CountryInfo(code: 'QA', flag: '🇶🇦', name: 'Qatar'),
    'emirates':     CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'emirats':      CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'dubai':        CountryInfo(code: 'AE', flag: '🇦🇪', name: 'Émirats'),
    'india':        CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'hindi':        CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'bollywood':    CountryInfo(code: 'IN', flag: '🇮🇳', name: 'Inde'),
    'pakistan':     CountryInfo(code: 'PK', flag: '🇵🇰', name: 'Pakistan'),
    'china':        CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'chine':        CountryInfo(code: 'CN', flag: '🇨🇳', name: 'Chine'),
    'japan':        CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'japon':        CountryInfo(code: 'JP', flag: '🇯🇵', name: 'Japon'),
    'korea':        CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'coree':        CountryInfo(code: 'KR', flag: '🇰🇷', name: 'Corée'),
    'iran':         CountryInfo(code: 'IR', flag: '🇮🇷', name: 'Iran'),
    'iraq':         CountryInfo(code: 'IQ', flag: '🇮🇶', name: 'Irak'),
    'liban':        CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'lebanon':      CountryInfo(code: 'LB', flag: '🇱🇧', name: 'Liban'),
    'argentina':    CountryInfo(code: 'AR', flag: '🇦🇷', name: 'Argentine'),
    'argentine':    CountryInfo(code: 'AR', flag: '🇦🇷', name: 'Argentine'),
    'mexico':       CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'mexique':      CountryInfo(code: 'MX', flag: '🇲🇽', name: 'Mexique'),
    'nigeria':      CountryInfo(code: 'NG', flag: '🇳🇬', name: 'Nigeria'),
    'canada':       CountryInfo(code: 'CA', flag: '🇨🇦', name: 'Canada'),
    'australia':    CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),
    'australie':    CountryInfo(code: 'AU', flag: '🇦🇺', name: 'Australie'),
    'international': CountryInfo(code: 'INT', flag: '🌐', name: 'International'),
  };

  // ── Helpers de matching ────────────────────────────────────────────────────

  static CountryInfo? _exactMatch(String s) => _exact[s];

  static CountryInfo? _prefixMatch(String normalized) {
    for (final entry in _exact.entries) {
      final k = entry.key;
      if (k.length < 2) continue;
      if (normalized.startsWith('$k ') ||
          normalized.startsWith('$k-') ||
          normalized.startsWith('$k:') ||
          normalized.startsWith('$k|')) {
        return entry.value;
      }
    }
    return null;
  }

  static CountryInfo? _containsMatch(String normalized) {
    // Tri par longueur décroissante pour que "arabie saoudite" matche avant "arabie"
    final sorted = _containsMap.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sorted) {
      if (entry.key.length < 4) continue;
      if (normalized.contains(entry.key)) return entry.value;
    }
    return null;
  }
}