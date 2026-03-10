import 'dart:io';
import 'package:flutter/foundation.dart';

class VideoConstraintsHelper {
  /// Returns appropriate video constraints for the current platform
  static Map<String, dynamic> getConstraints({
    String? deviceId,
    int idealWidth = 1280,
    int idealHeight = 720,
  }) {
    if (kIsWeb) {
      return _webConstraints(deviceId, idealWidth, idealHeight);
    } else if (Platform.isIOS) {
      return _iosConstraints(deviceId, idealWidth, idealHeight);
    } else if (Platform.isAndroid) {
      return _androidConstraints(deviceId, idealWidth, idealHeight);
    } else {
      return _desktopConstraints(deviceId, idealWidth, idealHeight);
    }
  }

  static Map<String, dynamic> _webConstraints(String? deviceId, int w, int h) {
    return deviceId != null && deviceId.isNotEmpty && deviceId != 'default'
        ? {'deviceId': {'exact': deviceId}, 'width': {'ideal': w}, 'height': {'ideal': h}}
        : {'width': {'ideal': w}, 'height': {'ideal': h}};
  }

  static Map<String, dynamic> _iosConstraints(String? deviceId, int w, int h) {
    // iOS: Use facingMode instead of deviceId
    final isFrontCamera = deviceId?.contains('video:1') == true ||
                          deviceId?.toLowerCase().contains('front') == true;
    return {
      'facingMode': isFrontCamera ? 'user' : 'environment',
      'width': {'ideal': w},
      'height': {'ideal': h},
    };
  }

  static Map<String, dynamic> _androidConstraints(String? deviceId, int w, int h) {
    // Android: Similar to iOS, facingMode is more reliable
    // Some Android devices crash with exact deviceId
    final isFrontCamera = deviceId?.contains('front') == true ||
                          deviceId?.contains('1') == true;
    return {
      'facingMode': isFrontCamera ? 'user' : 'environment',
      'width': {'ideal': w},
      'height': {'ideal': h},
    };
  }

  static Map<String, dynamic> _desktopConstraints(String? deviceId, int w, int h) {
    // Desktop (Windows/macOS/Linux): deviceId works fine
    return deviceId != null && deviceId.isNotEmpty && deviceId != 'default'
        ? {'deviceId': {'exact': deviceId}, 'width': {'ideal': w}, 'height': {'ideal': h}}
        : {'width': {'ideal': w}, 'height': {'ideal': h}};
  }
}