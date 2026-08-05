// lib/core/theme.dart
// Arich Player — Theme v3
// Corrections v3 :
//   • [BUG]  getTheme('soft') retombait sur darkTheme — softTheme créé + routé
//   • [BUG]  gradientButton(radius:100) → pill sur height:52 — défaut corrigé à 14
//   • [BUG]  blueNightTheme → blueTheme (cohérence avec clé Hive 'blue')
//   • [CLEAN] warning == gold (doublon) — warning = alias de gold
//   • [CLEAN] Surfaces soft/blue centralisées dans AppTheme (plus dans _C privé)
//   • [AAA]  GradientButton / DangerButton : StatefulWidget + press state + HapticFeedback
//   • [AAA]  gradientPill() helper séparé du gradientButton()
//   • [AAA]  glowColor() helper générique ajouté
//   • [AAA]  accentForTheme() / backgroundForTheme() / surfaceForTheme() helpers

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {

  // ── Couleurs signature ────────────────────────────────────────────────────
  static const Color violet     = Color(0xFF7B2FFF);
  static const Color red        = Color(0xFFFF2D55);

  // ── Aliases sémantiques ───────────────────────────────────────────────────
  static const Color primary    = violet;
  static const Color primaryAlt = red;
  static const Color secondary  = Color(0xFF0A84FF);

  // ── Gradients signature ───────────────────────────────────────────────────
  static const LinearGradient gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [violet, red],
  );
  static const LinearGradient gradientHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end:   Alignment.centerRight,
    colors: [violet, red],
  );
  static const LinearGradient gradientVertical = LinearGradient(
    begin: Alignment.topCenter,
    end:   Alignment.bottomCenter,
    colors: [violet, red],
  );

  // ── Surfaces — thème Dark OLED (clé Hive : 'dark') ───────────────────────
  static const Color background  = Color(0xFF000000);
  static const Color surface     = Color(0xFF111111);
  static const Color surfaceHigh = Color(0xFF1A1A1A);
  static const Color surfaceTop  = Color(0xFF242424);

  // ── Surfaces — thème Nuit Douce (clé Hive : 'soft') ──────────────────────
  // [FIX] Ces couleurs n'existaient que dans la classe _C privée de settings_screen.
  // Centralisées ici pour que tous les fichiers y accèdent via AppTheme.
  static const Color softBackground  = Color(0xFF1A1A2E);
  static const Color softSurface     = Color(0xFF22223B);
  static const Color softSurfaceHigh = Color(0xFF2A2A46);
  static const Color softSurfaceTop  = Color(0xFF35355A);
  static const Color softAccentColor = Color(0xFF6C63FF);
  static const LinearGradient softGradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [softAccentColor, Color(0xFF9B7BFF)],
  );

  // ── Surfaces — thème Nuit Bleue (clé Hive : 'blue') ──────────────────────
  static const Color blueBackground  = Color(0xFF0A0E1A);
  static const Color blueSurface     = Color(0xFF111827);
  static const Color blueSurfaceHigh = Color(0xFF1A2235);
  static const Color blueSurfaceTop  = Color(0xFF212D43);
  static const Color blueAccentColor = Color(0xFF4F7CFF);
  static const LinearGradient blueGradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end:   Alignment.bottomRight,
    colors: [blueAccentColor, Color(0xFF7B5CFF)],
  );

  // ── Sémantiques ───────────────────────────────────────────────────────────
  static const Color gold    = Color(0xFFFFD60A);
  // [CLEAN] warning avait exactement la même valeur que gold — unifié
  static const Color warning = gold;
  static const Color success = Color(0xFF30D158);
  static const Color error   = Color(0xFFFF453A);

  // ── Danger atténué (actions destructives) ─────────────────────────────────
  static const Color danger        = Color(0xFFBF2D2D);
  static const Color dangerMuted   = Color(0xFF7A1A1A);
  static const Color dangerSurface = Color(0xFF2A1010);

  // ── Texte ─────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted     = Color(0xFF3A3A3C);

  // ── Séparateurs ───────────────────────────────────────────────────────────
  static const Color divider = Color(0xFF1A1A1A);
  static const Color border  = Color(0x12FFFFFF);

  // ── Couleurs par type de contenu ──────────────────────────────────────────
  static const Color catLive         = Color(0xFF1A0A2E);
  static const Color catLiveAccent   = Color(0xFF9B59F5);
  static const Color catMovies       = Color(0xFF0A1628);
  static const Color catMoviesAccent = Color(0xFF3D8EFF);
  static const Color catSeries       = Color(0xFF0D1F1A);
  static const Color catSeriesAccent = Color(0xFF34C77B);
  static const Color catSport        = Color(0xFF1A1200);
  static const Color catSportAccent  = Color(0xFFE6A817);
  static const Color catAdult        = Color(0xFF1A0610);
  static const Color catAdultAccent  = Color(0xFFE0457A);
  static const Color catOther        = Color(0xFF0F0F14);
  static const Color catOtherAccent  = Color(0xFF8E8EA8);

  // ── Helpers thème ─────────────────────────────────────────────────────────

  /// Accent couleur du thème actif — utile dans les fichiers qui ont _themeKey
  /// Ex : AppTheme.accentForTheme(_themeKey)
  static Color accentForTheme(String key) => switch (key) {
    'soft' => softAccentColor,
    'blue' => blueAccentColor,
    _      => violet,
  };

  /// Couleur de fond du thème actif
  static Color backgroundForTheme(String key) => switch (key) {
    'soft' => softBackground,
    'blue' => blueBackground,
    _      => background,
  };

  /// Couleur de surface (card) du thème actif
  static Color surfaceForTheme(String key) => switch (key) {
    'soft' => softSurface,
    'blue' => blueSurface,
    _      => surface,
  };

  // ── ThemeData — Dark OLED ─────────────────────────────────────────────────
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary, secondary: secondary, surface: surface, error: error,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface,
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle:  const TextStyle(color: textMuted, fontSize: 13),
      border:         OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.07))),
      focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primary, width: 1.5)),
      errorBorder:    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: error, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dividerColor: divider,
    iconTheme: const IconThemeData(color: textSecondary),
    dialogTheme: DialogThemeData(backgroundColor: surfaceHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceHigh,
      contentTextStyle: GoogleFonts.poppins(color: textPrimary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(primary),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    )),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary.withOpacity(0.7) : textMuted.withOpacity(0.3)),
    ),
  );

  // ── ThemeData — Nuit Douce ────────────────────────────────────────────────
  // [FIX] Ce ThemeData était absent — getTheme('soft') retombait sur darkTheme,
  // ce qui faisait que le fond restait #000000 au lieu de #1A1A2E et l'accent
  // restait violet au lieu de #6C63FF.
  static ThemeData softTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: softBackground,
    primaryColor: softAccentColor,
    colorScheme: ColorScheme.dark(
      primary: softAccentColor, secondary: const Color(0xFF9B7BFF),
      surface: softSurface, error: error,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: softSurface,
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle:  const TextStyle(color: textMuted, fontSize: 13),
      border:         OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.07))),
      focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: softAccentColor, width: 1.5)),
      errorBorder:    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: error, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dividerColor: softSurfaceHigh,
    iconTheme: const IconThemeData(color: textSecondary),
    dialogTheme: DialogThemeData(backgroundColor: softSurfaceHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: softSurfaceHigh,
      contentTextStyle: GoogleFonts.poppins(color: textPrimary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(softAccentColor),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    )),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? softAccentColor.withOpacity(0.7) : textMuted.withOpacity(0.3)),
    ),
  );

  // ── ThemeData — Nuit Bleue ────────────────────────────────────────────────
  // [CLEAN] Renommé blueNightTheme → blueTheme pour cohérence avec la clé 'blue'
  static ThemeData blueTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: blueBackground,
    primaryColor: blueAccentColor,
    colorScheme: ColorScheme.dark(
      primary: blueAccentColor, secondary: const Color(0xFF7B5CFF),
      surface: blueSurface, error: error,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: blueSurface,
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle:  const TextStyle(color: textMuted, fontSize: 13),
      border:         OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.07))),
      focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: blueAccentColor, width: 1.5)),
      errorBorder:    OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: error, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dividerColor: blueSurfaceHigh,
    iconTheme: const IconThemeData(color: textSecondary),
    dialogTheme: DialogThemeData(backgroundColor: blueSurfaceHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: blueSurfaceHigh,
      contentTextStyle: GoogleFonts.poppins(color: textPrimary, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(blueAccentColor),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    )),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? blueAccentColor.withOpacity(0.7) : textMuted.withOpacity(0.3)),
    ),
  );

  // ── getTheme ──────────────────────────────────────────────────────────────
  /// Retourne le bon ThemeData selon la clé Hive `pref_theme`.
  /// Valeurs : 'dark' | 'soft' | 'blue'
  /// [FIX] 'soft' retombait sur darkTheme — maintenant routé vers softTheme
  static ThemeData getTheme(String key) => switch (key) {
    'soft' => softTheme,
    'blue' => blueTheme,
    _      => darkTheme,
  };

  // ── Helpers décoratifs ────────────────────────────────────────────────────

  /// Bouton dégradé signature (violet → rouge)
  /// [FIX] radius défaut : 100 → 14. 100 donnait un pill complet sur height:52.
  /// Utiliser gradientPill() si on veut un pill (chips, badges, nav tabs).
  static BoxDecoration gradientButton({double radius = 14}) {
    return BoxDecoration(
      gradient: gradientPrimary,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: violet.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6)),
        BoxShadow(color: red.withOpacity(0.15),    blurRadius: 12, offset: const Offset(0, 3)),
      ],
    );
  }

  /// Pill gradient — pour badges, chips, nav pills, boutons ronds
  static BoxDecoration gradientPill({double radius = 100}) {
    return BoxDecoration(
      gradient: gradientHorizontal,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: violet.withOpacity(0.30), blurRadius: 12, offset: const Offset(0, 4)),
      ],
    );
  }

  /// Bouton danger atténué
  static BoxDecoration dangerButton({double radius = 14}) {
    return BoxDecoration(
      color: dangerSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: dangerMuted, width: 1),
    );
  }

  /// Card avec bordure subtile
  static BoxDecoration surfaceCard({double radius = 16, bool elevated = false}) {
    return BoxDecoration(
      color: elevated ? surfaceHigh : surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: 1),
    );
  }

  /// Card colorée par type de contenu
  static BoxDecoration categoryCard(CategoryType type, {double radius = 16}) {
    final c = _categoryColors(type);
    return BoxDecoration(
      color: c.$1,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.$2.withOpacity(0.25), width: 1),
    );
  }

  /// Badge/pill coloré par type
  static BoxDecoration categoryBadge(CategoryType type, {double radius = 100}) {
    final c = _categoryColors(type);
    return BoxDecoration(
      color: c.$2.withOpacity(0.15),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: c.$2.withOpacity(0.35), width: 1),
    );
  }

  /// Couleur d'accent par type de catégorie
  static Color categoryAccent(CategoryType type) => _categoryColors(type).$2;

  static (Color, Color) _categoryColors(CategoryType type) => switch (type) {
    CategoryType.live   => (catLive,   catLiveAccent),
    CategoryType.movies => (catMovies,  catMoviesAccent),
    CategoryType.series => (catSeries,  catSeriesAccent),
    CategoryType.sport  => (catSport,   catSportAccent),
    CategoryType.adult  => (catAdult,   catAdultAccent),
    CategoryType.other  => (catOther,   catOtherAccent),
  };

  /// Glow violet — focus TV, sélection active
  static List<BoxShadow> glowViolet({double intensity = 0.35, double blur = 20}) => [
    BoxShadow(color: violet.withOpacity(intensity), blurRadius: blur, spreadRadius: 2),
  ];

  /// Glow rouge — éléments live / actifs chauds
  static List<BoxShadow> glowRed({double intensity = 0.3, double blur = 16}) => [
    BoxShadow(color: red.withOpacity(intensity), blurRadius: blur, offset: const Offset(0, 4)),
  ];

  /// Glow générique — AppTheme.glowColor(AppTheme.catSportAccent, intensity: 0.4)
  static List<BoxShadow> glowColor(
    Color color, {
    double intensity = 0.35,
    double blur = 16,
    double spread = 0,
    Offset offset = const Offset(0, 4),
  }) => [
    BoxShadow(color: color.withOpacity(intensity), blurRadius: blur, spreadRadius: spread, offset: offset),
  ];

  /// Glow coloré par type de catégorie
  static List<BoxShadow> glowCategory(CategoryType type,
      {double intensity = 0.3, double blur = 16}) => [
    BoxShadow(color: categoryAccent(type).withOpacity(intensity), blurRadius: blur, offset: const Offset(0, 4)),
  ];

  /// Glassmorphism card
  static BoxDecoration glassCard({
    double opacity = 0.08, double radius = 16,
    Color borderColor = Colors.white, double borderOpacity = 0.07,
  }) {
    return BoxDecoration(
      color: Colors.white.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor.withOpacity(borderOpacity), width: 1),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
    );
  }

  /// Overlay gradient pour images de fond
  static BoxDecoration imageOverlay({
    AlignmentGeometry begin = Alignment.bottomCenter,
    AlignmentGeometry end   = Alignment.topCenter,
    double startOpacity = 0.9,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: begin, end: end,
        colors: [Colors.black.withOpacity(startOpacity), Colors.transparent],
        stops: const [0, 0.6],
      ),
    );
  }

  /// Ombre douce
  static List<BoxShadow> softShadow({
    Color color = Colors.black, double opacity = 0.35,
    double blur = 12, Offset offset = const Offset(0, 5),
  }) => [
    BoxShadow(color: color.withOpacity(opacity), blurRadius: blur, offset: offset),
  ];
}

// ── Enum type de contenu ──────────────────────────────────────────────────────
enum CategoryType { live, movies, series, sport, adult, other }

/// Détecte le type de catégorie depuis son nom
CategoryType detectCategoryType(String name) {
  final n = name.toLowerCase();
  if (n.contains('live') || n.contains('tv') || n.contains('chaine') || n.contains('chaîne'))
    return CategoryType.live;
  if (n.contains('film') || n.contains('movie') || n.contains('vod') ||
      n.contains('cinéma') || n.contains('cinema'))
    return CategoryType.movies;
  if (n.contains('serie') || n.contains('série') || n.contains('series') || n.contains('saison'))
    return CategoryType.series;
  if (n.contains('sport') || n.contains('foot') || n.contains('ligue') || n.contains('beinsport'))
    return CategoryType.sport;
  if (n.contains('adult') || n.contains('adulte') || n.contains('xxx') || n.contains('+18'))
    return CategoryType.adult;
  return CategoryType.other;
}

// ── Widget : bouton dégradé réutilisable ──────────────────────────────────────
// [AAA] Converti en StatefulWidget : press state + AnimatedScale + HapticFeedback
class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final double height;
  final double radius;

  const GradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.loading = false,
    this.height  = 52,
    this.radius  = 14,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => setState(() => _pressed = true),
      onTapUp:    (_) {
        setState(() => _pressed = false);
        if (!widget.loading && widget.onTap != null) {
          HapticFeedback.lightImpact();
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: widget.height,
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _pressed
              ? [BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 8)]
              : [
                  BoxShadow(color: AppTheme.violet.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6)),
                  BoxShadow(color: AppTheme.red.withOpacity(0.15),    blurRadius: 12, offset: const Offset(0, 3)),
                ],
        ),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Center(
            child: widget.loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label, style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ── Widget : bouton danger atténué ────────────────────────────────────────────
// [AAA] Converti en StatefulWidget : press state + HapticFeedback.mediumImpact
class DangerButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final double height;
  final double radius;

  const DangerButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.loading = false,
    this.height  = 52,
    this.radius  = 14,
  });

  @override
  State<DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<DangerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) {
        setState(() => _pressed = false);
        if (!widget.loading && widget.onTap != null) {
          // Action destructive → feedback medium (plus perceptible que light)
          HapticFeedback.mediumImpact();
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: widget.height,
        decoration: BoxDecoration(
          color: _pressed
              ? AppTheme.dangerMuted.withOpacity(0.6)
              : AppTheme.dangerSurface,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _pressed
                ? AppTheme.danger.withOpacity(0.5)
                : AppTheme.dangerMuted,
            width: 1,
          ),
        ),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Center(
            child: widget.loading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppTheme.danger)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: AppTheme.danger, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label, style: const TextStyle(
                        color: AppTheme.danger, fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
          ),
        ),
      ),
    );
  }
}