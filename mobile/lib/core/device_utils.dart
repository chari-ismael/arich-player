import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceUtils {
  static Future<String> getDeviceKey() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String rawId = "UNKNOWN";

    if (Platform.isAndroid || Platform.operatingSystem == 'tizen') {
      // Android et Tizen retournent des infos similaires via DeviceInfoPlugin
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      rawId = androidInfo.id; // ANDROID_ID / uuid de l'appareil
    } else if (Platform.isIOS) {
      final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      rawId = iosInfo.identifierForVendor ?? "UNKNOWN";
    }

    String cleanId = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (cleanId.length < 12) {
      cleanId = cleanId.padRight(12, '0');
    }
    
    return 'ARICH-${cleanId.substring(0, 4)}-${cleanId.substring(4, 8)}-${cleanId.substring(8, 12)}';
  }

  static Future<String> getDeviceModel() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid || Platform.operatingSystem == 'tizen') {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return '${androidInfo.brand} ${androidInfo.model}';
    }
    return Platform.operatingSystem;
  }
}