import 'dart:async';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class MicTestController {
  Function(double level)? onLevelChanged;
  Function(bool isWorking)? onMicStatusChanged;
  
  bool _isTestingMic = false;
  bool get isTestingMic => _isTestingMic;
  
  double _micLevel = 0.0;
  double get micLevel => _micLevel;
  
  bool _micIsWorking = false;
  bool get micIsWorking => _micIsWorking;

  // WebRTC objects for loopback
  MediaStream? _localStream;
  RTCPeerConnection? _loopbackSenderPc;
  RTCPeerConnection? _loopbackReceiverPc;
  RTCRtpSender? _audioSender;
  StreamSubscription? _audioLevelSubscription;

  Future<void> startMicTest(String? deviceId) async {
    if (_isTestingMic) return;

    try {
      // 1. Get media stream with the specified device
      /*final constraints = {
        'audio': deviceId != null
            ? {'deviceId': {'exact': deviceId}}
            : true,
        'video': false,
      };*/

      final constraints = {
        'audio': deviceId != null
            ? {'deviceId': deviceId}
            : true,
        'video': false,
      };


      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      
      final audioTrack = _localStream!.getAudioTracks().firstOrNull;
      if (audioTrack == null) {
        GSLogger.error("No audio track found");
        await stopMicTest();
        return;
      }

      // 2. Create loopback peer connections
      _loopbackSenderPc = await createPeerConnection({});
      _loopbackReceiverPc = await createPeerConnection({});

      // 3. Setup ICE candidate exchange
      _loopbackSenderPc!.onIceCandidate = (candidate) {
        if (candidate != null) {
          _loopbackReceiverPc?.addCandidate(candidate);
        }
      };

      _loopbackReceiverPc!.onIceCandidate = (candidate) {
        if (candidate != null) {
          _loopbackSenderPc?.addCandidate(candidate);
        }
      };

      // 4. Add audio track to sender
      _audioSender = await _loopbackSenderPc!.addTrack(audioTrack, _localStream!);

      // 5. Perform offer/answer exchange
      final offer = await _loopbackSenderPc!.createOffer();
      await _loopbackSenderPc!.setLocalDescription(offer);
      await _loopbackReceiverPc!.setRemoteDescription(offer);

      final answer = await _loopbackReceiverPc!.createAnswer();
      await _loopbackReceiverPc!.setLocalDescription(answer);
      await _loopbackSenderPc!.setRemoteDescription(answer);

      _isTestingMic = true;
      _micIsWorking = false;
      _micLevel = 0.0;

      // 6. Start polling for audio level stats
      _audioLevelSubscription = Stream.periodic(const Duration(milliseconds: 100)).listen((_) async {
        await _checkAudioLevel();
      });

      GSLogger.info("Mic test started with device: $deviceId");
    } catch (e) {
      GSLogger.error("Error starting mic test: $e");
      await stopMicTest();
    }
  }

  Future<void> _checkAudioLevel() async {
    if (_audioSender == null || !_isTestingMic) return;

    try {
      final stats = await _audioSender!.getStats();
      double level = 0.0;

      for (final report in stats) {
        // Find the report that contains the audio level information
        if (report.type == 'media-source' && report.values.containsKey('audioLevel')) {
          level = (report.values['audioLevel'] ?? 0.0).toDouble();
          break;
        }
      }

      _micLevel = level;
      onLevelChanged?.call(_micLevel);

      // Check if microphone is working (detecting sound)
      const double workingThreshold = 0.05;
      if (!_micIsWorking && level > workingThreshold) {
        _micIsWorking = true;
        onMicStatusChanged?.call(true);
        GSLogger.info("Microphone is working - sound detected!");
      }
    } catch (e) {
      GSLogger.error("Error getting audio stats: $e");
    }
  }

  Future<void> stopMicTest() async {
    _isTestingMic = false;

    // Cancel the stats subscription
    await _audioLevelSubscription?.cancel();
    _audioLevelSubscription = null;

    // Close peer connections
    await _loopbackSenderPc?.close();
    await _loopbackReceiverPc?.close();
    _loopbackSenderPc = null;
    _loopbackReceiverPc = null;
    _audioSender = null;

    // Stop and dispose media stream
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      await _localStream!.dispose();
      _localStream = null;
    }

    _micLevel = 0.0;
    _micIsWorking = false;

    GSLogger.info("Mic test stopped");
  }

  void dispose() {
    stopMicTest();
  }
}