// lib/config/channel/audio_output_helper_web.dart
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:agora_demo/core/util/app_logger_util.dart';

/// Sets the audio output device on ALL audio and video elements in the page.
Future<void> setAudioOutputDevice(String deviceId) async {
  GSLogger.info(
      "audio_output_helper_web config/channel: Setting audio output to: $deviceId");

  if (deviceId.isEmpty) {
    GSLogger.info("audio_output_helper_web: Empty deviceId, skipping");
    return;
  }
  try {
    // Find all audio elements
    final audioElements = html.document.querySelectorAll('audio');
    // Find all video elements (they also have audio)
    final videoElements = html.document.querySelectorAll('video');
    GSLogger.info("  Found ${audioElements.length} audio elements");
    GSLogger.info("  Found ${videoElements.length} video elements");

    int successCount = 0;
    int failCount = 0;

    // Apply to all audio elements
    for (final element in audioElements) {
      if (element is html.AudioElement) {
        final result = await _applySinkIdToAudio(element, deviceId);
        if (result) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    // Apply to all video elements
    for (final element in videoElements) {
      if (element is html.VideoElement) {
        final result = await _applySinkIdToVideo(element, deviceId);
        if (result) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    GSLogger.info("  Applied to $successCount elements, failed on $failCount");
    GSLogger.info("=== audio_output_helper_web: END ===");
  } catch (e) {
    GSLogger.error("audio_output_helper_web: Error: $e");
  }
}

/// Applies setSinkId to an AudioElement using native dart:html method
Future<bool> _applySinkIdToAudio(
    html.AudioElement element, String deviceId) async {
  try {
    GSLogger.info("  Audio element current sinkId: '${element.sinkId}'");

    // Use native dart:html setSinkId method
    await element.setSinkId(deviceId);

    GSLogger.info("  Audio element new sinkId: '${element.sinkId}'");
    return element.sinkId == deviceId;
  } catch (e) {
    GSLogger.error("  Failed to set sinkId on audio element: $e");
    return false;
  }
}

/// Applies setSinkId to a VideoElement using native dart:html method
Future<bool> _applySinkIdToVideo(
    html.VideoElement element, String deviceId) async {
  try {
    GSLogger.info("  Video element current sinkId: '${element.sinkId}'");

    // ⭐ Use native dart:html setSinkId method
    await element.setSinkId(deviceId);

    GSLogger.info("  Video element new sinkId: '${element.sinkId}'");
    return element.sinkId == deviceId;
  } catch (e) {
    GSLogger.error("  Failed to set sinkId on video element: $e");
    return false;
  }
}

