import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:agora_demo/core/util/app_logger_util.dart';

class AudioTestService {
  html.AudioElement? _audioElement;
  StreamController<void>? _playbackCompleteController;

  Stream<void> get onPlaybackComplete => 
      _playbackCompleteController?.stream ?? const Stream.empty();
  
  Future<void> initialize() async {
    _playbackCompleteController = StreamController<void>.broadcast();
  }
  
  Future<void> playTestSoundOld({String? outputDeviceId}) async {
    GSLogger.info("AudioTestService:Web: Playing test sound");
    GSLogger.info("  Requested outputDeviceId: $outputDeviceId");
    
    try {
      // Stop existing playback
      await stopTestSound();
      
      // Recreate the stream controller if it was closed
      if (_playbackCompleteController == null || _playbackCompleteController!.isClosed) {
        _playbackCompleteController = StreamController<void>.broadcast();
      }
      
      // Create new audio element
      _audioElement = html.AudioElement()
        ..src = 'assets/assets/audio/audio.mp3'
        ..crossOrigin = 'anonymous';

      _audioElement!.onEnded.listen((_) {
        GSLogger.info("AudioTestService (web): Playback completed");
        if (_playbackCompleteController != null && !_playbackCompleteController!.isClosed) {
          _playbackCompleteController!.add(null);
        }
      });

      //  Also listen for errors
      _audioElement!.onError.listen((event) {
        GSLogger.error("AudioTestService (web): Playback error: $event");
        if (_playbackCompleteController != null && !_playbackCompleteController!.isClosed) {
          _playbackCompleteController!.add(null);
        }
      });

      // Log current sinkId BEFORE setting
      final currentSinkId = js_util.getProperty(_audioElement!, 'sinkId') ?? '';
      GSLogger.info("  Current sinkId BEFORE setSinkId: '$currentSinkId'");

      // Set output device if specified
      if (outputDeviceId != null && 
          outputDeviceId.isNotEmpty && 
          outputDeviceId != 'default') {
        await _setOutputDevice(outputDeviceId);
      }
      // Log sinkId AFTER setting
      final newSinkId = js_util.getProperty(_audioElement!, 'sinkId') ?? '';
      GSLogger.info("  sinkId AFTER setSinkId: '$newSinkId'");


      // Play the audio
      await _audioElement!.play();
      GSLogger.info("AudioTestService (web): Playback started");
      
    } catch (e) {
      GSLogger.error("AudioTestService (web): Error playing: $e");
      if (_playbackCompleteController != null && !_playbackCompleteController!.isClosed) {
        _playbackCompleteController!.add(null);
      }
      rethrow;
    }
  }
  
  Future<void> playTestSound({String? outputDeviceId}) async {
    GSLogger.info("=== AudioTestService: playTestSound START ===");
    GSLogger.info("  Requested outputDeviceId: $outputDeviceId");

    try {
      // Stop existing playback
      await stopTestSound();

      // Recreate the stream controller if it was closed
      if (_playbackCompleteController == null ||
          _playbackCompleteController!.isClosed) {
        _playbackCompleteController = StreamController<void>.broadcast();
      }

      // Create new audio element
      _audioElement = html.AudioElement()
        ..src = 'assets/assets/audio/audio.mp3'
        ..crossOrigin = 'anonymous';

      // Add event listeners
      _audioElement!.onEnded.listen((_) {
        GSLogger.info("AudioTestService: Playback completed (onEnded)");
        _notifyCompletion();
      });

      _audioElement!.onError.listen((event) {
        GSLogger.error("AudioTestService: Playback error: $event");
        _notifyCompletion();
      });

      // Log current sinkId BEFORE setting
      GSLogger.info("  Current sinkId BEFORE setSinkId: '${_audioElement!.sinkId}'");

      // Set output device if specified and not default
      if (outputDeviceId != null &&
          outputDeviceId.isNotEmpty &&
          outputDeviceId != 'default') {
        
        GSLogger.info("  Current sinkId BEFORE setSinkId: '${_audioElement!.sinkId}'");

        await _setOutputDevice(outputDeviceId);
      } else {
        GSLogger.info("  Using default audio output (no setSinkId call)");
      }

      // Log sinkId AFTER setting
      GSLogger.info("  sinkId AFTER setSinkId: '${_audioElement!.sinkId}'");

      // Play the audio
      await _audioElement!.play();
      GSLogger.info("=== AudioTestService: Playback started ===");
    } catch (e) {
      GSLogger.error("AudioTestService: Error in playTestSound: $e");
      _notifyCompletion();
      rethrow;
    }
  }

  /// Uses the native dart:html setSinkId method
  Future<void> _setOutputDevice(String deviceId) async {
    if (_audioElement == null) {
      GSLogger.error("_setOutputDevice: audioElement is null!");
      return;
    }

    GSLogger.info("_setOutputDevice: Calling setSinkId('$deviceId')...");

    try {
      // Use native dart:html setSinkId method
      await _audioElement!.setSinkId(deviceId);

      // Verify the change
      GSLogger.info("_setOutputDevice: setSinkId completed");
      GSLogger.info("_setOutputDevice: Actual sinkId is now: '${_audioElement!.sinkId}'");

      // Verify it matches what we requested
      if (_audioElement!.sinkId != deviceId) {
        GSLogger.warning(
            "_setOutputDevice: WARNING! sinkId (${_audioElement!.sinkId}) != requested ($deviceId)");
      }
    } catch (e) {
      GSLogger.error("_setOutputDevice: setSinkId failed with error: $e");
      GSLogger.error("_setOutputDevice: Error type: ${e.runtimeType}");
    }
  }

  void _notifyCompletion() {
    if (_playbackCompleteController != null &&
        !_playbackCompleteController!.isClosed) {
      _playbackCompleteController!.add(null);
    }
  }


  Future<void> _setOutputDeviceOld(String deviceId) async {
    if (_audioElement == null) {
      GSLogger.error("_setOutputDevice: audioElement is null!");
      return;
    }

    GSLogger.info("AudioTestService: Calling setSinkId('$deviceId')...");

    try {


      // Check if setSinkId is supported
      if (!js_util.hasProperty(_audioElement!, 'setSinkId')) {
        GSLogger.error("_setOutputDevice: setSinkId NOT supported!");
        return;
      }

      GSLogger.info("_setOutputDevice: setSinkId is supported");
      GSLogger.info("_setOutputDevice: Calling setSinkId('$deviceId')...");

      await js_util.promiseToFuture(
        js_util.callMethod(_audioElement!, 'setSinkId', [deviceId]),
      );

      // Verify the change
      final actualSinkId = js_util.getProperty(_audioElement!, 'sinkId') ?? '';
      GSLogger.info("_setOutputDevice: setSinkId completed");
      GSLogger.info("_setOutputDevice: Actual sinkId is now: '$actualSinkId'");

      // Verify it matches what we requested
      if (actualSinkId != deviceId) {
        GSLogger.warning(
            "_setOutputDevice: WARNING! sinkId ($actualSinkId) != requested ($deviceId)");
      }
      
    } catch (e) {
      GSLogger.error("_setOutputDevice: setSinkId failed with error: $e");
      // Log the error type for debugging
      GSLogger.error("_setOutputDevice: Error type: ${e.runtimeType}");
    }
  }
  
  Future<void> stopTestSound() async {
    if (_audioElement != null) {
      _audioElement!.pause();
      _audioElement!.src = '';
      _audioElement = null;
    }
  }
  
  void dispose() {
    stopTestSound();
    _playbackCompleteController?.close();
    _playbackCompleteController = null;
  }
}