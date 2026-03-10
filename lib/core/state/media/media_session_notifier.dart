// The single, unified notifier.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:agora_demo/core/config/session_role_enum.dart';
import 'package:agora_demo/core/model/media_session_state.dart';
import 'package:agora_demo/core/screens/agora/agora_session_strategy.dart';
import 'package:agora_demo/core/screens/agora/media_session_strategy.dart';
import 'package:agora_demo/core/screens/classroom/media_session_events.dart';
import 'package:agora_demo/core/service/agora_server_service.dart';
import 'package:agora_demo/core/state/classroom/share_screen_provider.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final mediaSessionProvider =
    AsyncNotifierProvider<MediaSessionNotifier, MediaSessionState>(() {
  return MediaSessionNotifier();
});

// The MediaSessionNotifier has no idea how signaling happens;
// It just knows the WebRTCSessionStrategy or AgoraSessionStrategy needs it to work.

const _sessionInfoKey = 'active_session_info';

class MediaSessionNotifier extends AsyncNotifier<MediaSessionState> {
  AgoraSessionStrategy? activeStrategy;

  VideoViewController? _activeRemoteScreenShareController;

  StreamSubscription? _dataStreamSubscription;

  // We still store the context for reconnection.
  SessionRole _role = SessionRole.tutor;
  late String _ownSessionId;
  late String _peerSessionId;

  int _currentSessionEpoch = -1;

  // A timer to automatically clear the set after a timeout.
  Timer? _tutorRecoveryTimer;
  int _reconnectAttempts = 0;
  // Constants for fixed UIDs
  static const int TUTOR_UID = 1;
  static const int STUDENT_UID = 2;
  static const int _maxReconnectAttempts = 3;

  Completer<DateTime?>? _timestampCompleter;

  Timer? _heartbeatPingTimer;
  Timer? _heartbeatPongTimeoutTimer;
  bool _isReconnectProcedureRunning = false;
  bool _isLeavingSession = false;

  bool _isIntentionalStrategySwitch = false;
  bool _isStrategySwitchInProgress = false;

  @override
  Future<MediaSessionState> build() async {
    // When the notifier is built, it gets a reference to the signaling service.
    // 2. Set up its own cleanup logic.
    ref.onDispose(() {
      _tutorRecoveryTimer?.cancel();

      //activeStrategy?.dispose();
      GSLogger.log(
          "DEBUG: MediaSessionNotifier onDispose called, but strategy was NOT disposed.");
    });

    return const MediaSessionState();
  }

  /// The single entry point to start or restart a session.
  Future<void> initializeAndStartSession({
    required SessionRole role,
    String? selectedAudioDeviceId,
    String? selectedVideoDeviceId,
    List<dynamic> queuedMessages = const [],
    bool shouldInitiateOffer = false,
  }) async {
    
    state = const AsyncValue.loading();
    _isLeavingSession = false;
    _role = role;  // Important: Set the role so getAgoraUid() returns correct UID

    try {
      // 1. READ all necessary context from other providers.
      final selectedDevices = ref.read(deviceSelectionProvider);
      final screenShareNotifier = ref.read(screenShareProvider.notifier);

      // Strategy is Agora
      GSLogger.log("Initializing Agora Session...");

      // 1. Fetch the latest config directly. No caching.
      // This ensures we always get the valid daily token.
      // Generate unique channel name

      // Fetch token for this specific channel
      final agoraConfigService = AgoraConfigService();

      final agoraConfig = await agoraConfigService.fetchConfig();
      activeStrategy = AgoraSessionStrategy(
        appId: agoraConfig.appId,
        channelName: agoraConfig.channelId,
        role: role,
        ownUid: getAgoraUid(),
        peerUid: getPeerAgoraUid(),
        token: agoraConfig.token,
      );

      // 2. START the strategy (gets media, etc.)
      await activeStrategy!.startSession(onEvent: _handleMediaSessionEvent);

      // 5. UPDATE the final state to signal success.
      state = AsyncData(state.value!.copyWith(
        isSignalingConnected: true,
        localVideoView: activeStrategy!.localVideoView,
        remoteVideoView: activeStrategy!.remoteVideoView,
      ));
      // After the strategy is live and the UI state is updated,
      // we must start listening to its data stream for incoming events.
      _listenToDataChannel();

      // Apply Initial Device Selections.
      // For WebRTC, devices are passed via constructor and used in getUserMedia
      // For Agora, we need to apply them after the engine is initialized
      GSLogger.info("Agora: Applying initial device selections...");
      await Future.delayed(
          const Duration(milliseconds: 500)); // Let SDK stabilize
      await _applyInitialDeviceSelectionsInternal(selectedDevices);
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  /// Internal method to apply device selections (doesn't need WidgetRef)
  Future<void> _applyInitialDeviceSelectionsInternal(
      DeviceSelectionState deviceState) async {
    GSLogger.info("MediaSessionNotifier: Applying initial device selections");
    GSLogger.info("  Audio Input: ${deviceState.audioInputDeviceId}");
    GSLogger.info("  Audio Output: ${deviceState.audioOutputDeviceId}");
    GSLogger.info("  Video Input: ${deviceState.videoInputDeviceId}");

    try {
      if (deviceState.audioInputDeviceId != null &&
          deviceState.audioInputDeviceId!.isNotEmpty) {
        await setAudioInputDevice(deviceState.audioInputDeviceId!);
      }

      if (deviceState.audioOutputDeviceId != null &&
          deviceState.audioOutputDeviceId!.isNotEmpty) {
        await setAudioOutputDevice(deviceState.audioOutputDeviceId!);
      }

      if (deviceState.videoInputDeviceId != null &&
          deviceState.videoInputDeviceId!.isNotEmpty) {
        await setVideoInputDevice(deviceState.videoInputDeviceId!);
      }
      GSLogger.info(
          "MediaSessionNotifier: Device selections applied successfully");
    } catch (e) {
      GSLogger.error(
          "MediaSessionNotifier: Error applying device selections: $e");
    }
  }

  /// Switch audio input device in active session
  Future<void> setAudioInputDevice(String deviceId) async {
    GSLogger.info("MediaSessionNotifier: Setting audio input to: $deviceId");

    if (activeStrategy == null) {
      GSLogger.error("MediaSessionNotifier: No active strategy");
      return;
    }

    await activeStrategy!.setAudioInputDevice(deviceId);
  }

  /// Switch audio output device in active session
  Future<void> setAudioOutputDevice(String deviceId) async {
    GSLogger.info("MediaSessionNotifier: Setting audio output to: $deviceId");

    if (activeStrategy == null) {
      GSLogger.error("MediaSessionNotifier: No active strategy");
      return;
    }

    await activeStrategy!.setAudioOutputDevice(deviceId);
  }

  /// Switch video input device in active session
  Future<void> setVideoInputDevice(String deviceId) async {
    GSLogger.info("MediaSessionNotifier: Setting video input to: $deviceId");

    if (activeStrategy == null) {
      GSLogger.error("MediaSessionNotifier: No active strategy");
      return;
    }

    await activeStrategy!.setVideoInputDevice(deviceId);
  }

  // In your session setup code:
  int getAgoraUid() {
    return _role == SessionRole.tutor ? TUTOR_UID : STUDENT_UID;
  }

  int getPeerAgoraUid() {
    return _role == SessionRole.tutor ? STUDENT_UID : TUTOR_UID;
  }

  Future<void> disableMediaOnly() async {
    GSLogger.info("MediaSessionNotifier: disableMediaOnly");

    try {
      await activeStrategy?.disableMedia();

      final currentState = state.valueOrNull ?? MediaSessionState();
      state = AsyncData(currentState.copyWith(
        isLocalAudioEnabled: false,
        isLocalVideoEnabled: false,
        // Keep video views - don't set to null
      ));

      //_sendMediaStatusUpdate('audio', false);
      //_sendMediaStatusUpdate('video', false);

      GSLogger.info("MediaSessionNotifier: Media disabled");
    } catch (e) {
      GSLogger.error("MediaSessionNotifier: disableMediaOnly failed: $e");
    }
  }

  /// Called when teacher clicks "Enable Audio/Video"
  Future<void> enableMediaOnly() async {
    GSLogger.info("MediaSessionNotifier: enableMediaOnly");

    try {
      await activeStrategy?.enableMedia();

      final currentState = state.valueOrNull ?? MediaSessionState();
      state = AsyncData(currentState.copyWith(
        isLocalAudioEnabled: true,
        isLocalVideoEnabled: true,
        localVideoView: activeStrategy?.localVideoView,
        remoteVideoView: activeStrategy?.remoteVideoView,
      ));

      //_sendMediaStatusUpdate('audio', true);
      //_sendMediaStatusUpdate('video', true);

      GSLogger.info("MediaSessionNotifier: Media enabled");
    } catch (e) {
      GSLogger.error("MediaSessionNotifier: enableMediaOnly failed: $e");
    }
  }

  Future<void> leaveSession() async {
    GSLogger.info(
        "MediaSessionNotifier: Leaving session and cleaning up connections.");
    _isLeavingSession = true;

    try {
      final currentState = state.valueOrNull;
      if (currentState?.isDataConnectionActive == true &&
          activeStrategy != null) {
        GSLogger.info("Sending 'session_ended' signal to peer before leaving.");
        final payload = {'type': 'session_exited'};
        try {
          await activeStrategy!
              .sendUnreliableData(utf8.encode(jsonEncode(payload)));
          // Small delay to ensure message is sent
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          GSLogger.error("Failed to send session_exited signal: $e");
        }
      }

      // 2. Cancel data stream subscription
      _dataStreamSubscription?.cancel();
      _dataStreamSubscription = null;

      // 4. Dispose of the media strategy (closes PeerConnection, etc.)

      if (activeStrategy != null) {
        GSLogger.info("MediaSessionNotifier: calling activeStrategy!.dispose");
        await activeStrategy!.dispose();
        activeStrategy = null;
      }

      // Wait for Agora server to process
      await Future.delayed(const Duration(seconds: 2));

      // Reset strategy preference to default
      /*ref.read(sessionStrategyTypeProvider.notifier).state = 
          SessionStrategyType.webRTC;*/

      // 3. Reset this notifier's state to initial.
      state = AsyncData(MediaSessionState(callStatus: CallStatus.idle));
    } finally {
      // 5. Reset the flag after everything is done (optional, but safe).
      //    If this notifier is kept alive, we want it to be usable again.
      // Lets not reset here. Because of the async calls in the leaveSession
      //
      //_isLeavingSession = false;
    }
  }

  // The 'dispose' method clears the persisted session.
  Future<void> dispose() async {
    _dataStreamSubscription?.cancel();
    _dataStreamSubscription = null;

    await activeStrategy?.dispose();
    activeStrategy = null;
    // Reset to initial state
  }

  void initiateHandshake({bool addTracks = false}) {
    // Get the current state to update it immutably.
    final currentState = state.valueOrNull ?? const MediaSessionState();

    // 1. NOW is the correct time to set the flag.
    //    We update the state to reflect that the peer is present and ready.
    state = AsyncData(currentState.copyWith(
      isPeerPresentInRoom: true,
    ));

    // Call the internal method to create and send the offer.
    activeStrategy?.initiateHandshake(addTracks: addTracks);
  }

  void _handleMediaSessionEvent(MediaSessionEvent event) async {
    if (_isLeavingSession) {
      GSLogger.info(
          "Notifier: Ignoring ${event.runtimeType} during leaveSession.");
      return;
    }
    final currentState = state.valueOrNull ?? const MediaSessionState();
    
    GSLogger.info("MediaSessionNotifier: Received event ${event.runtimeType}");

    if (event is RemoteVideoReadyEvent) {
      // Remote video is ready - update the state with the new remote video view
      GSLogger.info("MediaSessionNotifier: Remote video is ready, updating state");
      state = AsyncData(currentState.copyWith(
        remoteVideoView: activeStrategy?.remoteVideoView,
      ));
    } else if (event is PeerReadyEvent) {
      // Peer has joined - update state
      GSLogger.info("MediaSessionNotifier: Peer is ready");
      state = AsyncData(currentState.copyWith(
        isPeerConnected: true,
        remoteVideoView: activeStrategy?.remoteVideoView,
      ));
    } else if (event is RemoteMediaStateChangedEvent) {
      GSLogger.info("MediaSessionNotifier: Remote ${event.mediaType} ${event.isEnabled ? 'enabled' : 'disabled'}");
      if (event.mediaType == 'video') {
        state = AsyncData(currentState.copyWith(
          isRemoteVideoEnabled: event.isEnabled,
          remoteVideoView: activeStrategy?.remoteVideoView,
        ));
      } else if (event.mediaType == 'audio') {
        state = AsyncData(currentState.copyWith(
          isRemoteAudioEnabled: event.isEnabled,
        ));
      }
    } else if (event is SignalingConnectedEvent) {
      GSLogger.info("MediaSessionNotifier: Signaling connected");
      state = AsyncData(currentState.copyWith(
        isSignalingConnected: true,
      ));
    } else if (event is ConnectionFailedEvent) {
      GSLogger.error("MediaSessionNotifier: Connection failed - ${event.reason}");
    } else if (event is LocalMediaUnavailableEvent) {
      GSLogger.warning("MediaSessionNotifier: Local media unavailable - ${event.reason}");
    }
  }

  /// Subscribes to the active strategy's data stream to handle incoming data.
  void _listenToDataChannel() {
    // Cancel any old subscription first

    GSLogger.log(">>>  _listenToDataChannel() ");

    _dataStreamSubscription?.cancel();

    if (activeStrategy == null) return;

    _dataStreamSubscription = activeStrategy!.dataStream.listen((data) {
      // This function is called for EVERY message that arrives.
      try {
        GSLogger.log(">>>  activeStrategy!.dataStream.listen() ");
      } catch (e) {
        GSLogger.info("_listenToDataChannel: $e");
        GSLogger.info("Error processing incoming data: $e");
      }
    });
  }

  // This is the public method called by the UI.
  Future<void> toggleLocalAudio() async {
    // Guard against no active strategy or state.
    if (activeStrategy == null || state.value == null) return;

    // 1. Determine the new status FIRST.
    final bool newStatus = !state.value!.isLocalAudioEnabled;

    // 2. Pass this explicit status to the strategy.
    // This works for BOTH WebRTC and Agora.
    await activeStrategy!.toggleLocalAudio(newStatus);

    // 3. Update UI state.
    state = AsyncData(state.value!.copyWith(
      isLocalAudioEnabled: newStatus,
    ));
  }

  Future<void> toggleLocalVideo() async {
    if (activeStrategy == null || state.value == null) return;

    // 1. Determine the new status FIRST.
    final bool newStatus = !state.value!.isLocalVideoEnabled;

    await activeStrategy!.toggleLocalVideo(newStatus);

    state = AsyncData(state.value!.copyWith(
      isLocalVideoEnabled: newStatus,
    ));
    //await _sendMediaStatusUpdate('video', newStatus);
  }

  Future<void> toggleRemoteAudio() async {}
  Future<void> toggleRemoteVideo() async {}

  Future<void> startScreenShare() async {
    GSLogger.info("MediaSessionNotifier: Starting screen share");
    final currentState = state.valueOrNull ?? MediaSessionState();

    // We also check if the data connection is active.
    if (currentState?.isDataConnectionActive != true) {
      GSLogger.log("Cannot start screen share, data channel is not open.");
      // Optionally show a user-facing error here.
      return;
    }

    GSLogger.log(
        "Notifier: Delegating startScreenShare to the active strategy.");

    try {
      // Agora screen share
      try {
        await activeStrategy?.startScreenShare();

        // Update state to reflect sharing
        state = AsyncData(currentState.copyWith(
          isLocalUserSharingScreen: true,
        ));
      } catch (e) {
        GSLogger.error("Error starting Agora screen share: $e");
      }
    } catch (e) {
      GSLogger.error("MediaSessionNotifier: Error starting screen share: $e");
      ref.read(screenShareProvider.notifier).setSharing(false);
      rethrow;
    }
  }

  Future<void> stopScreenShare() async {
    if (activeStrategy == null) {
      GSLogger.log("Cannot stop screen share, no active strategy.");
      return;
    }
    final currentState = state.valueOrNull ?? MediaSessionState();

    // Agora screen share
    try {
      await activeStrategy?.stopScreenShare();

      // Update state to reflect not sharing
      state = AsyncData(currentState.copyWith(
        isLocalUserSharingScreen: false,
      ));
    } catch (e) {
      GSLogger.error("Error stopping Agora screen share: $e");
    } finally {
      // 4. ALWAYS disconnect from the temporary signaling connection.
      //await signalingNotifier.closeTemporaryConnection();
    }
  }

  Future<void> startSessionWithoutAudio() async {
    GSLogger.log("Notifier: Starting session WITHOUT audio/video.");

    // 1. Send Signal
    final payload = {'type': 'start_session_no_media'};
    await activeStrategy?.sendUnreliableData(utf8.encode(jsonEncode(payload)));

    // 2. Update Local State
    state = AsyncData(state.value!.copyWith(
      //callStatus: CallStatus.activeNoMedia,
      // Ensure media flags are off
      isLocalAudioEnabled: false,
      isLocalVideoEnabled: false,
      isRemoteAudioEnabled: false,
      isRemoteVideoEnabled: false,
    ));

    // 3. Stop Tracks (Fire and Forget or Await if safe)
    // We don't await because we want the UI to update immediately.
    //activeStrategy?.endCall();
  }

  /// Generates a unique channel name for a tutor-student session
  String generateChannelName({
    required String tutorId,
    required String studentId,
  }) {
    // Create unique channel name
    // Format: tutorId-studentId
    return '$tutorId-$studentId';
  }
}
/// Tracks whether the local user has dismissed the screen share dialog.
  final isScreenShareDialogDismissedProvider = StateProvider<bool>((ref) {
    // By default, the dialog is not dismissed.
    return false;
  });