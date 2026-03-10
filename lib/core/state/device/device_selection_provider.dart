import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The state object that holds the selected device IDs.
@immutable
class DeviceSelectionState {
  final String? audioInputDeviceId;
  final String? audioOutputDeviceId;
  final String? videoInputDeviceId;
  final bool isAudioEnabledOnJoin;
  final bool isVideoEnabledOnJoin;

  const DeviceSelectionState({
    this.audioInputDeviceId,
    this.audioOutputDeviceId,
    this.videoInputDeviceId,
    // They default to true, so mic and camera are on by default.
    this.isAudioEnabledOnJoin = true,
    this.isVideoEnabledOnJoin = true,
  });

  DeviceSelectionState copyWith({
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    String? videoInputDeviceId,
    bool? isAudioEnabledOnJoin,
    bool? isVideoEnabledOnJoin,
  }) {
    return DeviceSelectionState(
      audioInputDeviceId: audioInputDeviceId ?? this.audioInputDeviceId,
      audioOutputDeviceId: audioOutputDeviceId ?? this.audioOutputDeviceId,
      videoInputDeviceId: videoInputDeviceId ?? this.videoInputDeviceId,
      isAudioEnabledOnJoin: isAudioEnabledOnJoin ?? this.isAudioEnabledOnJoin,
      isVideoEnabledOnJoin: isVideoEnabledOnJoin ?? this.isVideoEnabledOnJoin,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceSelectionState &&
        other.audioInputDeviceId == audioInputDeviceId &&
        other.audioOutputDeviceId == audioOutputDeviceId &&
        other.videoInputDeviceId == videoInputDeviceId &&
        other.isAudioEnabledOnJoin == isAudioEnabledOnJoin &&
        other.isVideoEnabledOnJoin == isVideoEnabledOnJoin;
  }

  @override
  int get hashCode => Object.hash(
        audioInputDeviceId,
        audioOutputDeviceId,
        videoInputDeviceId,
        isAudioEnabledOnJoin,
        isVideoEnabledOnJoin,
      );

  @override
  String toString() {
    return 'DeviceSelectionState('
        'audioInput: $audioInputDeviceId, '
        'audioOutput: $audioOutputDeviceId, '
        'videoInput: $videoInputDeviceId, '
        'audioEnabled: $isAudioEnabledOnJoin, '
        'videoEnabled: $isVideoEnabledOnJoin)';
  }
}

class DeviceListState {
  final List<MediaDeviceInfo> audioInputs;
  final List<MediaDeviceInfo> audioOutputs;
  final List<MediaDeviceInfo> videoInputs;
  // We can add outputs here in the future
  const DeviceListState(
      {this.audioInputs = const [],
      this.audioOutputs = const [],
      this.videoInputs = const []});

  DeviceListState copyWith({
    List<MediaDeviceInfo>? audioInputs,
    List<MediaDeviceInfo>? audioOutputs,
    List<MediaDeviceInfo>? videoInputs,
  }) {
    return DeviceListState(
      audioInputs: audioInputs ?? this.audioInputs,
      audioOutputs: audioOutputs ?? this.audioOutputs,
      videoInputs: videoInputs ?? this.videoInputs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceListState &&
        _listEquals(other.audioInputs, audioInputs) &&
        _listEquals(other.audioOutputs, audioOutputs) && // Add this
        _listEquals(other.videoInputs, videoInputs);
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      audioInputs.hashCode ^
      audioOutputs.hashCode ^ // Add this
      videoInputs.hashCode;

  @override
  String toString() {
    return 'DeviceListState(audioInputs: ${audioInputs.length}, audioOutputs: ${audioOutputs.length}, videoInputs: ${videoInputs.length})';
  }
}

final deviceListProvider =
    StateNotifierProvider<DeviceManagerNotifier, DeviceListState>(
  (ref) => DeviceManagerNotifier(ref),
);

class DeviceManagerNotifier extends StateNotifier<DeviceListState> {
  final Ref _ref;

  DeviceManagerNotifier(this._ref) : super(const DeviceListState()) {
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    GSLogger.info("=== DeviceManagerNotifier: _loadDevices() START ===");

    try {
      // Step 1: Initial enumeration
      var devices = await navigator.mediaDevices.enumerateDevices();
      GSLogger.info(
          "Step 1: Initial enumeration found ${devices.length} devices");

      // Step 2: Check for empty labels
      // final hasEmptyLabels = devices.any((d) => d.label.isEmpty);
      // Step 2: Check for empty labels (permission not granted yet)
      final hasEmptyLabels = devices.any((d) =>
          d.label.isEmpty && d.deviceId != 'default' && d.deviceId.isNotEmpty);

      GSLogger.info("Step 2: Has empty labels: $hasEmptyLabels");

      if (hasEmptyLabels || devices.length <= 3) {
        GSLogger.info("Step 3: Requesting media permissions...");
        await _requestMediaPermissions();

        // Re-enumerate
        devices = await navigator.mediaDevices.enumerateDevices();
        GSLogger.info(
            "Step 4: After permission, found ${devices.length} devices");
      }

      // Step 5: Log all raw devices
      GSLogger.info("Step 5: All devices:");
      for (var d in devices) {
        GSLogger.info(
            "  kind=${d.kind}, label='${d.label}', id=${d.deviceId}...");
      }

      // Step 6: Filter by kind
      final audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      final audioOutputs =
          devices.where((d) => d.kind == 'audiooutput').toList();
      final videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

      GSLogger.info("Step 6: Filtered counts:");
      GSLogger.info("  Audio Inputs: ${audioInputs.length}");
      GSLogger.info("  Audio Outputs: ${audioOutputs.length}");
      GSLogger.info("  Video Inputs: ${videoInputs.length}");

      // Step 7: Update state
      state = DeviceListState(
        audioInputs: audioInputs,
        audioOutputs: audioOutputs,
        videoInputs: videoInputs,
      );

      GSLogger.info("Step 7: State updated: ${state.toString()}");

      // Step 8: Set defaults
      _setDefaultSelections(audioInputs, audioOutputs, videoInputs);

      GSLogger.info("=== DeviceManagerNotifier: _loadDevices() END ===");
    } catch (e, stack) {
      GSLogger.error("DeviceManagerNotifier: Error in _loadDevices: $e");
      GSLogger.error("Stack: $stack");
    }
  }

  Future<void> _requestMediaPermissions() async {
    try {
      // Request both audio and video permissions
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });

      // Stop the tracks immediately - we just needed permission
      stream.getTracks().forEach((track) => track.stop());
      await stream.dispose();

      GSLogger.info("Media permissions granted");
    } catch (e) {
      GSLogger.error("Error requesting media permissions: $e");

      // Try audio only if video fails
      try {
        final audioStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        audioStream.getTracks().forEach((track) => track.stop());
        await audioStream.dispose();
        GSLogger.info("Audio permission granted (video failed)");
      } catch (e) {
        GSLogger.error("Error requesting audio permission: $e");
      }
    }
  }

  void _setDefaultSelections(
    List<MediaDeviceInfo> audioInputs,
    List<MediaDeviceInfo> audioOutputs,
    List<MediaDeviceInfo> videoInputs,
  ) {
    final selectionNotifier = _ref.read(deviceSelectionProvider.notifier);
    final currentSelection = _ref.read(deviceSelectionProvider);

    // Set default audio input if not already set
    if (audioInputs.isNotEmpty && currentSelection.audioInputDeviceId == null) {
      final defaultDevice = _findDefaultDevice(audioInputs);
      selectionNotifier.setAudioInputDevice(defaultDevice.deviceId);
      GSLogger.info("Default audio input set: ${defaultDevice.label}");
    }

    // Set default audio output if not already set
    if (audioOutputs.isNotEmpty &&
        currentSelection.audioOutputDeviceId == null) {
      final defaultDevice = _findDefaultDevice(audioOutputs);
      selectionNotifier.setAudioOutputDevice(defaultDevice.deviceId);
      GSLogger.info("Default audio output set: ${defaultDevice.label}");
    }

    // Set default video input if not already set
    if (videoInputs.isNotEmpty && currentSelection.videoInputDeviceId == null) {
      final defaultDevice = _findDefaultDevice(videoInputs);
      selectionNotifier.setVideoInputDevice(defaultDevice.deviceId);
      GSLogger.info("Default video input set: ${defaultDevice.label}");
    }
  }

  /// Finds the default device from the list.
  /// Priority:
  /// 1. Device with deviceId == 'default'
  /// 2. Device with label containing 'default' (case-insensitive)
  /// 3. First device in the list
  MediaDeviceInfo _findDefaultDevice(List<MediaDeviceInfo> devices) {
    if (devices.isEmpty) {
      throw ArgumentError('Device list cannot be empty');
    }

    // Priority 1: Device with deviceId == 'default'
    final defaultById = devices.firstWhereOrNull(
      (device) => device.deviceId == 'default',
    );
    if (defaultById != null) return defaultById;

    // Priority 2: Device with label containing 'default'
    final defaultByLabel = devices.firstWhereOrNull(
      (device) => device.label.toLowerCase().contains('default'),
    );
    if (defaultByLabel != null) return defaultByLabel;

    // Priority 3: First device in the list
    return devices.first;
  }

  /// Refresh devices
  /// (useful when devices are connected/disconnected)
  Future<void> refreshDevices() async {
    await _loadDevices();
  }
}

// 2. The StateNotifier to manage the state.
class DeviceSelectionNotifier extends StateNotifier<DeviceSelectionState> {
  DeviceSelectionNotifier() : super(const DeviceSelectionState());

  // Getters for selected device IDs
  String? get selectedAudioInputDeviceId => state.audioInputDeviceId;
  String? get selectedAudioOutputDeviceId => state.audioOutputDeviceId;
  String? get selectedVideoInputDeviceId => state.videoInputDeviceId;
  bool get isAudioEnabledOnJoin => state.isAudioEnabledOnJoin;
  bool get isVideoEnabledOnJoin => state.isVideoEnabledOnJoin;

  void setAudioInputDevice(String? deviceId) {
    GSLogger.info("DeviceSelectionNotifier: Setting audio input to: $deviceId");
    state = state.copyWith(audioInputDeviceId: deviceId);
  }

  void setAudioOutputDevice(String? deviceId) {
    GSLogger.info(
        "DeviceSelectionNotifier: Setting audio output to: $deviceId");
    state = state.copyWith(audioOutputDeviceId: deviceId);
  }

  // Add this method for video input
  void setVideoInputDevice(String? deviceId) {
    GSLogger.info("DeviceSelectionNotifier: Setting video input to: $deviceId");
    state = state.copyWith(videoInputDeviceId: deviceId);
  }

  void setAudioEnabled(bool isEnabled) {
    GSLogger.info(
        "DeviceSelectionNotifier: Setting audio enabled to: $isEnabled");
    state = state.copyWith(isAudioEnabledOnJoin: isEnabled);
  }

  void setVideoEnabled(bool isEnabled) {
    GSLogger.info(
        "DeviceSelectionNotifier: Setting video enabled to: $isEnabled");
    state = state.copyWith(isVideoEnabledOnJoin: isEnabled);
  }

  void setAudioDevice(MediaDeviceInfo? device) {
    setAudioInputDevice(device?.deviceId);
  }

  void setVideoDevice(MediaDeviceInfo? device) {
    setVideoInputDevice(device?.deviceId);
  }

  void reset() {
    state = DeviceSelectionState();
  }
}

// 3. The final provider that the UI will interact with.
final deviceSelectionProvider =
    StateNotifierProvider<DeviceSelectionNotifier, DeviceSelectionState>(
  (ref) => DeviceSelectionNotifier(),
);

final isKeyboardVisibleProvider = StateProvider<bool>((ref) => false);

// Convenience providers for easy access to selected device IDs
final selectedAudioInputIdProvider = Provider<String?>((ref) {
  return ref.watch(deviceSelectionProvider).audioInputDeviceId;
});

final selectedAudioOutputIdProvider = Provider<String?>((ref) {
  return ref.watch(deviceSelectionProvider).audioOutputDeviceId;
});

final selectedVideoInputIdProvider = Provider<String?>((ref) {
  return ref.watch(deviceSelectionProvider).videoInputDeviceId;
});
