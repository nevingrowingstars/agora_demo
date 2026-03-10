import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ScreenShareState {
  final bool isSharing;
  final RTCVideoRenderer? renderer;
  final MediaStream? stream;
  const ScreenShareState({this.isSharing = false, this.renderer, this.stream});

  /// Manual copyWith implementation
  ScreenShareState copyWith({
    bool? isSharing,
    RTCVideoRenderer? renderer,
    MediaStream? stream,
    bool clearRenderer = false,
    bool clearStream = false,
  }) {
    return ScreenShareState(
      isSharing: isSharing ?? this.isSharing,
      renderer: clearRenderer ? null : (renderer ?? this.renderer),
      stream: clearStream ? null : (stream ?? this.stream),
    );
  }
}

class ScreenShareNotifier extends StateNotifier<ScreenShareState> {
  ScreenShareNotifier() : super(const ScreenShareState());

  Future<void> start(Future<MediaStream?> Function() capture) async {
    // fresh renderer per session
    
    GSLogger.info("ScreenShareNotifier: start");
    
    final renderer = RTCVideoRenderer();
    await renderer.initialize();

    MediaStream? stream;
    try {
      stream = await capture();
      if (stream == null) {
        // user cancelled → clean up the renderer we created
        await renderer.dispose();
        return;
      }
      renderer.srcObject = stream;

      // PUBLISH to UI: from now on widgets may mount RTCVideoView(renderer)
      state =
          ScreenShareState(isSharing: true, renderer: renderer, stream: stream);

      // Handle OS stop (e.g., "Stop sharing" button)
      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        videoTracks.first.onEnded = () {
          GSLogger.info("ScreenShareNotifier: Track ended by user");
          stop();
        };
      }
      GSLogger.info("ScreenShareNotifier: Screen share started successfully");

    } catch (e) {
      GSLogger.error("ScreenShareNotifier: Screen share failed: $e");
      // cleanup on failure
      try {
        renderer.srcObject = null;
      } catch (_) {}
      await renderer.dispose();
      rethrow;
    }
  }

  /// Start screen share with a void function (strategy handles the stream internally)
  Future<void> startWithStrategy(
    Future<void> Function() startFn, {
    Future<MediaStream?> Function()? getStream,
  }) async {

    GSLogger.info("ScreenShareNotifier: Starting screen share (via strategy)");
    
    try {
      await startFn();
      // If a stream getter is provided, set up local preview
      if (getStream != null) {
        final stream = await getStream();
        if (stream != null) {
          GSLogger.info("ScreenShareNotifier: Setting up local preview");
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;

          state = ScreenShareState(
            isSharing: true,
            renderer: renderer,
            stream: stream,
          );

          // Handle OS stop button
          final videoTracks = stream.getVideoTracks();
          if (videoTracks.isNotEmpty) {
            videoTracks.first.onEnded = () {
              GSLogger.info("ScreenShareNotifier: Track ended by user");
              stop();
            };
          }

          GSLogger.info(
              "ScreenShareNotifier: Local preview set up successfully");
          return;
        }
      }
      state = state.copyWith(isSharing: true);
      GSLogger.info("ScreenShareNotifier: Screen share started via strategy");
    } catch (e) {
      GSLogger.error("ScreenShareNotifier: Screen share failed: $e");
      state = state.copyWith(isSharing: false);
      rethrow;
    }
  }
  /// Set sharing state directly
  void setSharing(bool isSharing) {
    GSLogger.info("ScreenShareNotifier: setSharing($isSharing)");
    state = state.copyWith(isSharing: isSharing);
  }

  Future<void> stop() async {

    GSLogger.info("ScreenShareNotifier: Stopping screen share");

    final current = state;

    // 1) UNPUBLISH so UI unmounts RTCVideoView
    state =
        const ScreenShareState(isSharing: false, renderer: null, stream: null);

    // 2) Dispose next frame to avoid “used after disposed”
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        current.renderer?.srcObject = null;
      } catch (_) {}
      await current.renderer?.dispose();
      // stop tracks last
      final tracks = [
        ...?current.stream?.getAudioTracks(),
        ...?current.stream?.getVideoTracks(),
      ];
      for (final t in tracks) {
        try {
          t.stop();
        } catch (_) {}
      }
      GSLogger.info("ScreenShareNotifier: Screen share resources disposed");
    });
  }
}

final screenShareProvider =
    StateNotifierProvider<ScreenShareNotifier, ScreenShareState>((ref) {
  return ScreenShareNotifier();
});
