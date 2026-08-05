import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/device_service.dart';

class ForceUpdateInfo {
  final bool required;
  final String minVersion;
  final String latestVersion;
  final String apkUrl;
  final String message;

  const ForceUpdateInfo({
    required this.required,
    this.minVersion = '',
    this.latestVersion = '',
    this.apkUrl = '',
    this.message = '',
  });
}

class UpdateService {
  static Future<ForceUpdateInfo> checkForceUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final current = pkg.version;

      final rows = await Supabase.instance.client
          .from('app_config')
          .select('key, value')
          .inFilter('key', [
        'min_version',
        'latest_version',
        'apk_url',
        'force_update',
        'force_update_message',
        'dev_bypass_enabled',
        'dev_bypass_keys',
        'dev_bypass_emails',
      ]);

      final cfg = <String, String>{
        for (final r in rows) r['key'] as String: (r['value'] ?? '').toString(),
      };

      if (await _isDevBypass(cfg)) {
        return const ForceUpdateInfo(required: false);
      }

      final forceFlag = (cfg['force_update'] ?? 'false').toLowerCase() == 'true';
      final minVersion = cfg['min_version'] ?? '';
      final latest = cfg['latest_version'] ?? minVersion;
      final apkUrl = cfg['apk_url'] ?? '';
      final message = (cfg['force_update_message'] ?? '').trim().isNotEmpty
          ? cfg['force_update_message']!.trim()
          : 'Une mise à jour est requise pour continuer à utiliser Arich Player.';

      final needsUpdate = forceFlag && minVersion.isNotEmpty &&
          _compareVersions(current, minVersion) < 0;

      return ForceUpdateInfo(
        required: needsUpdate,
        minVersion: minVersion,
        latestVersion: latest,
        apkUrl: apkUrl,
        message: message,
      );
    } catch (e) {
      debugPrint('[UpdateService] $e');
      return const ForceUpdateInfo(required: false);
    }
  }

  static Future<void> openStore(String apkUrl) async {
    final playStore = Uri.parse('market://details?id=com.arich.iptv');
    final webStore = Uri.parse('https://play.google.com/store/apps/details?id=com.arich.iptv');
    final custom = apkUrl.isNotEmpty ? Uri.tryParse(apkUrl) : null;

    for (final uri in [custom, playStore, webStore]) {
      if (uri == null) continue;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
  }

  static Future<bool> _isDevBypass(Map<String, String> cfg) async {
    if (kDebugMode) return true;
    if ((cfg['dev_bypass_enabled'] ?? 'false').toLowerCase() != 'true') {
      return false;
    }
    final keys = (cfg['dev_bypass_keys'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final emails = (cfg['dev_bypass_emails'] ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    final identity = await DeviceService.getOrCreate();
    if (keys.contains(identity.deviceKey)) return true;

    final email = Supabase.instance.client.auth.currentUser?.email?.toLowerCase();
    if (email != null && emails.contains(email)) return true;

    return false;
  }

  static int _compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final da = i < pa.length ? pa[i] : 0;
      final db = i < pb.length ? pb[i] : 0;
      if (da != db) return da.compareTo(db);
    }
    return 0;
  }
}
