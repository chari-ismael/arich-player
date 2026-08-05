// lib/services/app_update_service.dart
// Vérifie min_version / latest_version depuis app_config Supabase.
// Bloque l'app si version < min_version (mise à jour obligatoire).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';

class AppUpdateInfo {
  final bool updateRequired;
  final bool updateAvailable;
  final String minVersion;
  final String latestVersion;
  final String apkUrl;
  final String playStoreUrl;

  const AppUpdateInfo({
    this.updateRequired = false,
    this.updateAvailable = false,
    this.minVersion = '0.0.0',
    this.latestVersion = '0.0.0',
    this.apkUrl = '',
    this.playStoreUrl = 'https://play.google.com/store/apps/details?id=com.arich.iptv',
  });
}

class AppUpdateService {
  static Future<AppUpdateInfo> check(String currentVersion) async {
    try {
      final rows = await Supabase.instance.client
          .from('app_config')
          .select('key, value')
          .inFilter('key', [
            'min_version',
            'latest_version',
            'apk_url',
            'play_store_url',
            'force_update',
          ]);

      final cfg = <String, String>{};
      for (final row in rows as List) {
        final k = row['key'] as String?;
        final v = row['value'] as String?;
        if (k != null && v != null) cfg[k] = v;
      }

      final minV    = cfg['min_version'] ?? '0.0.0';
      final latestV = cfg['latest_version'] ?? currentVersion;
      final force   = (cfg['force_update'] ?? 'false').toLowerCase() == 'true';
      final apkUrl  = cfg['apk_url'] ?? '';
      final playUrl = cfg['play_store_url'] ??
          'https://play.google.com/store/apps/details?id=com.arich.iptv';

      final belowMin    = _compareVersions(currentVersion, minV) < 0;
      final belowLatest = _compareVersions(currentVersion, latestV) < 0;

      return AppUpdateInfo(
        updateRequired: belowMin || (force && belowLatest),
        updateAvailable: belowLatest,
        minVersion: minV,
        latestVersion: latestV,
        apkUrl: apkUrl,
        playStoreUrl: playUrl,
      );
    } catch (e) {
      debugPrint('[AppUpdate] check error: $e');
      return const AppUpdateInfo();
    }
  }

  /// Affiche un écran bloquant si mise à jour obligatoire.
  static Future<void> enforceIfNeeded(
    BuildContext context,
    String currentVersion,
  ) async {
    final info = await check(currentVersion);
    if (!context.mounted || !info.updateRequired) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Mise à jour requise',
            style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          content: Text(
            'Une nouvelle version (${info.latestVersion}) est obligatoire pour continuer à utiliser ARICH Player.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => _openStore(info),
              child: const Text(
                'Mettre à jour',
                style: TextStyle(color: AppTheme.violet, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openStore(AppUpdateInfo info) async {
    final url = info.apkUrl.isNotEmpty ? info.apkUrl : info.playStoreUrl;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static int _compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }
}
