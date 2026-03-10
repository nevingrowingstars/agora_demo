import 'dart:async';
import 'package:agora_demo/core/model/media_availability_status.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final mediaAvailabilityStatusProvider =
    StateNotifierProvider<MediaAvailabilityNotifier, MediaAvailabilityStatus>(
  (ref) => MediaAvailabilityNotifier(),
);

class MediaAvailabilityNotifier extends StateNotifier<MediaAvailabilityStatus> {
  MediaAvailabilityNotifier() : super(MediaAvailabilityStatus.initial());

  Future<void> checkAvailability() async {
    GSLogger.info("=== Checking media availability ===");

    state = MediaAvailabilityStatus.checking();

    bool audioAvailable = false;
    bool videoAvailable = false;
    String? audioError;
    String? videoError;

    // Check audio
    try {
      final audioStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false})
          .timeout(const Duration(seconds: 5));

      for (final track in audioStream.getAudioTracks()) {
        track.stop();
      }
      await audioStream.dispose();

      audioAvailable = true;
      GSLogger.info("  Audio: Available ✓");
    } catch (e) {
      audioError = _parseMediaError(e, 'microphone');
      GSLogger.error("  Audio: $audioError");
    }

    // Check video
    try {
      final videoStream = await navigator.mediaDevices
          .getUserMedia({'audio': false, 'video': true})
          .timeout(const Duration(seconds: 5));

      for (final track in videoStream.getVideoTracks()) {
        track.stop();
      }
      await videoStream.dispose();

      videoAvailable = true;
      GSLogger.info("  Video: Available ✓");
    } catch (e) {
      videoError = _parseMediaError(e, 'camera');
      GSLogger.error("  Video: $videoError");
    }

    state = MediaAvailabilityStatus(
      audioAvailable: audioAvailable,
      videoAvailable: videoAvailable,
      audioError: audioError,
      videoError: videoError,
      isChecking: false,
    );

    GSLogger.info("=== Media check complete: $state ===");
  }

  String _parseMediaError(dynamic error, String deviceType) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('timeout')) {
      return '$deviceType may be in use by another application (Teams, Zoom, etc.)';
    } else if (errorStr.contains('notallowederror') ||
        errorStr.contains('permission')) {
      return '$deviceType permission denied. Please allow access.';
    } else if (errorStr.contains('notfounderror') ||
        errorStr.contains('not found')) {
      return 'No $deviceType found. Please connect a device.';
    } else if (errorStr.contains('notreadableerror') ||
        errorStr.contains('could not start')) {
      return '$deviceType is in use by another application.';
    }

    return 'Unable to access $deviceType.';
  }

  void reset() {
    state = MediaAvailabilityStatus.initial();
  }
}