import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';


enum CallStatus {
  // 1. Connected to Signaling. Waiting for Ring (Student) or waiting to Ring (Tutor).
  idle,      
  // 2. Ring signal sent/received. Waiting for Answer.
  ringing,   
  // 3. Accepted. Overlay hides. WebRTC Handshake begins.
  answered,  
  // 4 Active Session without Media (Whiteboard Only)
  activeNoMedia    
}


@immutable
class MediaSessionState {
  // --- View Widgets (Technology-Agnostic) ---
  final Widget localVideoView;
  final Widget remoteVideoView;

  // For remote screen share
  final RTCVideoRenderer? remoteScreenShareRenderer;
  final VideoViewController? agoraScreenShareController; 

  // Screen share is also just a widget

  /// A widget to display a preview of the screen the LOCAL user is sharing.
  /// This is typically shown in a small, floating window so the user
  /// knows what they are presenting.
  final Widget? localScreenSharePreview;

  // NEW: True when connected to WebSocket/HTTP
  final bool isSignalingConnected;

  // True = Manual Start. False = Recovery/Restore.
  
  // --- Connection Status Flags ---
  final bool isPeerConnected;
  final bool isPeerPresentInRoom;
  final bool isDataConnectionActive;
  final String dataConnectionState;

  final CallStatus callStatus;

  // --- Local User Status Flags ---
  final bool isLocalAudioEnabled;
  final bool isLocalVideoEnabled;
  final bool isLocalUserSharingScreen;

  /// Device/permission availability 
  /// False if: permission denied, device in use, device not found
  final bool isLocalMediaAvailable;
  final bool isPeerMediaAvailable;

  // --- Remote User Status Flags ---
  final bool isRemoteAudioEnabled;
  final bool isRemoteVideoEnabled;
  final bool isRemoteUserSharingScreen;
  final bool isPermanentlyDisconnected;

  const MediaSessionState({
    // Views default to placeholders
    this.localVideoView = const ColoredBox(color: Colors.black54),
    this.remoteVideoView = const ColoredBox(color: Colors.black54),
    this.remoteScreenShareRenderer,
    this.localScreenSharePreview,
    this.agoraScreenShareController,
    // Status flags
    this.isSignalingConnected = false,
    this.isPeerConnected = false,
    this.isPeerPresentInRoom = false,
    this.isDataConnectionActive = false,
    this.dataConnectionState = 'closed',
    this.callStatus = CallStatus.idle,
    this.isLocalAudioEnabled = true,
    this.isLocalVideoEnabled = true,
    this.isLocalUserSharingScreen = false,
    this.isLocalMediaAvailable = true,  
    this.isPeerMediaAvailable = true,  
    this.isRemoteAudioEnabled = true,
    this.isRemoteVideoEnabled = true,
    this.isRemoteUserSharingScreen = false,
    this.isPermanentlyDisconnected = false,
  });

  // The essential copyWith method remains crucial
  MediaSessionState copyWith({
    Widget? localVideoView,
    Widget? remoteVideoView,
    // Use an object to represent "null" if you need to clear the view
    // Or handle null directly in the copyWith logic
    bool clearRemoteVideoView = false,
    RTCVideoRenderer? remoteScreenShareRenderer,
    VideoViewController? agoraScreenShareController,
    bool clearRemoteScreenShareRenderer = false,
    Widget? localScreenSharePreview,
    bool? clearScreenShareView, // A flag to explicitly nullify the view
    bool? clearLocalScreenSharePreview = false,
    bool? isSignalingConnected,
    bool? isPeerConnected,
    bool? isPeerPresentInRoom,
    bool? isDataConnectionActive,
    String? dataConnectionState,
    CallStatus? callStatus,
    bool? isLocalAudioEnabled,
    bool? isLocalVideoEnabled,
    bool? isLocalUserSharingScreen,
    bool? isLocalMediaAvailable,
    bool? isPeerMediaAvailable,
    bool? isRemoteAudioEnabled,
    bool? isRemoteVideoEnabled,
    bool? isRemoteUserSharingScreen,
    bool? isPermanentlyDisconnected,
  }) {

    if (callStatus == CallStatus.answered) {
      print(">>> copyWith: callStatus being set to ANSWERED <<<");
    }

    return MediaSessionState(
      localVideoView: localVideoView ?? this.localVideoView,
      remoteVideoView: clearRemoteVideoView
          ? const ColoredBox(color: Colors.blueGrey) 
          : remoteVideoView ?? this.remoteVideoView,
      remoteScreenShareRenderer: clearRemoteScreenShareRenderer
          ? null
          : remoteScreenShareRenderer ?? this.remoteScreenShareRenderer,
      agoraScreenShareController: clearRemoteScreenShareRenderer
          ? null
          : agoraScreenShareController ?? this.agoraScreenShareController,
      localScreenSharePreview: (clearLocalScreenSharePreview == true)
          ? null
          : localScreenSharePreview ?? this.localScreenSharePreview,
      isSignalingConnected: isSignalingConnected ?? this.isSignalingConnected,
      isPeerConnected: isPeerConnected ?? this.isPeerConnected,
      isPeerPresentInRoom: isPeerPresentInRoom ?? this.isPeerPresentInRoom,
      isDataConnectionActive:
          isDataConnectionActive ?? this.isDataConnectionActive,
      dataConnectionState: dataConnectionState ?? this.dataConnectionState,
      callStatus: callStatus ?? this.callStatus,
      isLocalAudioEnabled: isLocalAudioEnabled ?? this.isLocalAudioEnabled,
      isLocalVideoEnabled: isLocalVideoEnabled ?? this.isLocalVideoEnabled,
      isLocalMediaAvailable: isLocalMediaAvailable ?? this.isLocalMediaAvailable,
      isPeerMediaAvailable: isPeerMediaAvailable ?? this.isPeerMediaAvailable,
      isLocalUserSharingScreen:
          isLocalUserSharingScreen ?? this.isLocalUserSharingScreen,
      isRemoteAudioEnabled: isRemoteAudioEnabled ?? this.isRemoteAudioEnabled,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      isRemoteUserSharingScreen:
          isRemoteUserSharingScreen ?? this.isRemoteUserSharingScreen,
      isPermanentlyDisconnected:
          isPermanentlyDisconnected ?? this.isPermanentlyDisconnected,
    );
  }

  const MediaSessionState.initial(
      this.localVideoView,
      this.remoteVideoView,
      this.remoteScreenShareRenderer,
      this.agoraScreenShareController,
      this.localScreenSharePreview,
      this.isSignalingConnected,
      this.isDataConnectionActive,
      this.dataConnectionState,
      this.isLocalAudioEnabled,
      this.isLocalVideoEnabled,
      this.isLocalUserSharingScreen,
      this.isLocalMediaAvailable,
      this.isPeerMediaAvailable,
      this.isRemoteAudioEnabled,
      this.isRemoteVideoEnabled,
      this.isRemoteUserSharingScreen)
      : isPeerConnected = false,
        isPeerPresentInRoom = false,
        callStatus = CallStatus.idle,
        isPermanentlyDisconnected = false;
}
