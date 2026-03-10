import 'package:agora_demo/core/util/app_logger_util.dart';

/// Stub for non-web platforms
Future<void> setAudioOutputDevice(String deviceId) async {
  GSLogger.info("audio_output_helper_stub: Audio output device selection not supported on this platform");
}