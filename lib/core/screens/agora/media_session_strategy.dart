// The unified event model remains the same.
import 'dart:typed_data';

import 'package:agora_demo/core/state/media/signaling_event.dart';
import 'package:flutter/material.dart';

abstract class MediaSessionEvent {/* ... */}

// The updated, powerful strategy interface

abstract class MediaSessionStrategy {
  /// Initializes the session and establishes a connection.
  /// It no longer takes renderers as arguments. It creates its own views.
  Future<void> startSession({
    required Function(MediaSessionEvent event) onEvent,
  });

  Future<void> reconnectSession({
    required Function(MediaSessionEvent event) onEvent,
    bool wasCallActive = false,
  });

  /// Set audio input device (microphone)
  Future<void> setAudioInputDevice(String deviceId);

  /// Set audio output device (speaker)
  Future<void> setAudioOutputDevice(String deviceId);

  /// Set video input device (camera)
  Future<void> setVideoInputDevice(String deviceId);

  // 1. Connects the peers (Data Channel / P2P).
  //    For WebRTC: Sends Offer.
  //    For Agora: Fires DataChannelOpened (since join happens at start).
  Future<void> initiateHandshake({bool addTracks = false});

  // 2. Unmutes local audio/video.
  //    For WebRTC: Sets track.enabled = true.
  //    For Agora: Sets publishCameraTrack = true.
  Future<void> enableMedia();

  /// Disables media tracks
  Future<void> disableMedia();

  int get sessionEpoch;

  //CommunicationStrategy get signalingChannel;

  // --- Add the public handlers for external events ---
  void handleExternalSignalingMessage(dynamic message);
  void handleExternalSignalingEvent(SignalingEvent event);

  /// Provides the widget to display the local user's video.
  Widget get localVideoView;

  /// Provides the widget to display the remote user's video.
  Widget get remoteVideoView;

  /// A stream of incoming data from the peer.
  Stream<Uint8List> get dataStream;

  /// Sends a chunk of data to the peer.
  Future<void> sendApplicationData(Uint8List data);

  Future<void> sendUnreliableData(Uint8List data);

  // User actions remain the same

  Future<void> startCall();
  Future<void> endCall();

  Future<void> toggleLocalAudio(bool status);
  Future<void> toggleLocalVideo(bool status);

  void refreshRemoteVideoController() {}

  // --- Screen Share  ---
  Future<void> startScreenShare();
  Future<void> stopScreenShare();

  void resetReliabilityLayer();

  void resetPeerConnection();

  void refreshTracks(bool shouldBeEnabled);

  Future<void> sendScreenShareStoppedSignal();

  void handleIncomingNegotiationMessage(Map<String, dynamic> message);

  void setReconnecting(bool bool);

  /// Cleans up all resources.
  Future<void> dispose();
}
