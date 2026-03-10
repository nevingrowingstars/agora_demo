import 'dart:ui';

import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RemoteScreenShareWidget extends ConsumerStatefulWidget {
  const RemoteScreenShareWidget({Key? key}) : super(key: key);

  @override
  ConsumerState<RemoteScreenShareWidget> createState() =>
      _RemoteScreenShareWidgetState();
}

class _RemoteScreenShareWidgetState
    extends ConsumerState<RemoteScreenShareWidget> {
  // Local state to manage the position of the draggable window.
  Offset _position = const Offset(100, 100);
  final ScrollController _shareScreenScrollController = ScrollController();

  // TransformationController for zoom/pan
  final TransformationController _transformationController =
      TransformationController();
      

  @override
  void dispose() {
    _transformationController.dispose();
    _shareScreenScrollController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    final double widgetWidth = screenSize.width * 0.8;
    final double widgetHeight = screenSize.height * 0.8;

    final sessionState = ref.watch(mediaSessionProvider).valueOrNull;
    final isRemoteSharing = sessionState?.isRemoteUserSharingScreen ?? false;
    final remoteRenderer = sessionState?.remoteScreenShareRenderer;
    final agoraController = sessionState?.agoraScreenShareController;
    final isDismissed = ref.watch(isScreenShareDialogDismissedProvider);

    GSLogger.info(
        "RemoteScreenShareWidget.build() called - isRemoteSharing: $isRemoteSharing, isDismissed: $isDismissed, hasRenderer: ${remoteRenderer != null}");

    GSLogger.info("RemoteScreenShareWidget.build():");
    GSLogger.info("  - isRemoteSharing: $isRemoteSharing");
    GSLogger.info("  - isDismissed: $isDismissed");
    GSLogger.info("  - remoteRenderer: $remoteRenderer");
    GSLogger.info("  - agoraController: $agoraController");

    // Add this debug info
    if (agoraController != null) {
      GSLogger.info("  - agoraController canvas UID: ${agoraController.canvas.uid}");
      GSLogger.info("  - agoraController connection: ${agoraController.connection?.channelId}");
    }

    // Check if remote is sharing AND we have a valid renderer/
    // controller
    if (!isRemoteSharing || isDismissed) {
      return const SizedBox.shrink();
    }

    // Need at least one valid renderer/controller
    if (remoteRenderer == null && agoraController == null) {
      return const SizedBox.shrink();
    }

    // Build the video view based on which strategy is active
    Widget videoView;
    
    if (remoteRenderer != null) {
      // WebRTC path - use RTCVideoViewObjectFitCover to fill the space
      videoView = RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
    } else {
      // Agora path
      videoView = AgoraVideoView(controller: agoraController!);
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: widgetWidth,
            height: widgetHeight,
            //child: GestureDetector(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent, width: 2),
                  color:
                      Colors.black, // Set a base color for the window
                ),
                child: Column(
                  children: [
                    _buildHeaderBar(),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10)),

                        child: Container(
                          color: Colors.black,
                          child: _buildVideoContent(
                              remoteRenderer, agoraController),
                        ),

                        /*child: InteractiveViewer(
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Container(
                          color: Colors.black,
                          child: Center(
                            child: videoView,
                          ),
                        ),
                      ),*/

                        // The Scrollbar and SingleChildScrollView are correct.

                        /*child: Scrollbar(
                          controller: _shareScreenScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _shareScreenScrollController,
                            // The child is now an AspectRatio widget.
                            scrollDirection: Axis.horizontal,
                            child: AspectRatio(
                              // 1. Calculate the aspect ratio from the renderer's video value.
                              aspectRatio: aspectRatio,
                              child: videoView,
                            ),
                          ),
                        ),
                        */
                      ),
                    ),
                  ],
                ),
              ),
            //),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoContent(
    RTCVideoRenderer? remoteRenderer,
    VideoViewController? agoraController,
  ) {
    // Use LayoutBuilder to get actual available size
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget videoView;

        if (remoteRenderer != null) {
          // WebRTC path
          // Use FittedBox with BoxFit.contain to fill width while maintaining aspect ratio
          // Then wrap in scrollable for vertical overflow
          videoView = SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SizedBox(
              width: constraints.maxWidth,
              // Calculate height based on source aspect ratio
              // If source is 16:9 and width is 800, height = 800 / (16/9) = 450
              height:
                  _calculateVideoHeight(remoteRenderer, constraints.maxWidth),
              child: RTCVideoView(
                remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          );
        } else if (agoraController != null) {
          // Agora path
          videoView = SizedBox.expand(
            child: AgoraVideoView(
              key: ValueKey(agoraController.hashCode),
              controller: agoraController),
          );
        } else {
          videoView = const Center(
            child: Text(
              'No video available',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return videoView;
        // Wrap in InteractiveViewer for zoom/pan
        /* return InteractiveViewer(
          transformationController: _transformationController,
          panEnabled: true,
          scaleEnabled: false,
          minScale: 1.0,
          maxScale: 1.0,
          boundaryMargin: const EdgeInsets.all(100),
          child: videoView,
        ); */
      },
    );
  }

  double _calculateVideoHeight(
      RTCVideoRenderer renderer, double availableWidth) {
    // Get source dimensions
    final sourceWidth = renderer.value.width.toDouble();
    final sourceHeight = renderer.value.height.toDouble();

    if (sourceWidth <= 0 || sourceHeight <= 0) {
      // Default to 16:9 if dimensions not available
      return availableWidth / (16 / 9);
    }

    final aspectRatio = sourceWidth / sourceHeight;
    return availableWidth / aspectRatio;
  }

  Widget _buildHeaderBar() {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.screen_share, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  "Screen Share",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                // Fit to window button
                IconButton(
                  icon: const Icon(Icons.fit_screen,
                      color: Colors.white, size: 20),
                  tooltip: 'Reset zoom',
                  onPressed: _resetZoom,
                ),
                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    ref
                        .read(isScreenShareDialogDismissedProvider.notifier)
                        .state = true;
                  },
                ),
              ],
            ),
          ],
        ),
      //),
    );
  }
}
