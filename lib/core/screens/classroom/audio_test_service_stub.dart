import 'dart:async';

import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioTestService {
  AudioPlayer? _audioPlayer;
  StreamController<void>? _playbackCompleteController;
  StreamSubscription? _playerCompleteSubscription;

  /// Stream that emits when audio playback completes
  Stream<void> get onPlaybackComplete => 
      _playbackCompleteController?.stream ?? const Stream.empty();
 
  
  Future<void> initialize() async {
    _audioPlayer = AudioPlayer();
    _playbackCompleteController = StreamController<void>.broadcast();
    
    // Listen for playback completion
    _playerCompleteSubscription = _audioPlayer!.onPlayerComplete.listen((_) {
      GSLogger.info("AudioTestService (mobile): Playback completed");
      _playbackCompleteController?.add(null);
    });
  }
  
  Future<void> playTestSound({String? outputDeviceId}) async {
    GSLogger.info("AudioTestService (mobile): Playing test sound");
    GSLogger.info("  Note: Device selection not supported on mobile");
    
    await _audioPlayer?.stop();
    await _audioPlayer?.setSource(AssetSource('audio/audio.mp3'));
    await _audioPlayer?.resume();
  }
  
  Future<void> stopTestSound() async {
    await _audioPlayer?.stop();
  }
  
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _playbackCompleteController?.close();
    _playbackCompleteController = null;
  }
}