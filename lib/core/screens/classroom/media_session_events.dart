import 'package:agora_demo/core/screens/agora/media_session_strategy.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

// =============================================================================
// Connection Events
// =============================================================================

/// Fired when the connection to the channel fails.
class ConnectionFailedEvent extends MediaSessionEvent {
  final String reason;
  ConnectionFailedEvent(this.reason);
}

/// Fired when signaling/channel connection is established.
class SignalingConnectedEvent extends MediaSessionEvent {}

/// Fired when the peer-to-peer connection fails.
class P2PConnectionFailedEvent extends MediaSessionEvent {
  final int sessionEpoch;
  P2PConnectionFailedEvent({required this.sessionEpoch});
}

// =============================================================================
// Peer Events
// =============================================================================

/// Fired when the remote peer is ready (joined and streaming).
class PeerReadyEvent extends MediaSessionEvent {}

// =============================================================================
// Media Events
// =============================================================================

/// Fired when local media (camera/mic) is unavailable.
class LocalMediaUnavailableEvent extends MediaSessionEvent {
  final String? reason;
  LocalMediaUnavailableEvent({this.reason});
}

/// Fired when the remote video stream is ready to display.
class RemoteVideoReadyEvent extends MediaSessionEvent {}

/// Fired when remote user's audio/video state changes (mute/unmute).
class RemoteMediaStateChangedEvent extends MediaSessionEvent {
  final String mediaType; // 'audio' or 'video'
  final bool isEnabled;

  RemoteMediaStateChangedEvent({
    required this.mediaType,
    required this.isEnabled,
  });
}

// =============================================================================
// Data Channel Events
// =============================================================================

/// Fired when the Agora data stream is ready for messaging.
class DataChannelOpenedEvent extends MediaSessionEvent {}

// =============================================================================
// Screen Share Events
// =============================================================================

/// Fired when local screen share has started successfully.
class LocalScreenShareStartedEvent extends MediaSessionEvent {}

/// Fired when local screen share has stopped.
class LocalScreenShareStoppedEvent extends MediaSessionEvent {}

/// Fired when the remote user starts sharing their screen.
class RemoteScreenShareStartedEvent extends MediaSessionEvent {
  /// The Agora VideoViewController for the remote screen share stream.
  final VideoViewController? agoraController;

  RemoteScreenShareStartedEvent({this.agoraController});
}

/// Fired when screen sharing stops (local or remote).
class ScreenShareStoppedEvent extends MediaSessionEvent {}


