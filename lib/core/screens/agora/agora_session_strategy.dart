import 'dart:async';
import 'dart:convert';

import 'package:agora_demo/core/channel/reliable_data_channel.dart';
import 'package:agora_demo/core/config/session_role_enum.dart';
import 'package:agora_demo/core/screens/agora/agora_enginex_manager.dart';
import 'package:agora_demo/core/screens/agora/media_session_strategy.dart';
import 'package:agora_demo/core/screens/classroom/media_session_events.dart';
import 'package:agora_demo/core/state/media/signaling_event.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

//import 'package:growingstars_whiteboard/config/channel/agora_engine_manger.dart';

const int TUTOR_UID = 1;
const int STUDENT_UID = 2;
const int TUTOR_SCREEN_SHARE_UID = 1001;
const int STUDENT_SCREEN_SHARE_UID = 1002;

class AgoraSessionStrategy implements MediaSessionStrategy {
  /// Your unique App ID from the Agora developer console.
  final String appId;

  /// The name of the channel (room) to join. Must be the same for both users.
  final String channelName;

  final SessionRole role;

  /// The unique *integer* ID for the local user in the channel.
  final int ownUid;

  final int peerUidInt;

  /// An optional, temporary token for joining the channel (for production).
  final String? token;

  // Use the singleton engine manager
  //final AgoraEngineManager _engineManager = AgoraEngineManager.instance;
  final AgoraEngineXManager _engineManager = AgoraEngineXManager.instance;

  // Session state
  bool _isSessionActive = false;

  int? _remoteUid;

  int? _assignedLocalUid;

  int? _confirmedPeerUid;

  String _currentSessionId = '';

  // --- Controllers are now nullable and will be created later ---
  // --- A dedicated controller for the remote screen share stream ---
  VideoViewController? _localViewController;
  VideoViewController? _screenShareViewController;
  VideoViewController? _cachedRemoteController;
  int? _cachedRemoteUid;

  // Device selection storage
  String? selectedAudioInputDeviceId;
  String? selectedAudioOutputDeviceId;
  String? selectedVideoInputDeviceId;

  /// Creates an Agora session strategy.
  ///
  /// Requires an [appId], a [channelName] to join, and a unique integer [ownUid].
  /// A [token] is optional but highly recommended for production environments.

  final int _sessionEpoch;
  static int _nextEpoch = 0;

  AgoraSessionStrategy({
    required this.appId,
    required this.channelName,
    required this.role,
    required int ownUid,
    required int peerUid,
    this.token,
  })  : ownUid = ownUid,
        peerUidInt = peerUid,
        _sessionEpoch = _nextEpoch++;

  // Internal State
  Function(MediaSessionEvent event)? _onEventCallback;

  // Change from final to late
  late StreamController<Uint8List> _dataStreamController;
  late Completer<void> _sessionReadyCompleter;

  ReliableDataChannel? _reliableChannel;
  int? _dataStreamId;
  RtcEngineEventHandler? _rtcEngineEventHandler;
  RtcConnection? _remoteConnection;
  RtcConnection? _screenShareConnection;
  int? _screenShareLocalUid;

  // A new flag to track the state internally
  bool _isSharingScreen = false;
  // In AgoraSessionStrategy class fields
  int? _remoteScreenShareUid;
  bool _isRemoteSharingScreen = false;

  bool _isReconnecting = false;

  // Computed property for peer's screen share UID
  int get screenShareUid {
    return role == SessionRole.tutor
        ? STUDENT_SCREEN_SHARE_UID // 1002
        : TUTOR_SCREEN_SHARE_UID; // 1001
  }

  // Your OWN screen share UID (for when YOU share screen)
  int get ownScreenShareUid {
    return role == SessionRole.tutor
        ? TUTOR_SCREEN_SHARE_UID // 1001
        : STUDENT_SCREEN_SHARE_UID; // 1002
  }

  @override
  Widget get localVideoView {
    GSLogger.info("localVideoView getter called");

    if (_engineManager.engine != null && _localViewController != null) {
      return SizedBox.expand(
        key: const ValueKey('local_video'),
        child: AgoraVideoView(
          controller: _localViewController!,
        ),
      );
    } else {
      return const ColoredBox(color: Colors.black);
    }
  }

  @override
  Widget get remoteVideoView {
    GSLogger.info(
        "remoteVideoView called - remoteUid: $_remoteUid, confirmed: $_confirmedPeerUid, cached: $_cachedRemoteUid, hasController: ${_cachedRemoteController != null}");

    final uid = _confirmedPeerUid ?? _remoteUid;

    if (uid == null || _engineManager.engine == null) {
      GSLogger.info(
          "remoteVideoView: No remoteUid or engine, returning placeholder");
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child: Text('Waiting...', style: TextStyle(color: Colors.white))),
      );
    }

    GSLogger.info(
        "Creating remote view for UID: $uid on channel: $channelName");
    // Always create fresh controller if UID changed or controller is null
    if (_cachedRemoteController == null || _cachedRemoteUid != uid) {
      GSLogger.info(
          "Creating FRESH remote controller for UID: $uid on channel: $channelName");

      _cachedRemoteController = VideoViewController.remote(
        rtcEngine: _engineManager.engine!,
        canvas: VideoCanvas(
          uid: uid,
          renderMode: RenderModeType.renderModeFit,
        ),
        connection: RtcConnection(channelId: channelName),
        useFlutterTexture: true,
      );
      _cachedRemoteUid = uid;
    }
    // Use key to force rebuild when UID changes, wrap in SizedBox.expand for proper sizing
    return SizedBox.expand(
      key: ValueKey('remote_video_$uid'),
      child: AgoraVideoView(controller: _cachedRemoteController!),
    );
  }

  @override
  Widget? get remoteScreenShareView {
    final uid = _remoteScreenShareUid;
    final engine = _engineManager.engine;

    GSLogger.info(
        "remoteScreenShareView called - uid: $uid, isRemoteSharing: $_isRemoteSharingScreen");

    if (uid == null || engine == null || !_isRemoteSharingScreen) {
      GSLogger.info("remoteScreenShareView: No screen share active");
      return null;
    }

    GSLogger.info("Creating remote screen share view for UID: $uid");

    return AgoraVideoView(
      key: ValueKey('screen_share_$uid'),
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: channelName),
      ),
    );
  }

  @override
  Stream<Uint8List> get dataStream => _dataStreamController.stream;

  @override
  Future<void> startSession(
      {required Function(MediaSessionEvent event) onEvent}) async {
    _isSessionActive = true;
    _onEventCallback = onEvent;

    // RESET ALL STATE at the start of a new session
    _remoteUid = null;
    _confirmedPeerUid = null;
    _cachedRemoteController = null;
    _cachedRemoteUid = null;
    _remoteConnection = null;
    _assignedLocalUid = null;
    _localViewController = null;
    _dataStreamId = null;
    _reliableChannel = null;

    // Create new stream controller and completer
    _dataStreamController = StreamController<Uint8List>.broadcast();
    _sessionReadyCompleter = Completer<void>();

    _currentSessionId = const Uuid().v4();
    GSLogger.info(
        "AgoraStrategy: Starting session $_currentSessionId on channel: $channelName");
    GSLogger.info(
        "AgoraStrategy: _isSessionActive = $_isSessionActive"); // ← Debug log

    try {
      // 1. Ensure engine is initialized
      await _engineManager.ensureInitialized(appId);

      // Apply selected devices AFTER engine init, BEFORE joining channel
      await _applySelectedDevices();

      _rtcEngineEventHandler = _createRtcEventHandlers(onEvent);

      _engineManager.registerEventHandler(_rtcEngineEventHandler!);

      bool mediaEnabled = false;

      try {
        // 3. Create local view controller
        _localViewController = VideoViewController(
          rtcEngine: _engineManager.engine!,
          canvas: const VideoCanvas(
            uid: 0,
            renderMode: RenderModeType.renderModeFit,
          ),
          useFlutterTexture: true,
        );

        // Ensure video is enabled at engine level (for both local and remote)
        await _engineManager.engine?.enableVideo();
        await _engineManager.engine?.enableAudio();

        // 4. Start preview
        await _engineManager.startPreview();

        mediaEnabled = true;
        GSLogger.info("AgoraStrategy: Media enabled successfully");

      } catch (e) {
        // CATCH permission denied and continue without media
        GSLogger.warning("AgoraStrategy: Could not enable media: $e");
        GSLogger.info("AgoraStrategy: Continuing in data-channel-only mode");

        // Notify UI about no-media mode
        _onEventCallback
            ?.call(LocalMediaUnavailableEvent(reason: e.toString()));
      }
      // ALWAYS join channel (data channel works without media)
      // 5. Join channel - this will work even without media permission

      // ALWAYS join channel (data channel works without media)
      // This should NOT throw now because publishCameraTrack/publishMicrophoneTrack are false
      try {
        await _engineManager.joinChannel(
          token: token!,
          channelName: channelName,
          cameraUid: ownUid, // Let Agora assign
          screenShareUid: ownScreenShareUid, 
          screenShareToken: token,
          publishMedia: mediaEnabled, 
        );

        GSLogger.info(
            "AgoraStrategy: joinChannel called (mediaEnabled: $mediaEnabled)");
      } catch (joinError) {
        // Also catch joinChannel errors
        GSLogger.error("AgoraStrategy: joinChannel failed: $joinError");
        GSLogger.info("AgoraStrategy: Session failed to start");

        _isSessionActive = false;
        await dispose();
        rethrow;
      }

    } catch (e) {
      GSLogger.info("AgoraSessionStrategy failed to start: $e");
      _isSessionActive = false;
      await dispose();
      rethrow;
    }
    return _sessionReadyCompleter.future;
  }

  @override
  Future<void> setAudioInputDevice(String deviceId) async {
    GSLogger.info(
        "AgoraSessionStrategy: Setting audio input device: $deviceId");
    selectedAudioInputDeviceId = deviceId;
    await _engineManager.setAudioInputDevice(deviceId);
  }

  @override
  Future<void> setAudioOutputDevice(String deviceId) async {
    GSLogger.info(
        "AgoraSessionStrategy: Setting audio output device: $deviceId");
    // Store the device ID
    selectedAudioOutputDeviceId = deviceId;
    await _engineManager.setAudioOutputDevice(deviceId);
  }

  @override
  Future<void> setVideoInputDevice(String deviceId) async {
    GSLogger.info(
        "AgoraSessionStrategy: Setting video input device: $deviceId");
    selectedVideoInputDeviceId = deviceId;
    await _engineManager.setVideoInputDevice(deviceId);
  }

  void _handleLocalScreenShareStopped() {
    if (!_isSharingScreen) {
      GSLogger.info("Agora: Not sharing, ignoring browser stop");
      return;
    }

    GSLogger.info("Agora: Handling local screen share stopped");

    _isSharingScreen = false;
    _screenShareLocalUid = null;

    // Stop and cleanup screen share engine properly
    // Clean up via engine manager
    _engineManager.stopScreenShare().then((_) {
      GSLogger.info("Agora: Engine stopScreenShare completed");
    }).catchError((e) {
      GSLogger.error("Agora: Error in stopScreenShare: $e");
    });

    // Notify peer
    _sendScreenShareSignal(false);

    // Fire event to update local UI
    _onEventCallback?.call(LocalScreenShareStoppedEvent());
  }

  RtcEngineEventHandler _createRtcEventHandlers(
      Function(MediaSessionEvent event) onEvent) {
    return RtcEngineEventHandler(
      // --- onJoinChannelSuccess ---
      onJoinChannelSuccess: (connection, elapsed) {
        if (!_isSessionActive) {
          GSLogger.info(
              '[Agora] Ignoring onJoinChannelSuccess - session not active');
          return;
        }

        GSLogger.info(
            '[Agora] onJoinChannelSuccess: Local user ${connection.localUid} joined channel ${connection.channelId}');
        _assignedLocalUid = connection.localUid;

        _engineManager.onCameraJoinSuccess(connection);

        _onEventCallback?.call(SignalingConnectedEvent());

        // Create data stream
        _engineManager.createDataStream().then((streamId) {
          if (!_isSessionActive) return;

          _dataStreamId = streamId;
          _reliableChannel = ReliableDataChannel(
            maxChunkSize: 500,
            delayBetweenChunks: const Duration(milliseconds: 200),
            sendRawDataCallback: (rawData) async {
              if (_dataStreamId != null && _isSessionActive) {
                await _engineManager.sendStreamMessage(
                  streamId: _dataStreamId!,
                  data: rawData,
                );
              }
            },
            onDataReceivedCallback: (payload) {
              if (_isSessionActive && !_dataStreamController.isClosed) {
                _dataStreamController.add(payload);
              }
            },
          );

          if (!_sessionReadyCompleter.isCompleted) {
            _sessionReadyCompleter.complete();
          }
        }).catchError((e) {
          if (!_sessionReadyCompleter.isCompleted) {
            _sessionReadyCompleter.completeError(e);
          }
        });
      },

      // --- onStreamMessage ---
      onStreamMessage: (RtcConnection connection, int remoteUid, int streamId,
          Uint8List data, int length, int sentTs) {
        if (!_isSessionActive) return;

        try {
          final messageString = utf8.decode(data);
          final payload = jsonDecode(messageString) as Map<String, dynamic>;
          final String? type = payload['type'];

          const reliableProtocolTypes = {'data', 'ack', 'nack', 'batch'};

          if (type != null && reliableProtocolTypes.contains(type)) {
            _reliableChannel?.handleRawData(data);
          } else if (type == 'screenShareStarted') {
            GSLogger.info(
                "Agora: Received 'screenShareStarted' signal from peer.");
            final screenShareUid = payload['screenShareUid'] as int?;
            GSLogger.info("Agora: Peer's screenShareUid: $screenShareUid");
            _handleRemoteScreenShareStarted(
                signalScreenShareUid: screenShareUid);
          } else if (type == 'screenShareStopped') {
            GSLogger.info(
                "Agora: Received 'screenShareStopped' signal from peer.");
            // The remote video view will switch back to camera
            // Fire event to hide overlay on our side
            _handleRemoteScreenShareStopped();
          } else {
            if (!_dataStreamController.isClosed) {
              _dataStreamController.add(data);
            }
          }
        } catch (e) {
          GSLogger.log("Error routing Agora message: $e");
        }
      },

      // --- onRemoteVideoStateChanged ---
      onRemoteVideoStateChanged: (RtcConnection connection, int remoteUid,
          RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
        GSLogger.info('[Agora onRemoteVideoStateChanged]');
        GSLogger.info('  remoteUid: $remoteUid');
        GSLogger.info('  state: $state');
        GSLogger.info('  reason: $reason');
        GSLogger.info('  screenShareUid: $screenShareUid');
        GSLogger.info('  _isRemoteSharingScreen: $_isRemoteSharingScreen');

        // === GUARD: Session must be active ===
        if (!_isSessionActive) {
          GSLogger.info('[Agora] Ignoring - session not active');
          return;
        }

        // === FILTER 1: Skip OWN screen share UID ===
        if (remoteUid == ownScreenShareUid) {
          GSLogger.info('[Agora] Ignoring own screen share video state');
          return;
        }

        // === FILTER 2: Skip OWN camera UID ===
        if (remoteUid == _assignedLocalUid || remoteUid == ownUid) {
          GSLogger.info('[Agora] Ignoring own video state');
          return;
        }

        // === FILTER 3: Only accept expected UIDs ===
        // Accept: peer's camera UID (peerUidInt) OR peer's screen share UID (screenShareUid)
        if (remoteUid != peerUidInt && remoteUid != screenShareUid) {
          GSLogger.info('[Agora] Ignoring unexpected UID: $remoteUid');
          return;
        }

        // === HANDLE VIDEO STATE CHANGES ===

        // --- VIDEO ACTIVE (Decoding) - This is when video is actually ready ---
        if (state == RemoteVideoState.remoteVideoStateDecoding) {
          // Handle PEER'S SCREEN SHARE becoming active
          if (remoteUid == screenShareUid) {
            GSLogger.info('[Agora] Peer screen share video DECODING: $remoteUid');
            return;
          }
          
          // Handle PEER'S CAMERA becoming active
          if (_isRemoteSharingScreen) {
            GSLogger.info(
                '[Agora] Remote is sharing screen. Ignoring camera video event.');
            return;
          }

          GSLogger.info('[Agora] Remote video DECODING for UID: $remoteUid');

          // Force new controller creation since video is now actually decoding
          _cachedRemoteController = null;
          _cachedRemoteUid = null;

          // Confirm peer if not already confirmed
          if (_confirmedPeerUid == null && remoteUid == peerUidInt) {
            GSLogger.info(
                '[Agora] *** CONFIRMED PEER WITH DECODING VIDEO: $remoteUid ***');
            _confirmedPeerUid = remoteUid;
            _remoteUid = remoteUid;
            _remoteConnection = connection;
            _onEventCallback?.call(PeerReadyEvent());
          }

          _onEventCallback?.call(RemoteMediaStateChangedEvent(
            mediaType: 'video',
            isEnabled: true,
          ));
          _onEventCallback?.call(RemoteVideoReadyEvent());
          return;
        }

        // --- VIDEO STARTING (not yet ready, just informational) ---
        if (state == RemoteVideoState.remoteVideoStateStarting) {
          // On web platform, video may stay at STARTING state with RemoteUnmuted reason
          // when the track is actually available. Handle this case.
          if (reason == RemoteVideoStateReason.remoteVideoStateReasonRemoteUnmuted) {
            GSLogger.info('[Agora] Remote video STARTING with UNMUTED for UID: $remoteUid - treating as ready');
            
            if (remoteUid == screenShareUid) {
              GSLogger.info('[Agora] Screen share video ready: $remoteUid');
              return;
            }
            
            if (_isRemoteSharingScreen) {
              return;
            }

            // Force new controller creation
            _cachedRemoteController = null;
            _cachedRemoteUid = null;

            // Confirm peer if not already confirmed
            if (_confirmedPeerUid == null && remoteUid == peerUidInt) {
              GSLogger.info('[Agora] *** CONFIRMED PEER WITH STARTING VIDEO: $remoteUid ***');
              _confirmedPeerUid = remoteUid;
              _remoteUid = remoteUid;
              _remoteConnection = connection;
              _onEventCallback?.call(PeerReadyEvent());
            }

            _onEventCallback?.call(RemoteMediaStateChangedEvent(
              mediaType: 'video',
              isEnabled: true,
            ));
            _onEventCallback?.call(RemoteVideoReadyEvent());
            return;
          }
          
          GSLogger.info('[Agora] Remote video STARTING for UID: $remoteUid (waiting for DECODING or UNMUTED)');
          return;
        }

        // --- VIDEO STOPPED ---
        if (state == RemoteVideoState.remoteVideoStateStopped) {
          // Handle PEER'S SCREEN SHARE stopped/muted
          if (remoteUid == screenShareUid) {
            // Only fire stop event if it's a real stop (offline), not just mute
            if (reason ==
                RemoteVideoStateReason.remoteVideoStateReasonRemoteOffline) {
              GSLogger.info(
                  '[Agora] Peer screen share STOPPED (offline): $remoteUid');
              _handleRemoteScreenShareStopped();
            } else {
              GSLogger.info(
                  '[Agora] Peer screen share video MUTED (temporary): $remoteUid');
              // Don't fire stop event - this is temporary
            }
            return;
          }

          // Handle PEER'S CAMERA muted
          if (reason ==
              RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
            GSLogger.info('[Agora] Remote peer MUTED video: $remoteUid');
            _onEventCallback?.call(RemoteMediaStateChangedEvent(
              mediaType: 'video',
              isEnabled: false,
            ));
          }
          return;
        }
      },

      // --- onUserJoined ---
      onUserJoined: (RtcConnection connection, int rUid, int elapsed) {
        // === LOGGING FOR DEBUGGING ===
        GSLogger.info("=== Agora: _onUserJoined ===");
        GSLogger.info("  remoteUid: $rUid");
        GSLogger.info("  peerUidInt: $peerUidInt");
        GSLogger.info("  ownUid: $ownUid");
        GSLogger.info("  ownScreenShareUid: $ownScreenShareUid");
        GSLogger.info("  screenShareUid (peer's): $screenShareUid");
        GSLogger.info("  _confirmedPeerUid: $_confirmedPeerUid");
        GSLogger.info("  _assignedLocalUid: $_assignedLocalUid");

        if (!_isSessionActive) {
          GSLogger.info('[Agora] Ignoring onUserJoined - session not active');
          return;
        }

        GSLogger.info("[Agora onUserJoined] Remote user $rUid joined");

        // === FILTER 1: Skip OWN screen share UID ===
        // When I share my screen, my screen share UID joins the channel.
        // I should ignore this - it's ME, not the peer.
        if (rUid == ownScreenShareUid) {
          GSLogger.info('[Agora] Ignoring own screen share UID join: $rUid');
          return;
        }

        // === FILTER 2: Skip OWN camera UID ===
        // _assignedLocalUid is what Agora assigned us after joinChannel.
        // ownUid is what we REQUESTED when joining.
        // Check both in case they differ (they shouldn't, but safety first).
        if (rUid == _assignedLocalUid || rUid == ownUid) {
          GSLogger.info('[Agora] Ignoring own UID: $rUid');
          return;
        }

        // === FILTER 3: Skip PEER's screen share UID ===
        // The peer's screen share UID is `screenShareUid` (computed property).
        // We DON'T subscribe to this here - we wait for the 'screenShareStarted' signal
        // and then subscribe in _handleRemoteScreenShareStarted().
        if (rUid == screenShareUid) {
          GSLogger.info(
              '[Agora] Peer screen share UID joined: $rUid - waiting for signal');
          return;
        }

        // === FILTER 4: Skip if NOT the expected peer camera UID ===
        // This is the CRITICAL filter. We only accept ONE specific UID as the peer.
        // peerUidInt = 2 if I'm tutor (ownUid=1), or 1 if I'm student (ownUid=2).
        if (rUid != peerUidInt) {
          GSLogger.info(
              '[Agora] Ignoring unexpected UID: $rUid (expected peer camera: $peerUidInt)');
          return;
        }

        // === FILTER 5: Skip if we already confirmed a peer ===
        // Prevent duplicate processing if the peer rejoins multiple times.
        if (_confirmedPeerUid != null) {
          GSLogger.info(
              '[Agora] Already confirmed peer $_confirmedPeerUid. Ignoring: $rUid');
          return;
        }

        // === SUCCESS: This is the peer's camera UID! ===
        GSLogger.info('[Agora] *** PEER CAMERA CONFIRMED: $rUid ***');

        // This is the peer's camera UID
        GSLogger.info('[Agora] Peer camera joined: $rUid');
        _confirmedPeerUid = rUid;
        _remoteUid = rUid;
        _remoteConnection = connection;
        _cachedRemoteController = null;
        _cachedRemoteUid = null;

        // Don't subscribe or create controller here - wait for onRemoteVideoStateChanged
        // with remoteVideoStateDecoding which indicates the track is actually ready
        _onEventCallback?.call(PeerReadyEvent());
        // Don't fire RemoteVideoReadyEvent yet - wait for video to actually be decoding
      },
      onUserMuteAudio: (RtcConnection connection, int remoteUid, bool muted) {
        if (!_isSessionActive) return;
        if (remoteUid != _confirmedPeerUid) return;

        GSLogger.info(
            '[Agora] Remote peer ${muted ? "MUTED" : "UNMUTED"} audio: $remoteUid');
        _onEventCallback?.call(RemoteMediaStateChangedEvent(
          mediaType: 'audio',
          isEnabled: !muted,
        ));
      },

      onAudioDeviceStateChanged: (deviceId, deviceType, deviceState) {
        GSLogger.info("======== Audio Device State Changed ========");
        GSLogger.info(
            "AudioDeviceStateChanged: deviceId=$deviceId, type=$deviceType, state=$deviceState");
      },

      onAudioRoutingChanged: (routing) {
        GSLogger.info("======== Audio Routing Changed ========");
        GSLogger.info("AudioRoutingChanged: routing=$routing");
      },

      onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
        if (!_isSessionActive) return;
        if (remoteUid != _confirmedPeerUid) return;

        GSLogger.info(
            '[Agora] Remote peer ${muted ? "MUTED" : "UNMUTED"} video: $remoteUid');
        _onEventCallback?.call(RemoteMediaStateChangedEvent(
          mediaType: 'video',
          isEnabled: !muted,
        ));
      },

      onLocalVideoStateChanged: (VideoSourceType source,
          LocalVideoStreamState state, LocalVideoStreamReason reason) {
        GSLogger.info(
            '[Agora] onLocalVideoStateChanged: source=$source, state=$state, reason=$reason');

        // Detect when screen share is stopped via browser button
        if (source == VideoSourceType.videoSourceScreen ||
            source == VideoSourceType.videoSourceScreenPrimary ||
            source == VideoSourceType.videoSourceScreenSecondary) {
          if (state == LocalVideoStreamState.localVideoStreamStateStopped ||
              state == LocalVideoStreamState.localVideoStreamStateFailed) {
            GSLogger.info('[Agora] Screen share stopped via browser button');

            // Only handle if we think we're still sharing
            if (_isSharingScreen) {
              GSLogger.info(
                  '[Agora] Cleaning up after browser-initiated screen share stop');

              _handleLocalScreenShareStopped();
            }
          }
        }
      },

      // --- onUserOffline ---
      onUserOffline: (connection, remoteUid, reason) {
        if (!_isSessionActive) return;

        GSLogger.info(
            '[Agora onUserOffline] remoteUid: $remoteUid, reason: $reason');

        if (remoteUid == ownScreenShareUid) {
          GSLogger.info(
              '[Agora] Ignoring own screen share offline: $remoteUid');
          return;
        }

        // Only fire ScreenShareStoppedEvent if peer was actually sharing
        if (remoteUid == screenShareUid && _isRemoteSharingScreen) {
          GSLogger.info('[Agora] Peer screen share STOPPED: $remoteUid');
          _isRemoteSharingScreen = false;
          _remoteScreenShareUid = null;
          _screenShareViewController = null;
          _onEventCallback?.call(ScreenShareStoppedEvent());
          return;
        }

        if (remoteUid == _confirmedPeerUid || remoteUid == _remoteUid) {
          GSLogger.info('[Agora] Peer camera left: $remoteUid');
          _remoteUid = null;
          _confirmedPeerUid = null;
          _cachedRemoteController = null;
          _cachedRemoteUid = null;
          _remoteConnection = null;
          _onEventCallback?.call(P2PConnectionFailedEvent(sessionEpoch: 0));
        }
      },

      // --- onLeaveChannel ---
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        GSLogger.info(
            '[Agora] onLeaveChannel - Left channel ${connection.channelId}');
      },

      // --- onError ---
      onError: (ErrorCodeType err, String msg) {
        GSLogger.error('[Agora onError] err: $err, msg: $msg');
        _onEventCallback?.call(ConnectionFailedEvent(msg));
        if (!_sessionReadyCompleter.isCompleted) {
          _sessionReadyCompleter.completeError(Exception(msg));
        }
      },
    );
  }

  /// Applies all stored device selections to Agora engine
  Future<void> _applySelectedDevices() async {
    GSLogger.info("Agora: _applySelectedDevices");
    GSLogger.info("  audioInput: $selectedAudioInputDeviceId");
    GSLogger.info("  audioOutput: $selectedAudioOutputDeviceId");
    GSLogger.info("  videoInput: $selectedVideoInputDeviceId");

    if (_engineManager.engine == null) {
      GSLogger.warning("Agora: Engine not initialized, cannot apply devices");
      return;
    }

    // Apply audio input device
    if (selectedAudioInputDeviceId != null &&
        selectedAudioInputDeviceId!.isNotEmpty &&
        selectedAudioInputDeviceId != 'default') {
      try {
        await _engineManager.setAudioInputDevice(selectedAudioInputDeviceId!);
        GSLogger.info("Agora: Audio input device applied successfully");
      } catch (e) {
        GSLogger.error("Agora: Failed to apply audio input device: $e");
      }
    }

    // Apply audio output device
    if (selectedAudioOutputDeviceId != null &&
        selectedAudioOutputDeviceId!.isNotEmpty &&
        selectedAudioOutputDeviceId != 'default') {
      try {
        await _engineManager.setAudioOutputDevice(selectedAudioOutputDeviceId!);
        GSLogger.info("Agora: Audio output device applied successfully");
      } catch (e) {
        GSLogger.error("Agora: Failed to apply audio output device: $e");
      }
    }

    // Apply video input device
    if (selectedVideoInputDeviceId != null &&
        selectedVideoInputDeviceId!.isNotEmpty &&
        selectedVideoInputDeviceId != 'default') {
      try {
        await _engineManager.setVideoInputDevice(selectedVideoInputDeviceId!);
        GSLogger.info("Agora: Video input device applied successfully");
      } catch (e) {
        GSLogger.error("Agora: Failed to apply video input device: $e");
      }
    }
  }

  Future<void> _subscribeToRemoteUser(int uid) async {
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.error('[Agora] Cannot subscribe - engine is null');
      return;
    }

    try {
      GSLogger.info('[Agora] Subscribing to remote user: $uid');

      // Unmute remote streams to enable receiving
      await engine.muteRemoteAudioStream(uid: uid, mute: false);
      await engine.muteRemoteVideoStream(uid: uid, mute: false);

      // Setup remote video canvas - important for web platform
      await engine.setupRemoteVideo(VideoCanvas(
        uid: uid,
        renderMode: RenderModeType.renderModeFit,
        mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
      ));

      // Set subscription options for high quality
      try {
        await engine.setRemoteVideoSubscriptionOptions(
          uid: uid,
          options: const VideoSubscriptionOptions(
            type: VideoStreamType.videoStreamHigh,
          ),
        );
      } catch (e) {
        // This might not be supported on web, ignore
        GSLogger.info('[Agora] setRemoteVideoSubscriptionOptions not supported: $e');
      }

      GSLogger.info('[Agora] Subscribed to remote user: $uid');
    } catch (e) {
      // Error -4 (NOT_READY) is expected sometimes
      GSLogger.warning('[Agora] Error subscribing to remote user $uid: $e');
    }
  }

  @override
  Future<void> dispose({bool closeSignaling = true}) async {
    GSLogger.info('AgoraStrategy: Disposing session...');

    _isSessionActive = false;

    // 1. Stop screen share if active
    if (_isSharingScreen) {
      try {
        await _engineManager.stopScreenShare();
      } catch (e) {
        GSLogger.error("Error stopping screen share during dispose: $e");
      }
    }

    // 3. Reset screen share state
    _isSharingScreen = false;
    _screenShareLocalUid = null;
    _isRemoteSharingScreen = false;
    _remoteScreenShareUid = null;
    _screenShareViewController = null;

    // 1. Unregister event handler
    _engineManager.unregisterEventHandler();
    _rtcEngineEventHandler = null;

    // 2. Leave channel (but keep engine alive!)
    try {
      await _engineManager.leaveChannel();
    } catch (e) {
      GSLogger.error('Error leaving channel during dispose: $e');
    }

    // 3. Clear state
    _localViewController = null;
    _cachedRemoteController = null;
    _screenShareViewController = null;
    _cachedRemoteUid = null;
    _remoteUid = null;
    _confirmedPeerUid = null;
    _remoteConnection = null;
    _assignedLocalUid = null;
    _screenShareConnection = null;
    _screenShareLocalUid = null;
    _dataStreamId = null;
    _reliableChannel = null;

    // 4. Close data stream
    if (!_dataStreamController.isClosed) {
      _dataStreamController.close();
    }

    GSLogger.info('AgoraStrategy: Session disposed (engine kept alive)');
  }

  @override
  Future<void> sendApplicationData(Uint8List data) async {
    // Create a local reference to the engine for null-safety promotion.
    final engine = _engineManager.engine;
    if (engine == null || _dataStreamId == null) {
      GSLogger.log("Cannot send data: engine or stream ID is not initialized.");
      return; // Exit early if not ready
    }

    // Delegate sending to the reliable channel

    try {
      // Now it's safe to use 'engine' without the '!' operator.
      _reliableChannel?.sendData(data);
    } catch (e) {
      GSLogger.log("Error sending Agora stream message: $e");
    }
  }

  Future<void> startCall() async {
    GSLogger.info("AgoraSessionStrategy: startCall");

    final engine = _engineManager.engine;
    if (engine == null) return;

    try {
      // Unmute and publish
      await engine.muteLocalAudioStream(false);
      await engine.muteLocalVideoStream(false);
      await engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ));
      await engine.startPreview();

      GSLogger.info("AgoraSessionStrategy: Call started - audio/video ON");
    } catch (e) {
      GSLogger.error("Error starting call: $e");
    }
  }

  @override
  Future<void> endCall() async {
    GSLogger.info("AgoraSessionStrategy: endCall");

    final engine = _engineManager.engine;
    if (engine == null) return;

    try {
      // Mute and stop publishing
      await engine.muteLocalAudioStream(true);
      await engine.muteLocalVideoStream(true);
      await engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
      ));
      await engine.stopPreview();

      GSLogger.info("AgoraSessionStrategy: Call ended - audio/video OFF");
    } catch (e) {
      GSLogger.error("Error ending call: $e");
    }
  }

  /*Future<void> _switchCamera() async {
    await _engine!.switchCamera();
  }

  _openCamera() async {
    await _engine!.enableLocalVideo(!openCamera);
  }

  _muteLocalVideoStream() async {
    await _engine!.muteLocalVideoStream(!muteCamera);
    
  }

  _muteAllRemoteVideoStreams() async {
    await _engine!.muteAllRemoteVideoStreams(!muteAllRemoteVideo);
  }*/

  @override
  Future<void> toggleLocalAudio(bool isEnabled) async {
    // Added the isEnabled parameter
    // --- Guard Clause ---
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.log("Cannot toggle audio: engine is not initialized.");
      return;
    }

    try {
      if (isEnabled) {
        // 1. Enable hardware capture
        // Unmute - start publishing audio
        await engine.muteLocalAudioStream(false);
        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishMicrophoneTrack: true,
        ));
        GSLogger.info("Agora: Audio UNMUTED");
      } else {
        // Mute - stop publishing audio (but keep track enabled)
        await engine.muteLocalAudioStream(true);
        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishMicrophoneTrack: false,
        ));
        GSLogger.info("Agora: Audio MUTED");
      }
    } catch (e) {
      GSLogger.log("Error toggling Agora local audio: $e");
    }
  }

  @override
  Future<void> toggleLocalVideo(bool isEnabled) async {
    // This maps directly to enableLocalVideo from the example
    // --- Guard Clause ---
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.info("Cannot toggle audio: engine is not initialized.");
      return;
    }

    try {
      GSLogger.info("Mute LocalVideoStream ${!isEnabled}");
      if (isEnabled) {
        // ENABLE VIDEO
        GSLogger.info("Enabling Local Video...");

        await engine.enableVideo();

        // 1. First, start the preview (this enables the track)
        GSLogger.info("Starting Local Video Preview");
        await engine.startPreview();

        // 2. Small delay to let the track initialize
        await Future.delayed(const Duration(milliseconds: 200));

        // 3. Then unmute the video stream
        GSLogger.info("Unmute LocalVideoStream");
        await engine.muteLocalVideoStream(false);

        // 3. Update channel options to publish
        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishCameraTrack: true,
        ));

        GSLogger.info("Agora: Video ON");
      } else {
        //  DISABLE VIDEO
        GSLogger.info("Disabling Local Video...");

        // 1. Mute the video stream first
        GSLogger.info("Mute LocalVideoStream");
        await engine.muteLocalVideoStream(true);

        // 2. Stop publishing
        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishCameraTrack: false,
        ));

        // 3. Then stop the preview
        GSLogger.info("Stopping Local Video Preview");
        await engine.stopPreview();

        //await engine.disableVideo();

        GSLogger.info("Agora: Video OFF");
      }
    } catch (e) {
      GSLogger.log("Error toggling Agora local audio: $e");
    }
  }

  /// Refresh the remote video controller (clears cache and recreates)
  void refreshRemoteVideoController() {
    GSLogger.info("Agora: Refreshing remote video controller");
    _cachedRemoteUid = null;
    _cachedRemoteController = null;

    // Recreate if we have a remote UID
    if (_confirmedPeerUid != null) {
      GSLogger.info(
          "Agora: Recreating remote controller for UID: $_confirmedPeerUid");

      _cachedRemoteController = VideoViewController.remote(
        rtcEngine: _engineManager.engine!,
        canvas: VideoCanvas(
          uid: _confirmedPeerUid!,
          renderMode: RenderModeType.renderModeHidden,
        ),
        connection: RtcConnection(channelId: channelName),
      );
      _cachedRemoteUid = _confirmedPeerUid;
    }
  }

  @override
  Future<void> startScreenShare() async {
    GSLogger.info(
        "AgoraSessionStrategy: Starting screen share with separate connection");

    if (_isSharingScreen) {
      GSLogger.info("Already sharing screen");
      return;
    }

    try {
      // Start screen share on separate engine
      await _engineManager!.startScreenShare();

      _isSharingScreen = true;

      _screenShareLocalUid = ownScreenShareUid;
      GSLogger.info("Agora: Screen share will use UID: $_screenShareLocalUid");

      // 5. Notify peer via data channel
      _sendScreenShareSignal(true);

      // 6. Fire event for local UI
      _onEventCallback?.call(LocalScreenShareStartedEvent());

      GSLogger.info(
          "AgoraSessionStrategy: Screen share started successfully with UID: $_screenShareLocalUid");
    } catch (e) {
      GSLogger.error("AgoraSessionStrategy: Failed to start screen share: $e");
      _isSharingScreen = false;
      _screenShareLocalUid = null;
      rethrow;
    }
  }

  @override
  Future<void> stopScreenShare() async {
    GSLogger.info("AgoraSessionStrategy: Stopping screen share");

    if (!_isSharingScreen) {
      GSLogger.info("Not sharing screen, nothing to stop");
      return;
    }

    try {
      // Use the engine manager directly
      await _engineManager.stopScreenShare();

      _isSharingScreen = false;
      _screenShareLocalUid = null;

      // Notify peer
      _sendScreenShareSignal(false);

      // Fire event
      // 3. Fire event to update local UI
      _onEventCallback?.call(LocalScreenShareStoppedEvent());
    } catch (e) {
      GSLogger.error("AgoraSessionStrategy: Error stopping screen share: $e");
      _isSharingScreen = false;
      _screenShareLocalUid = null;
    }
  }

  /// Sends screen share start/stop signal to peer via data channel
  void _sendScreenShareSignal(bool isStarting) {
    final signalType = isStarting ? 'screenShareStarted' : 'screenShareStopped';

    GSLogger.info("Agora: Sending '$signalType' signal to peer");

    final payload = {
      'type': signalType,
      'screenShareUid':
          ownScreenShareUid, // Include the screen share UID for reference
    };

    try {
      final bytes = utf8.encode(jsonEncode(payload));
      sendUnreliableData(bytes);
      GSLogger.info("Agora: '$signalType' signal sent successfully");
    } catch (e) {
      GSLogger.error("Agora: Failed to send '$signalType' signal: $e");
    }
  }

  /// Web-specific screen share implementation
  Future<void> _startScreenShareWeb(RtcEngineEx engine) async {
    try {
      GSLogger.info("Agora Web: Starting screen capture...");

      // 1. Start screen capture WITHOUT audio to avoid mutex issue
      await engine.startScreenCapture(const ScreenCaptureParameters2(
        captureAudio: false,
        captureVideo: true,
      ));

      // 2. Wait for capture to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. Update channel options - DON'T touch audio options on web
      const options = ChannelMediaOptions(
        publishCameraTrack: false,
        publishScreenTrack: true,
        publishScreenCaptureVideo: true,
      );

      await engine.updateChannelMediaOptions(options);

      GSLogger.info("Agora Web: Screen share started successfully");
    } catch (e) {
      GSLogger.error("Agora Web: Error in _startScreenShareWeb: $e");
      rethrow;
    }
  }

  /// Helper method to start desktop screen capture (macOS/Windows)
  Future<void> _startDesktopScreenCapture(RtcEngine engine) async {
    const thumbSize = SIZE(width: 360, height: 240);
    const iconSize = SIZE(width: 360, height: 240);

    final sources = await engine.getScreenCaptureSources(
      thumbSize: thumbSize,
      iconSize: iconSize,
      includeScreen: true,
    );

    if (sources.isEmpty) {
      throw Exception("No screen sources found.");
    }

    // Pick the first source (you could show a picker UI here)
    final source = sources.first;

    if (source.type == ScreenCaptureSourceType.screencapturesourcetypeScreen) {
      await engine.startScreenCaptureByDisplayId(
        displayId: source.sourceId!,
        regionRect: const Rectangle(x: 0, y: 0, width: 0, height: 0),
        captureParams: const ScreenCaptureParameters(
          captureMouseCursor: true,
          frameRate: 30,
        ),
      );
    } else {
      await engine.startScreenCaptureByWindowId(
        windowId: source.sourceId!,
        regionRect: const Rectangle(x: 0, y: 0, width: 0, height: 0),
        captureParams: const ScreenCaptureParameters(
          captureMouseCursor: true,
          frameRate: 30,
        ),
      );
    }
  }

  /// Helper method to update channel media options for screen sharing
  Future<void> _updateChannelMediaOptionsForScreenShare(
      bool isScreenShared) async {
    if (kIsWeb) {
      GSLogger.warning(
          "_updateChannelMediaOptionsForScreenShare should not be called on web");
      return;
    }

    final options = ChannelMediaOptions(
      publishCameraTrack: !isScreenShared,
      publishMicrophoneTrack: true, // Keep mic on during screen share
      publishScreenTrack: isScreenShared,
      publishScreenCaptureAudio: isScreenShared,
      publishScreenCaptureVideo: isScreenShared,
    );

    await _engineManager.engine?.updateChannelMediaOptions(options);
    GSLogger.info(
        "Agora: Updated channel options - publishScreenTrack: $isScreenShared");
  }


  void _handleRemoteScreenShareStarted({int? signalScreenShareUid}) {
    GSLogger.info("=== Agora: _handleRemoteScreenShareStarted ===");
    GSLogger.info("  signalScreenShareUid: $signalScreenShareUid");
    GSLogger.info("  ownScreenShareUid: $ownScreenShareUid");
    GSLogger.info("  screenShareUid (peer's): $screenShareUid");

    // === GUARD 1: Skip if this is our own signal echoing back ===
    if (signalScreenShareUid != null &&
        signalScreenShareUid == ownScreenShareUid) {
      GSLogger.info("Agora: Ignoring own screenShareStarted signal (echo).");
      return;
    }

    // === GUARD 2: Skip if already showing remote screen share ===
    if (_isRemoteSharingScreen && _screenShareViewController != null) {
      GSLogger.info("Agora: Already showing remote screen share. Ignoring.");
      return;
    }

    // === GUARD 3: Engine must be available ===
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.error("Agora: Engine is null, cannot handle screen share.");
      return;
    }

    // === Stop our own screen share if active ===
    if (_isSharingScreen) {
      GSLogger.info(
          "Agora: Stopping local screen share because remote peer started sharing.");
      _stopLocalScreenShareSilently();
    }

    // Just set flag - onUserJoined will create the controller when screen share UID joins
    _isRemoteSharingScreen = true;

    // Use the peer's SCREEN SHARE UID, not camera UID
    // The peer's screen share UID = screenShareUid (computed property)
    // This gives us peer's screen share UID
    _remoteScreenShareUid = screenShareUid;

    GSLogger.info(
        "Agora: Remote screen share UID set to: $_remoteScreenShareUid");

    _subscribeToRemoteUser(_remoteScreenShareUid!);

    // === Create the video controller for screen share ===
    GSLogger.info(
        "Agora: Creating controller for peer's screen share UID: $_remoteScreenShareUid");

    _screenShareViewController = VideoViewController.remote(
      rtcEngine: engine,
      canvas: VideoCanvas(
        uid: _remoteScreenShareUid!,
        renderMode: RenderModeType.renderModeFit,
      ),
      connection: RtcConnection(channelId: channelName),
    );

    GSLogger.info("Agora: Created _screenShareViewController");

    GSLogger.info(
        "Agora: Firing RemoteScreenShareStartedEvent with agoraController: $_screenShareViewController");
    // 3. Fire event to show the overlay
    _onEventCallback?.call(RemoteScreenShareStartedEvent(
      agoraController: _screenShareViewController,
    ));
  }

  Future<void> _stopLocalScreenShareSilently() async {
    final engine = _engineManager.engine;
    if (engine == null) {
      return;
    }

    // Check if not sharing
    if (!_isSharingScreen) {
      GSLogger.log("Agora: Not sharing screen. Nothing to stop silently.");
      return;
    }

    GSLogger.log("Agora: Stopping local screen share silently...");

    // Set flag IMMEDIATELY
    _isSharingScreen = false;

    try {
      // 1. Stop the OS-level screen capture
      await engine.stopScreenCapture();

      await Future.delayed(const Duration(milliseconds: 500));

      // 2. Switch back to publishing camera
      if (kIsWeb) {
        const options = ChannelMediaOptions(
          publishCameraTrack: true,
          publishScreenTrack: false,
          publishScreenCaptureVideo: false,
        );
        await engine.updateChannelMediaOptions(options);
      } else {
        await _updateChannelMediaOptionsForScreenShare(false);
      }

      // 3. Restart camera preview
      await engine.startPreview();

      await Future.delayed(const Duration(milliseconds: 300));

      // 4. Fire local stop event (to clear preview) but NOT send signal to peer
      _onEventCallback?.call(LocalScreenShareStoppedEvent());

      GSLogger.log("Agora: Local screen share stopped silently.");
    } catch (e) {
      GSLogger.error("Agora: Error stopping local screen share silently: $e");
      // Fire stop event anyway
      _onEventCallback?.call(LocalScreenShareStoppedEvent());
    }
  }

  void _handleRemoteScreenShareStopped() {
    GSLogger.info("Agora: _handleRemoteScreenShareStopped called");

    if (!_isRemoteSharingScreen) {
      GSLogger.info("Agora: Not showing remote screen share. Ignoring.");
      return;
    }

    _isRemoteSharingScreen = false;
    _remoteScreenShareUid = null;
    _screenShareViewController = null;

    // Force refresh the remote video controller to show camera again
    _cachedRemoteController = null;
    _cachedRemoteUid = null;

    // Fire event to hide the overlay
    _onEventCallback?.call(ScreenShareStoppedEvent());
  }

  /// Optional: Get a local preview of the screen share
  Widget getLocalScreenSharePreview() {
    // Web: Local screen preview doesn't work well,
    // show placeholder
    if (kIsWeb) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.screen_share, color: Colors.white, size: 48),
              SizedBox(height: 8),
              Text(
                'You are sharing your screen',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_engineManager.engine == null || !_isSharingScreen) {
      return const ColoredBox(color: Colors.black);
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engineManager.engine!,
        canvas: const VideoCanvas(
          uid: 0,
          sourceType: VideoSourceType.videoSourceScreen,
        ),
      ),
    );
  }

  @override
  int get sessionEpoch => _sessionEpoch;

  @override
  void handleExternalSignalingMessage(dynamic message) {
    // Agora does not use an external signaling channel for WebRTC signals,
    // so this method can be empty.
  }

  @override
  void handleExternalSignalingEvent(SignalingEvent event) {
    // Agora does not need to react to these events.
  }

  @override
  Future<void> initiateHandshake({bool addTracks = false}) async {
    
    GSLogger.info("Agora: Starting 'Handshake' (Enabling publishing).");
    // We update options to start publishing.
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.warning("Agora: No engine for handshake.");
      // Still fire DataChannelOpenedEvent - data channel can work without media
      _onEventCallback?.call(DataChannelOpenedEvent());
      return;
    }
    if (addTracks) {
      // Try to enable media, but don't fail if unavailable
      try {
        await engine.enableVideo();
        await engine.enableAudio();
        await engine.startPreview();

        await engine.updateChannelMediaOptions(const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
        ));

        await engine.muteLocalAudioStream(false);
        await engine.muteLocalVideoStream(false);

        GSLogger.info("Agora: Media tracks enabled for handshake.");
      } catch (e) {
        // CATCH permission denied and continue
        GSLogger.warning("Agora: Could not enable media for handshake: $e");
        GSLogger.info(
            "Agora: Continuing without media - data channel only mode");

        // Notify UI about media unavailability
        _onEventCallback
            ?.call(LocalMediaUnavailableEvent(reason: e.toString()));
      }
    }
    // ALWAYS fire DataChannelOpenedEvent (data channel works without
    // media)
    _onEventCallback?.call(DataChannelOpenedEvent());
    
  }

  @override
  Future<void> disableMedia() async {
    GSLogger.info("Agora: disableMedia() - Muting local audio/video streams.");

    if (_engineManager.engine == null) {
      GSLogger.warning("Agora: No engine to disable media.");
      return;
    }

    // Mute (stop publishing) but keep capturing
    await _engineManager.engine!.muteLocalAudioStream(true);
    await _engineManager.engine!.muteLocalVideoStream(true);

    GSLogger.info("Agora: Local audio/video muted (not publishing).");
  }

  @override
  Future<void> enableMedia() async {
    GSLogger.info("Agora: enableMedia() - Unmuting local audio/video streams.");

    
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.warning("Agora: No engine to enable media.");
      return;
    }

    try {
      // Try to enable video/audio at engine level first
      await engine.enableVideo();
      await engine.enableAudio();

      // Start preview (this may fail if no camera permission)
      await engine.startPreview();

      // Update channel options to publish
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
        ),
      );

      // Unmute streams
      await engine.muteLocalAudioStream(false);
      await engine.muteLocalVideoStream(false);

      GSLogger.info("Agora: Local audio/video enabled and publishing.");

    } catch (e) {
      // Handle permission denied gracefully
      GSLogger.warning("Agora: Could not enable media: $e");
      GSLogger.info("Agora: Continuing without local media");

      // Notify UI about media unavailability
      _onEventCallback?.call(LocalMediaUnavailableEvent(reason: e.toString()));
    }
  }

  @override
  void resetReliabilityLayer() {
    // TODO: implement resetReliabilityLayer
  }

  @override
  void resetPeerConnection() {
    // No-op or custom logic if you want to 'refresh' the Agora connection
    GSLogger.log("Agora: resetPeerConnection called (No-op).");
  }

  @override
  Future<void> reconnectSession(
      {required Function(MediaSessionEvent event) onEvent,
      bool wasCallActive = false}) async {
    // Re-assign callback
    _onEventCallback = onEvent;
    // Agora usually reconnects automatically. If you need a hard reset:
    // await dispose(closeSignaling: false);
    // await startSession(onEvent: onEvent);
  }

  @override
  void refreshTracks(bool shouldBeEnabled) {}

  @override
  Future<void> sendScreenShareStoppedSignal() async {
    final payload = {
      'type': 'screenShareStopped',
      'payload': {} // Agora doesn't need session IDs for this
    };
    final bytes = utf8.encode(jsonEncode(payload));

    // Send as unreliable (fast) data
    await sendUnreliableData(bytes);
  }

  @override
  void handleIncomingNegotiationMessage(Map<String, dynamic> message) {}

  @override
  Future<void> sendUnreliableData(Uint8List data) async {
    final engine = _engineManager.engine;
    if (engine == null || _dataStreamId == null) {
      GSLogger.log("Cannot send data: engine or stream ID is not initialized.");
      return;
    }

    // Check if the message exceeds 1KB limit (Agora specific)
    if (data.length > 1024) {
      GSLogger.log(
          "WARNING: Unreliable message size ${data.length} exceeds 1KB limit. It may be dropped.");
      // For unreliable data, we usually don't chunk.
      // You might want to compress it or split it manually if it's critical.
      // For now, let's proceed and see if it errors.
    }

    try {
      // Send directly via Agora stream.
      await engine.sendStreamMessage(
        streamId: _dataStreamId!,
        data: data,
        length: data.length,
      );
    } catch (e) {
      GSLogger.log("Error sending Agora unreliable data: $e");
    }
  }

  @override
  void setReconnecting(bool isReconnecting) {
    _isReconnecting = isReconnecting;
  }

  /// Creates the screen share controller when stream becomes active
  void _createScreenShareController(int uid) {
    final engine = _engineManager.engine;
    if (engine == null) {
      GSLogger.error(
          '[Agora] Cannot create screen share controller - engine is null');
      return;
    }

    if (_screenShareViewController != null) {
      GSLogger.info('[Agora] Screen share controller already exists');
      return;
    }

    GSLogger.info('[Agora] Creating screen share controller for UID: $uid');

    _screenShareViewController = VideoViewController.remote(
      rtcEngine: engine,
      canvas: VideoCanvas(
        uid: uid,
        renderMode: RenderModeType.renderModeFit,
      ),
      connection: RtcConnection(channelId: channelName),
    );

    GSLogger.info('[Agora] Firing RemoteScreenShareStartedEvent');
    _onEventCallback?.call(RemoteScreenShareStartedEvent(
      agoraController: _screenShareViewController,
    ));
  }
}
