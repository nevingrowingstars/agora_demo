// Create a new file, e.g., lib/core/model/signaling_event.dart

// The base class for all low-level signaling events.
abstract class SignalingEvent {}

// Fired when the WebSocket/HTTP connection itself is established.
class SignalingConnected extends SignalingEvent {}

// Fired when the server tells us the other user has joined our room.
// This is the trigger for the Tutor to send an offer.
class PeerJoinedSignaling extends SignalingEvent {
  final String peerSessionId;
  PeerJoinedSignaling(this.peerSessionId);
}

class PeerLeftSignaling extends SignalingEvent {}

class SignalingFailed extends SignalingEvent {
  final String reason;
  SignalingFailed(this.reason);
}

