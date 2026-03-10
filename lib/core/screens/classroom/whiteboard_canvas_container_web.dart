import 'package:agora_demo/core/screens/classroom/participant_video_widget.dart';
import 'package:agora_demo/core/screens/classroom/remote_screen_share_widget.dart';
import 'package:agora_demo/core/screens/classroom/whiteboard_canvas_widget.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class WhiteboardCanvasContainerWeb extends ConsumerWidget {
  const WhiteboardCanvasContainerWeb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Watch the single, unified provider to get all the state we need.
    final sessionData = ref.watch(mediaSessionProvider).valueOrNull;
    return Stack(
      children: [
        // Main content area with optional tab bar
        Column(
          children: [
            // Content area - use IndexedStack to keep all tabs alive
            Expanded(
              child: WhiteboardCanvasWidget(),
            ),
          ],
        ),
        const ParticipantVideoWidgetWeb(), // Assuming this is now a unified video widget
        if ((sessionData != null) &&
            (sessionData.isRemoteUserSharingScreen))
          RemoteScreenShareWidget(),
      ],
    );
  }
}

