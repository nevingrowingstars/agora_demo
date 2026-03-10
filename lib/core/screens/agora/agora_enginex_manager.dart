import 'dart:async';
import 'dart:typed_data';

import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Manages Agora RtcEngineEx for multi-connection support (camera + screen share).
///
/// Architecture:
/// - One RtcEngineEx instance
/// - Two joinChannelEx connections:
///   1. Camera connection (main video/audio)
///   2. Screen share connection (joins upfront, publishes on demand)
///
class AgoraEngineXManager {
  // Singleton instance
  static AgoraEngineXManager? _instance;
  static AgoraEngineXManager get instance =>
      _instance ??= AgoraEngineXManager._();

  AgoraEngineXManager._();

  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  bool _isInitialized = false;
  String? _currentAppId;
  RtcEngineEventHandler? _currentEventHandler;

  // Connection tracking
  String? _currentChannelName;
  RtcConnection? _cameraConnection;
  RtcConnection? _screenShareConnection;
  int? _assignedCameraUid;
  int? _screenShareUid;
  bool _isScreenSharing = false;
  String? _screenShareToken;

  // Getters
  bool get isInitialized => _isInitialized;
  String? get currentChannelName => _currentChannelName;
  RtcConnection? get cameraConnection => _cameraConnection;
  RtcConnection? get screenShareConnection => _screenShareConnection;
  int? get assignedCameraUid => _assignedCameraUid;
  int? get screenShareUid => _screenShareUid;
  bool get isScreenSharing => _isScreenSharing;

  /// Initialize engine (called once, lazy)
  Future<void> ensureInitialized(String appId) async {
    // If already initialized with same appId, skip
    if (_isInitialized && _engine != null && _currentAppId == appId) {
      GSLogger.info("AgoraEngineManager: Engine already initialized");
      return;
    }

    // If initialized with different appId, dispose first
    if (_isInitialized && _currentAppId != appId) {
      GSLogger.info("AgoraEngineManager: AppId changed, reinitializing...");
      await dispose();
    }

    GSLogger.info("AgoraEngineManager: Initializing engine...");

    // Retry mechanism for web platform where Iris SDK may not be ready immediately
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _engine = createAgoraRtcEngine();
        break; // Success, exit retry loop
      } catch (e) {
        if (attempt < maxRetries) {
          GSLogger.warning("AgoraEngineManager: createAgoraRtcEngine attempt $attempt failed, retrying...");
          await Future.delayed(retryDelay);
        } else {
          GSLogger.error("AgoraEngineManager: createAgoraRtcEngine failed after $maxRetries attempts: $e");
          rethrow;
        }
      }
    }

    try {

      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      await _engine!.enableVideo();
      await _engine!.enableAudio();
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Suppress verbose logs
      await _engine!.setLogLevel(LogLevel.logLevelError);
      await _engine!.setParameters('{"rtc.log_filter":0}');

      //await _engine!.setDefaultAudioRouteToSpeakerphone(true);
      //await _engine!.setEnableSpeakerphone(true);

      _currentAppId = appId;
      _isInitialized = true;

      GSLogger.info("AgoraEngineManager: Engine initialized successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineManager: Initialization failed: $e");
      _engine = null;
      _isInitialized = false;
      rethrow;
    }
  }

  /// Register event handler for current session
  void registerEventHandler(RtcEngineEventHandler handler) {
    if (_engine == null) {
      GSLogger.error(
          "AgoraEngineManager: Cannot register handler, engine is null");
      return;
    }

    // Unregister previous handler first
    if (_currentEventHandler != null) {
      GSLogger.info("AgoraEngineManager: Unregistering previous event handler");
      _engine!.unregisterEventHandler(_currentEventHandler!);
    }

    _currentEventHandler = handler;
    _engine!.registerEventHandler(handler);
    GSLogger.info("AgoraEngineManager: Event handler registered");
  }

  /// Unregister current event handler
  void unregisterEventHandler() {
    if (_currentEventHandler != null && _engine != null) {
      _engine!.unregisterEventHandler(_currentEventHandler!);
      _currentEventHandler = null;
      GSLogger.info("AgoraEngineManager: Event handler unregistered");
    }
  }

  /// Set audio input device (microphone)
  Future<void> setAudioInputDevice(String deviceId) async {
    if (_engine == null) {
      GSLogger.error(
          "AgoraEngineXManager: Cannot set audio input - engine is null");
      return;
    }

    try {
      GSLogger.info("AgoraEngineXManager: Switching audio input to: $deviceId");
      final deviceManager = await _engine!.getAudioDeviceManager();
      await deviceManager.followSystemRecordingDevice(false);
      await deviceManager.setRecordingDevice(deviceId);
      GSLogger.info("AgoraEngineXManager: Audio input switched successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error switching audio input: $e");
    }
  }

  /// Set audio output device (speaker)
  /// Set audio output device (speaker)
  Future<void> setAudioOutputDevice(String deviceId) async {
    if (_engine == null) {
      GSLogger.error(
          "AgoraEngineXManager: Cannot set audio output - engine is null");
      return;
    }

    try {
      GSLogger.info(
          "AgoraEngineXManager: Switching audio output to: $deviceId");

      final deviceManager = await _engine!.getAudioDeviceManager();
      await deviceManager.followSystemPlaybackDevice(false);

      // Log current device before change
      try {
        final currentDevice = await deviceManager.getPlaybackDevice();
        GSLogger.info(
            "AgoraEngineXManager: Current playback device: $currentDevice");
      } catch (e) {
        GSLogger.warning(
            "AgoraEngineXManager: Could not get current device: $e");
      }

      // Try to set the device
      await deviceManager.setPlaybackDevice(deviceId);

      // Verify the change
      try {
        final newDevice = await deviceManager.getPlaybackDevice();
        GSLogger.info(
            "AgoraEngineXManager: Playback device after change: $newDevice");

        if (newDevice != deviceId) {
          GSLogger.warning(
              "AgoraEngineXManager: Device ID mismatch! Expected: $deviceId, Got: $newDevice");
        }
      } catch (e) {
        GSLogger.warning(
            "AgoraEngineXManager: Could not verify device change: $e");
      }

      GSLogger.info("AgoraEngineXManager: Audio output switched successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error switching audio output: $e");
    }
  }

  /// Set video input device (camera)
  Future<void> setVideoInputDevice(String deviceId) async {
    if (_engine == null) {
      GSLogger.error(
          "AgoraEngineXManager: Cannot set video input - engine is null");
      return;
    }

    try {
      GSLogger.info("AgoraEngineXManager: Switching video input to: $deviceId");
      final deviceManager = await _engine!.getVideoDeviceManager();
      await deviceManager.setDevice(deviceId);
      GSLogger.info("AgoraEngineXManager: Video input switched successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error switching video input: $e");
    }
  }

  /// Start local preview
  Future<void> startPreview() async {
    if (_engine == null) return;
    await _engine!.startPreview();
  }

  /// Stop local preview
  Future<void> stopPreview() async {
    if (_engine == null) return;
    await _engine!.stopPreview();
  }

  /// Join a channel
  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int cameraUid,
    required int screenShareUid,
    String? screenShareToken,
    bool publishMedia = false, 
  }) async {
    if (_engine == null) {
      throw Exception("AgoraEngineManager: Engine not initialized");
    }

    GSLogger.info("AgoraEngineXManager: Joining channel: $channelName");
    GSLogger.info(
        "  Camera UID: $cameraUid, Screen Share UID: $screenShareUid");
    GSLogger.info("  publishMedia: $publishMedia"); 

    _currentChannelName = channelName;
    _screenShareUid = screenShareUid;
    _screenShareToken = screenShareToken ?? token;

    // 1. Join with Camera UID (main connection)
    _cameraConnection = RtcConnection(
      channelId: channelName,
      localUid: cameraUid,
    );

    try {
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: cameraUid,
        options:  ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          // on't publish media tracks initially
          // This prevents Agora from trying to create mic/camera tracks
          publishCameraTrack: publishMedia,
          publishMicrophoneTrack: publishMedia,
          autoSubscribeVideo: true,
          autoSubscribeAudio: true,
        ),
      );
      GSLogger.info("AgoraEngineXManager: joinChannel successful");

    } catch (e) {
      GSLogger.error("AgoraEngineXManager: joinChannel failed: $e");
      rethrow;
    }
  }

  /// Called from onJoinChannelSuccess to store assigned camera UID
  void onCameraJoinSuccess(RtcConnection connection) {
    GSLogger.info(
        "AgoraEngineXManager: Camera join success - assigned UID: $connection.localUid");
    // Update camera connection with the actual assigned UID
    _cameraConnection = connection;
    _assignedCameraUid = connection.localUid;
  }

  /// Start screen share - starts capture and updates connection to publish
  Future<void> startScreenShare() async {
    if (_engine == null || _currentChannelName == null) {
      GSLogger.error(
          "AgoraEngineXManager: Cannot start screen share - not ready");
      throw Exception("Engine or screen share connection not ready");
    }

    if (_isScreenSharing) {
      GSLogger.info("AgoraEngineXManager: Already sharing screen");
      return;
    }

    GSLogger.info("AgoraEngineXManager: Starting screen share...");


    try {

      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 1280, height: 720),
          frameRate: 15,
          bitrate: 0, // Auto
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainQuality,
        ),
      );

      // 1. Start screen capture
      await _engine!.startScreenCapture(
        const ScreenCaptureParameters2(
          captureAudio: true,
          captureVideo: true,
          videoParams: ScreenVideoParameters(
            dimensions:  VideoDimensions(width: 1280, height: 720),
            frameRate: 15,
            bitrate: 1500,
            contentHint: VideoContentHint.contentHintDetails,
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      _screenShareConnection = RtcConnection(
        channelId: _currentChannelName!,
        localUid: _screenShareUid!,
      );

      // 2. Cast to RtcEngineEx for joinChannelEx
      final engineEx = _engine as RtcEngineEx;

      _screenShareConnection = RtcConnection(
        channelId: _currentChannelName!,
        localUid: _screenShareUid!,
      );

      await engineEx.joinChannelEx(
        token: _screenShareToken ?? '',
        connection: _screenShareConnection!,
        options: const ChannelMediaOptions(
          autoSubscribeVideo: false,
          autoSubscribeAudio: false,
          publishScreenTrack: true,
          publishScreenCaptureVideo: true,
          publishScreenCaptureAudio: true,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      _isScreenSharing = true;

      GSLogger.info("AgoraEngineXManager: Screen share started successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error starting screen share: $e");
      _isScreenSharing = false;
      rethrow;
    }
  }

  /// Stop screen share - stops capture and updates connection to stop publishing
  Future<void> stopScreenShare() async {
    if (_engine == null) {
      GSLogger.info("AgoraEngineXManager: Engine is null, nothing to stop");
      return;
    }

    if (!_isScreenSharing) {
      GSLogger.info("AgoraEngineXManager: Not sharing screen");
      return;
    }

    GSLogger.info("AgoraEngineXManager: Stopping screen share...");

    try {
      // 1. Stop screen capture
      await _engine!.stopScreenCapture();

      // 2. Leave screen share connection
      if (_screenShareConnection != null) {
        final engineEx = _engine as RtcEngineEx;
        await engineEx.leaveChannelEx(connection: _screenShareConnection!);
        _screenShareConnection = null;
      }
      _isScreenSharing = false;
      // 3. Re-enable camera/mic publishing on main channel
      await Future.delayed(const Duration(milliseconds: 300));

      await _engine!.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ));

      GSLogger.info("AgoraEngineXManager: Re-enabled camera/mic publishing");
      GSLogger.info("AgoraEngineXManager: Screen share stopped");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error stopping screen share: $e");
      _isScreenSharing = false;
    }
  }

  /// Leave channel (both connections)
  Future<void> leaveChannel() async {
    if (_engine == null) {
      GSLogger.info("AgoraEngineXManager: Engine is null, nothing to leave");
      return;
    }

    GSLogger.info("AgoraEngineXManager: Leaving channel...");

    try {
      // Stop screen share first if active
      if (_isScreenSharing) {
        await stopScreenShare();
      }

      await _engine!.leaveChannel();
      await _engine!.stopPreview();

      _currentChannelName = null;
      _assignedCameraUid = null;
      _screenShareUid = null;
      _screenShareToken = null;
      _screenShareConnection = null;
      _isScreenSharing = false;

      GSLogger.info("AgoraEngineXManager: Left channel successfully");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error leaving channel: $e");
      _currentChannelName = null;
      _assignedCameraUid = null;
      _screenShareUid = null;
      _screenShareToken = null;
      _screenShareConnection = null;
    }
  }

  /// Create a data stream (uses camera connection)
  Future<int> createDataStream({
    bool ordered = true,
    bool syncWithAudio = false,
  }) async {
    if (_engine == null) {
      throw Exception("AgoraEngineXManager: Engine not initialized");
    }

    GSLogger.info("AgoraEngineXManager: Creating data stream...");

    final config =
        DataStreamConfig(ordered: ordered, syncWithAudio: syncWithAudio);
    final streamId = await _engine!.createDataStream(config);

    GSLogger.info(
        "AgoraEngineXManager: Data stream created with ID: $streamId");
    return streamId;
  }

  /// Send stream message (uses camera connection)
  Future<void> sendStreamMessage({
    required int streamId,
    required Uint8List data,
  }) async {
    if (_engine == null) {
      GSLogger.info("AgoraEngineXManager: Cannot send message - not ready");
      return;
    }

    await _engine!
        .sendStreamMessage(streamId: streamId, data: data, length: data.length);
  }

  /// Update camera connection media options
  Future<void> updateCameraMediaOptions(ChannelMediaOptions options) async {
    if (_engine == null || _cameraConnection == null) return;

    await _engine!.updateChannelMediaOptions(options);
  }

  /// Mute/unmute local video (camera connection)
  Future<void> muteLocalVideoStream(bool mute) async {
    if (_engine == null || _cameraConnection == null) return;

    await _engine!.muteLocalVideoStream(mute);
  }

  /// Mute/unmute local audio (camera connection)
  Future<void> muteLocalAudioStream(bool mute) async {
    if (_engine == null || _cameraConnection == null) return;
    await _engine!.muteLocalAudioStream(mute);
  }

  /// Dispose engine completely (call only at app shutdown or logout)
  Future<void> dispose() async {
    GSLogger.info("AgoraEngineXManager: Disposing engine...");

    try {
      await leaveChannel();
      unregisterEventHandler();

      if (_engine != null) {
        await _engine!.release();
        _engine = null;
      }

      _isInitialized = false;
      _currentAppId = null;
      _isScreenSharing = false;
      _instance = null;

      GSLogger.info("AgoraEngineXManager: Engine disposed completely");
    } catch (e) {
      GSLogger.error("AgoraEngineXManager: Error disposing engine: $e");
      _engine = null;
      _isInitialized = false;
      _currentAppId = null;
      _isScreenSharing = false;
    }
  }
}
