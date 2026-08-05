// lib/services/media_kit_native_real.dart

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

Future<void> setNativeProperty(Player player, String key, String value) async {
  try {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(key, value);
    }
  } catch (e) {
    debugPrint('[NativeHelper] setProperty($key) error: $e');
  }
}