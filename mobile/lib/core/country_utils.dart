// lib/core/country_utils.dart
//
// Arich Player — CountryUtils v2
//
// LOGIQUE STRICTE — même système que TiviMate / GSE Smart IPTV :
//
// Les vraies apps IPTV ne font PAS de match par préfixe simple (2-3 lettres).
// Elles utilisent :
//   1. Match de MOTS ENTIERS entre pipes :  "| FR |", "| FR:", "|FR|"
//   2. Liste blanche exhaustive de noms de pays complets
//   3. Jamais un simple startsWith("AR") car "AR" → Argentine ET Arab
//
// Exemples corrigés :
//   "| FR | TNT France"        → France  ✓
//   "AR | ARAB EVENTS"         → null    ✓ (Arab ≠ Argentine)
//   "| AR | Argentina Liga"    → Argentine ✓ (mot entier entre pipes)
//   "MAROC: BeIN Sports"       → Maroc   ✓
//   "MA | Maroc TNT"           → Maroc   ✓
//   "FR: Cinéma"               → France  ✓
//   "Arabes alowan Esport"     → null    ✓ (pas de code pays)
// ─────────────────────────────────────────────────────────────────────────────

class CountryInfo {
  final String code;
  final String flag;
  final String nameEn;
  const CountryInfo({required this.code, required this.flag, required this.nameEn});
}

class CountryUtils {
  CountryUtils._();

  // ── Table de correspondance code ISO → CountryInfo ─────────────────────────
  static const Map<String, CountryInfo> _byCode = {
    'FR': CountryInfo(code: 'FR', flag: '🇫🇷', nameEn: 'France'),
    'EN': CountryInfo(code: 'EN', flag: '🇬🇧', nameEn: 'English'),
    'UK': CountryInfo(code: 'UK', flag: '🇬🇧', nameEn: 'United Kingdom'),
    'GB': CountryInfo(code: 'GB', flag: '🇬🇧', nameEn: 'United Kingdom'),
    'US': CountryInfo(code: 'US', flag: '🇺🇸', nameEn: 'USA'),
    'DE': CountryInfo(code: 'DE', flag: '🇩🇪', nameEn: 'Germany'),
    'ES': CountryInfo(code: 'ES', flag: '🇪🇸', nameEn: 'Spain'),
    'IT': CountryInfo(code: 'IT', flag: '🇮🇹', nameEn: 'Italy'),
    'PT': CountryInfo(code: 'PT', flag: '🇵🇹', nameEn: 'Portugal'),
    'BE': CountryInfo(code: 'BE', flag: '🇧🇪', nameEn: 'Belgique'),
    'CH': CountryInfo(code: 'CH', flag: '🇨🇭', nameEn: 'Suisse'),
    'NL': CountryInfo(code: 'NL', flag: '🇳🇱', nameEn: 'Netherlands'),
    'PL': CountryInfo(code: 'PL', flag: '🇵🇱', nameEn: 'Poland'),
    'RU': CountryInfo(code: 'RU', flag: '🇷🇺', nameEn: 'Russia'),
    'TR': CountryInfo(code: 'TR', flag: '🇹🇷', nameEn: 'Turkey'),
    'MA': CountryInfo(code: 'MA', flag: '🇲🇦', nameEn: 'Maroc'),
    'DZ': CountryInfo(code: 'DZ', flag: '🇩🇿', nameEn: 'Algérie'),
    'TN': CountryInfo(code: 'TN', flag: '🇹🇳', nameEn: 'Tunisie'),
    'SA': CountryInfo(code: 'SA', flag: '🇸🇦', nameEn: 'Saudi Arabia'),
    'AE': CountryInfo(code: 'AE', flag: '🇦🇪', nameEn: 'UAE'),
    'EG': CountryInfo(code: 'EG', flag: '🇪🇬', nameEn: 'Egypt'),
    'IQ': CountryInfo(code: 'IQ', flag: '🇮🇶', nameEn: 'Iraq'),
    'LB': CountryInfo(code: 'LB', flag: '🇱🇧', nameEn: 'Lebanon'),
    'JO': CountryInfo(code: 'JO', flag: '🇯🇴', nameEn: 'Jordan'),
    'KW': CountryInfo(code: 'KW', flag: '🇰🇼', nameEn: 'Kuwait'),
    'QA': CountryInfo(code: 'QA', flag: '🇶🇦', nameEn: 'Qatar'),
    'BH': CountryInfo(code: 'BH', flag: '🇧🇭', nameEn: 'Bahrain'),
    'OM': CountryInfo(code: 'OM', flag: '🇴🇲', nameEn: 'Oman'),
    'YE': CountryInfo(code: 'YE', flag: '🇾🇪', nameEn: 'Yemen'),
    'LY': CountryInfo(code: 'LY', flag: '🇱🇾', nameEn: 'Libya'),
    'SD': CountryInfo(code: 'SD', flag: '🇸🇩', nameEn: 'Sudan'),
    'SY': CountryInfo(code: 'SY', flag: '🇸🇾', nameEn: 'Syria'),
    'PS': CountryInfo(code: 'PS', flag: '🇵🇸', nameEn: 'Palestine'),
    'IR': CountryInfo(code: 'IR', flag: '🇮🇷', nameEn: 'Iran'),
    'AF': CountryInfo(code: 'AF', flag: '🇦🇫', nameEn: 'Afghanistan'),
    'PK': CountryInfo(code: 'PK', flag: '🇵🇰', nameEn: 'Pakistan'),
    'IN': CountryInfo(code: 'IN', flag: '🇮🇳', nameEn: 'India'),
    'BD': CountryInfo(code: 'BD', flag: '🇧🇩', nameEn: 'Bangladesh'),
    'CN': CountryInfo(code: 'CN', flag: '🇨🇳', nameEn: 'China'),
    'JP': CountryInfo(code: 'JP', flag: '🇯🇵', nameEn: 'Japan'),
    'KR': CountryInfo(code: 'KR', flag: '🇰🇷', nameEn: 'Korea'),
    'TH': CountryInfo(code: 'TH', flag: '🇹🇭', nameEn: 'Thailand'),
    'VN': CountryInfo(code: 'VN', flag: '🇻🇳', nameEn: 'Vietnam'),
    'ID': CountryInfo(code: 'ID', flag: '🇮🇩', nameEn: 'Indonesia'),
    'MY': CountryInfo(code: 'MY', flag: '🇲🇾', nameEn: 'Malaysia'),
    'SG': CountryInfo(code: 'SG', flag: '🇸🇬', nameEn: 'Singapore'),
    'PH': CountryInfo(code: 'PH', flag: '🇵🇭', nameEn: 'Philippines'),
    'BR': CountryInfo(code: 'BR', flag: '🇧🇷', nameEn: 'Brazil'),
    'AR': CountryInfo(code: 'AR', flag: '🇦🇷', nameEn: 'Argentina'),
    'MX': CountryInfo(code: 'MX', flag: '🇲🇽', nameEn: 'Mexico'),
    'CO': CountryInfo(code: 'CO', flag: '🇨🇴', nameEn: 'Colombia'),
    'CL': CountryInfo(code: 'CL', flag: '🇨🇱', nameEn: 'Chile'),
    'PE': CountryInfo(code: 'PE', flag: '🇵🇪', nameEn: 'Peru'),
    'VE': CountryInfo(code: 'VE', flag: '🇻🇪', nameEn: 'Venezuela'),
    'BO': CountryInfo(code: 'BO', flag: '🇧🇴', nameEn: 'Bolivia'),
    'PY': CountryInfo(code: 'PY', flag: '🇵🇾', nameEn: 'Paraguay'),
    'UY': CountryInfo(code: 'UY', flag: '🇺🇾', nameEn: 'Uruguay'),
    'EC': CountryInfo(code: 'EC', flag: '🇪🇨', nameEn: 'Ecuador'),
    'GT': CountryInfo(code: 'GT', flag: '🇬🇹', nameEn: 'Guatemala'),
    'HN': CountryInfo(code: 'HN', flag: '🇭🇳', nameEn: 'Honduras'),
    'SV': CountryInfo(code: 'SV', flag: '🇸🇻', nameEn: 'El Salvador'),
    'NI': CountryInfo(code: 'NI', flag: '🇳🇮', nameEn: 'Nicaragua'),
    'CR': CountryInfo(code: 'CR', flag: '🇨🇷', nameEn: 'Costa Rica'),
    'PA': CountryInfo(code: 'PA', flag: '🇵🇦', nameEn: 'Panama'),
    'DO': CountryInfo(code: 'DO', flag: '🇩🇴', nameEn: 'Dominican Republic'),
    'CU': CountryInfo(code: 'CU', flag: '🇨🇺', nameEn: 'Cuba'),
    'CA': CountryInfo(code: 'CA', flag: '🇨🇦', nameEn: 'Canada'),
    'AU': CountryInfo(code: 'AU', flag: '🇦🇺', nameEn: 'Australia'),
    'NZ': CountryInfo(code: 'NZ', flag: '🇳🇿', nameEn: 'New Zealand'),
    'ZA': CountryInfo(code: 'ZA', flag: '🇿🇦', nameEn: 'South Africa'),
    'NG': CountryInfo(code: 'NG', flag: '🇳🇬', nameEn: 'Nigeria'),
    'KE': CountryInfo(code: 'KE', flag: '🇰🇪', nameEn: 'Kenya'),
    'GH': CountryInfo(code: 'GH', flag: '🇬🇭', nameEn: 'Ghana'),
    'ET': CountryInfo(code: 'ET', flag: '🇪🇹', nameEn: 'Ethiopia'),
    'TZ': CountryInfo(code: 'TZ', flag: '🇹🇿', nameEn: 'Tanzania'),
    'SN': CountryInfo(code: 'SN', flag: '🇸🇳', nameEn: 'Senegal'),
    'CM': CountryInfo(code: 'CM', flag: '🇨🇲', nameEn: 'Cameroon'),
    'CI': CountryInfo(code: 'CI', flag: '🇨🇮', nameEn: "Côte d'Ivoire"),
    'GR': CountryInfo(code: 'GR', flag: '🇬🇷', nameEn: 'Greece'),
    'CZ': CountryInfo(code: 'CZ', flag: '🇨🇿', nameEn: 'Czech Republic'),
    'SK': CountryInfo(code: 'SK', flag: '🇸🇰', nameEn: 'Slovakia'),
    'HU': CountryInfo(code: 'HU', flag: '🇭🇺', nameEn: 'Hungary'),
    'RO': CountryInfo(code: 'RO', flag: '🇷🇴', nameEn: 'Romania'),
    'BG': CountryInfo(code: 'BG', flag: '🇧🇬', nameEn: 'Bulgaria'),
    'HR': CountryInfo(code: 'HR', flag: '🇭🇷', nameEn: 'Croatia'),
    'RS': CountryInfo(code: 'RS', flag: '🇷🇸', nameEn: 'Serbia'),
    'BA': CountryInfo(code: 'BA', flag: '🇧🇦', nameEn: 'Bosnia'),
    'AL': CountryInfo(code: 'AL', flag: '🇦🇱', nameEn: 'Albania'),
    'MK': CountryInfo(code: 'MK', flag: '🇲🇰', nameEn: 'Macedonia'),
    'ME': CountryInfo(code: 'ME', flag: '🇲🇪', nameEn: 'Montenegro'),
    'SI': CountryInfo(code: 'SI', flag: '🇸🇮', nameEn: 'Slovenia'),
    'LT': CountryInfo(code: 'LT', flag: '🇱🇹', nameEn: 'Lithuania'),
    'LV': CountryInfo(code: 'LV', flag: '🇱🇻', nameEn: 'Latvia'),
    'EE': CountryInfo(code: 'EE', flag: '🇪🇪', nameEn: 'Estonia'),
    'UA': CountryInfo(code: 'UA', flag: '🇺🇦', nameEn: 'Ukraine'),
    'BY': CountryInfo(code: 'BY', flag: '🇧🇾', nameEn: 'Belarus'),
    'NO': CountryInfo(code: 'NO', flag: '🇳🇴', nameEn: 'Norway'),
    'SE': CountryInfo(code: 'SE', flag: '🇸🇪', nameEn: 'Sweden'),
    'DK': CountryInfo(code: 'DK', flag: '🇩🇰', nameEn: 'Denmark'),
    'FI': CountryInfo(code: 'FI', flag: '🇫🇮', nameEn: 'Finland'),
    'IE': CountryInfo(code: 'IE', flag: '🇮🇪', nameEn: 'Ireland'),
    'AT': CountryInfo(code: 'AT', flag: '🇦🇹', nameEn: 'Austria'),
    'LU': CountryInfo(code: 'LU', flag: '🇱🇺', nameEn: 'Luxembourg'),
    'IS': CountryInfo(code: 'IS', flag: '🇮🇸', nameEn: 'Iceland'),
    'MT': CountryInfo(code: 'MT', flag: '🇲🇹', nameEn: 'Malta'),
    'CY': CountryInfo(code: 'CY', flag: '🇨🇾', nameEn: 'Cyprus'),
    'IL': CountryInfo(code: 'IL', flag: '🇮🇱', nameEn: 'Israel'),
    'SO': CountryInfo(code: 'SO', flag: '🇸🇴', nameEn: 'Somalia'),
    'MR': CountryInfo(code: 'MR', flag: '🇲🇷', nameEn: 'Mauritania'),
    'ML': CountryInfo(code: 'ML', flag: '🇲🇱', nameEn: 'Mali'),
    'KZ': CountryInfo(code: 'KZ', flag: '🇰🇿', nameEn: 'Kazakhstan'),
    'AZ': CountryInfo(code: 'AZ', flag: '🇦🇿', nameEn: 'Azerbaijan'),
    'GE': CountryInfo(code: 'GE', flag: '🇬🇪', nameEn: 'Georgia'),
    'AM': CountryInfo(code: 'AM', flag: '🇦🇲', nameEn: 'Armenia'),
    'UZ': CountryInfo(code: 'UZ', flag: '🇺🇿', nameEn: 'Uzbekistan'),
  };

  // ── Noms complets → code (pour match par nom complet dans le titre) ─────────
  // On couvre les variantes FR/EN/AR les plus courantes dans les playlists IPTV
  static const Map<String, String> _nameToCode = {
    // Français
    'france': 'FR',
    'allemagne': 'DE',
    'espagne': 'ES',
    'italie': 'IT',
    'portugal': 'PT',
    'belgique': 'BE',
    'suisse': 'CH',
    'pays bas': 'NL',
    'hollande': 'NL',
    'pologne': 'PL',
    'russie': 'RU',
    'turquie': 'TR',
    'maroc': 'MA',
    'algerie': 'DZ',
    'tunisie': 'TN',
    'egypte': 'EG',
    'arabie saoudite': 'SA',
    'emirats': 'AE',
    'irak': 'IQ',
    'liban': 'LB',
    'jordanie': 'JO',
    'koweit': 'KW',
    'syrie': 'SY',
    'libye': 'LY',
    'soudan': 'SD',
    'yemen': 'YE',
    'palestine': 'PS',
    'iran': 'IR',
    'pakistan': 'PK',
    'inde': 'IN',
    'chine': 'CN',
    'japon': 'JP',
    'coree': 'KR',
    'bresil': 'BR',
    'argentine': 'AR',
    'mexique': 'MX',
    'colombie': 'CO',
    'chili': 'CL',
    'perou': 'PE',
    'venezuela': 'VE',
    'canada': 'CA',
    'australie': 'AU',
    'afrique du sud': 'ZA',
    'nigeria': 'NG',
    'kenya': 'KE',
    'ghana': 'GH',
    'senegal': 'SN',
    'cameroun': 'CM',
    'grece': 'GR',
    'roumanie': 'RO',
    'bulgarie': 'BG',
    'croatie': 'HR',
    'serbie': 'RS',
    'bosnie': 'BA',
    'albanie': 'AL',
    'ukraine': 'UA',
    'bielorussie': 'BY',
    'norvege': 'NO',
    'suede': 'SE',
    'danemark': 'DK',
    'finlande': 'FI',
    'irlande': 'IE',
    'autriche': 'AT',
    'luxembourg': 'LU',
    'islande': 'IS',
    'malte': 'MT',
    'chypre': 'CY',
    'israel': 'IL',
    'somalie': 'SO',
    'mauritanie': 'MR',
    'mali': 'ML',
    // Anglais
    'germany': 'DE',
    'spain': 'ES',
    'italy': 'IT',
    'netherlands': 'NL',
    'poland': 'PL',
    'russia': 'RU',
    'turkey': 'TR',
    'morocco': 'MA',
    'algeria': 'DZ',
    'tunisia': 'TN',
    'egypt': 'EG',
    'saudi arabia': 'SA',
    'saudi': 'SA',
    'kuwait': 'KW',
    'syria': 'SY',
    'libya': 'LY',
    'sudan': 'SD',
    'lebanon': 'LB',
    'jordan': 'JO',
    'iraq': 'IQ',
    'india': 'IN',
    'china': 'CN',
    'japan': 'JP',
    'korea': 'KR',
    'brazil': 'BR',
    'argentina': 'AR',
    'mexico': 'MX',
    'colombia': 'CO',
    'chile': 'CL',
    'peru': 'PE',
    'australia': 'AU',
    'south africa': 'ZA',
    'cameroon': 'CM',
    'greece': 'GR',
    'romania': 'RO',
    'bulgaria': 'BG',
    'croatia': 'HR',
    'serbia': 'RS',
    'bosnia': 'BA',
    'albania': 'AL',
    'norway': 'NO',
    'sweden': 'SE',
    'denmark': 'DK',
    'finland': 'FI',
    'ireland': 'IE',
    'austria': 'AT',
    'iceland': 'IS',
    'somalia': 'SO',
    'mauritania': 'MR',
    'united kingdom': 'GB',
    'england': 'GB',
    // Arabe translittéré
    'misr': 'EG',
    'masr': 'EG',
    'suriya': 'SY',
    'lubnane': 'LB',
    'urdun': 'JO',
  };

  // ── Codes ambigus qui ne doivent JAMAIS matcher seuls sans pipes ────────────
  // Ces codes existent en ISO mais sont aussi des préfixes communs de mots
  static const Set<String> _ambiguousCodes = {
    'AR', // Argentine MAIS aussi "Arab", "Arena", "Arte"...
    'IN', // India MAIS "International", "Info"...
    'IT', // Italy MAIS "Italian", "ITV"...
    'BE', // Belgium MAIS "BeIN", "Best"...
    'PT', // Portugal MAIS "Premium"...
    'NO', // Norway MAIS "Novela"...
    'IS', // Iceland MAIS "Islamic"...
    'AL', // Albania MAIS "Alowan", "Algeria" abrégé...
    'SO', // Somalia MAIS "Sony", "Sport"...
    'MA', // Maroc MAIS "Match", "Manga"...
    'ME', // Montenegro MAIS "Media", "MENA"...
    'GE', // Georgia MAIS "General"...
    'CO', // Colombia MAIS "Comedy", "Cooking"...
    'AM', // Armenia MAIS "Amazon"...
    'SI', // Slovenia MAIS "Sigma"...
    'BY', // Belarus MAIS "ByteDance"...
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Méthode principale : détecte le pays depuis un group-title de playlist
  //
  // Règles strictes (même ordre que TiviMate) :
  //   1. Format pipe : "| XX |", "| XX:", "|XX|", "|XX:" — code entre pipes
  //      → Pour les codes ambigus, OBLIGATOIRE d'avoir les pipes
  //   2. Format préfixe non-ambigu : "XX |", "XX:" — si code non-ambigu
  //   3. Nom complet : "France TNT", "MAROC beIN" — recherche mot complet
  // ─────────────────────────────────────────────────────────────────────────
  static CountryInfo? fromGroupTitle(String raw) {
    if (raw.isEmpty) return null;
    final s = raw.trim();

    // ── Étape 1 : code entre pipes (format strict "|XX|" ou "| XX |") ────────
    // Ce pattern capte : |FR|, | FR |, |FR:, | FR:, etc.
    final pipeMatch = RegExp(
      r'[\|]\s*([A-Z]{2,3})\s*[\|:\-]',
      caseSensitive: true,
    ).firstMatch(s.toUpperCase());

    if (pipeMatch != null) {
      final code = pipeMatch.group(1)!;
      if (_byCode.containsKey(code)) {
        return _byCode[code];
      }
    }

    // ── Étape 2 : préfixe non-ambigu "XX |", "XX:", "XX -" en début ─────────
    // Seulement pour les codes NON-ambigus
    final prefixMatch = RegExp(
      r'^([A-Z]{2,3})\s*[\|:\-\.]\s',
      caseSensitive: true,
    ).firstMatch(s.toUpperCase());

    if (prefixMatch != null) {
      final code = prefixMatch.group(1)!;
      if (_byCode.containsKey(code) && !_ambiguousCodes.contains(code)) {
        return _byCode[code];
      }
    }

    // ── Étape 3 : nom de pays complet dans le titre (mot entier) ─────────────
    // Normalise : retire accents, minuscule, puis cherche dans _nameToCode
    final normalized = _normalize(s);
    for (final entry in _nameToCode.entries) {
      // Vérifie que le nom est un mot entier (pas juste un préfixe)
      if (_containsWholeWord(normalized, entry.key)) {
        final code = entry.value;
        if (_byCode.containsKey(code)) return _byCode[code];
      }
    }

    return null;
  }

  // ── Vérifie que `word` est un mot entier dans `text` ──────────────────────
  static bool _containsWholeWord(String text, String word) {
    // Utilise \b (word boundary) simulé : espace ou début/fin
    final pattern = RegExp(
      r'(^|[\s\|\:\-\_\.])' + RegExp.escape(word) + r'($|[\s\|\:\-\_\.])',
      caseSensitive: false,
    );
    return pattern.hasMatch(text);
  }

  // ── Normalisation : retire accents, lowercase ──────────────────────────────
  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n');
  }

  // ── Nom localisé (affiché dans l'UI) ──────────────────────────────────────
  static String localizedName(String code) {
    return _byCode[code]?.nameEn ?? code;
  }

  // ── Flag depuis code ───────────────────────────────────────────────────────
  static String flagFromCode(String code) {
    return _byCode[code]?.flag ?? '🌐';
  }
}