import 'dart:async';

import 'package:agora_demo/core/screens/classroom/audio_test_service.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:agora_demo/core/screens/classroom/audio_output_helper.dart'  as audio_helper;



// An enum to represent the possible states of our test button.
enum SpeakerTestState { ready, playing, error }


class AudioOutputCheckWidget extends ConsumerStatefulWidget {
  const AudioOutputCheckWidget({super.key});

  @override
  ConsumerState<AudioOutputCheckWidget> createState() => _AudioOutputCheckWidgetState();
}

class _AudioOutputCheckWidgetState extends ConsumerState<AudioOutputCheckWidget> {
  
  final AudioTestService _audioTestService = AudioTestService();
  StreamSubscription<void>? _playbackCompleteSubscription;
  SpeakerTestState _testState = SpeakerTestState.ready;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _audioTestService.initialize();
    
    // Listen for playback completion
    _playbackCompleteSubscription = _audioTestService.onPlaybackComplete.listen((_) {
      GSLogger.info("AudioOutputCheckWidget: Received playback complete event");
      if (mounted) {
        setState(() {
          _testState = SpeakerTestState.ready;
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _playbackCompleteSubscription?.cancel();
    _audioTestService.dispose();
    super.dispose();
  }

  
  Future<void> _startSpeakerTest() async {

    final selectedDeviceId = ref.read(deviceSelectionProvider).audioOutputDeviceId;

    GSLogger.info("AudioOutputCheckWidget: Starting speaker test");
    GSLogger.info("  selectedDeviceId: ${selectedDeviceId}");
    
    setState(() {
      _testState = SpeakerTestState.playing;
      _isPlaying = true;
    });

    try {
      await _audioTestService.playTestSound(
        outputDeviceId: selectedDeviceId,
      );
    } catch (e) {
      GSLogger.error("AudioOutputCheckWidget: Error playing test sound: $e");
      if (mounted) {
        setState(() {
          _testState = SpeakerTestState.ready;
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _stopSpeakerTest() async {
    GSLogger.info("AudioOutputCheckWidget: Stopping speaker test");
    
    await _audioTestService.stopTestSound();
    
    if (mounted) {
      setState(() {
        _testState = SpeakerTestState.ready;
        _isPlaying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isPlaying ? _stopSpeakerTest : _startSpeakerTest,
      icon: Icon(_isPlaying ? Icons.stop : Icons.volume_up),
      label: Text(_isPlaying ? 'Stop Test' : 'Test Speaker'),
    );
  }
}



class AudioOutputTestWidget extends ConsumerStatefulWidget {
  
  final String? selectedDeviceId;

  const AudioOutputTestWidget({super.key, this.selectedDeviceId});

  @override
  ConsumerState<AudioOutputTestWidget> createState() =>
      _AudioOutputTestWidgetState();
}

class _AudioOutputTestWidgetState extends ConsumerState<AudioOutputTestWidget> {

  final AudioPlayer _audioPlayer = AudioPlayer();
  SpeakerTestState _testState = SpeakerTestState.ready;
  StreamSubscription? _playerCompleteSubscription;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((event) {
      // When the audio finishes playing naturally, we reset the state.
      if (mounted) {
        setState(() {
          _testState = SpeakerTestState.ready;
          _isPlaying = false; 
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioOutputTestWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If selected device changed while playing, update the output device
    if (oldWidget.selectedDeviceId != widget.selectedDeviceId && _isPlaying) {
      _setOutputDevice();
    }
  }

  Future<void> _setOutputDevice() async {
    final deviceId = widget.selectedDeviceId;
    GSLogger.info("AudioOutputCheckWidget._setOutputDevice: START");
    GSLogger.info("  widget.selectedDeviceId = '$deviceId'");

    if (deviceId == null || deviceId.isEmpty) {
      GSLogger.info(
          "AudioOutputCheckWidget._setOutputDevice: No device selected");
      return;
    }

    // Add a bit more delay to ensure audioplayers has created the element
    await Future.delayed(const Duration(milliseconds: 200));

    GSLogger.info(
        "AudioOutputCheckWidget._setOutputDevice: Calling setAudioOutputDevice...");
    await audio_helper.setAudioOutputDevice(deviceId);
    GSLogger.info("AudioOutputCheckWidget._setOutputDevice: END");
  }
  
  /// Plays the test sound. Can be called multiple times to restart the audio.
  Future<void> _startSpeakerTest() async {
    setState(() {
      _testState = SpeakerTestState.playing;
      _isPlaying = true;
    });

    try {

      // First, stop any existing playback
      await _audioPlayer.stop();
      
      // Load the audio source (this creates the HTML audio element)
      await _audioPlayer.setSource(AssetSource('audio/audio.mp3'));
      
      // Wait for element to be created
      await Future.delayed(const Duration(milliseconds: 100));

      // Set the output device (after element exists)
      await _setOutputDevice();

      // Set output device before playing
      // Finally, play the audio
      await _audioPlayer.resume();

      await Future.delayed(const Duration(milliseconds: 100));
      await _setOutputDevice();

    } catch (e) {
      GSLogger.error("Error playing test sound: $e");
      //GsSnackbar.showSnackBar("Could not play test sound.");
      // If an error occurs (e.g., file not found), reset the state.
      if (mounted) {
        setState(() {
          _testState = SpeakerTestState.ready;
        });
      }
    }
  }

  /// A getter to check if the audio is currently playing.
  bool get isPlaying => _testState == SpeakerTestState.playing;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _startSpeakerTest,
      
      child: Text(
        isPlaying ? "Playing..." : "Play Audio",
        
      ),
    );
  }
}
