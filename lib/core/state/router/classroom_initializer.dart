import 'dart:io';

import 'package:agora_demo/core/model/media_session_state.dart';
import 'package:agora_demo/core/screens/classroom/whiteboard_canvas_container_web.dart';
import 'package:agora_demo/core/screens/classroom/whiteboard_classroom_connect_widget_web.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ClassroomWebInitializer extends ConsumerStatefulWidget {
  const ClassroomWebInitializer({super.key});

  @override
  ConsumerState<ClassroomWebInitializer> createState() =>
      _ClassroomWebInitializerState();
}

// 1. Add WidgetsBindingObserver for PIP Mode
class _ClassroomWebInitializerState
    extends ConsumerState<ClassroomWebInitializer> with WidgetsBindingObserver {
  @override
  void initState() {
    GSLogger.log("ClassroomWebInitializer: initState()");
    super.initState();
    WidgetsBinding.instance
        .addObserver(this); // 2. Listen to lifecycle for PIP mode
    // This single call orchestrates the entire rejoin process in the correct order.
    _initializeAndRejoinSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    super.dispose();
  }

  Future<void> _initializeAndRejoinSession() async {
    // We wrap the entire logic that modifies providers in a post-frame callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Safety check: ensure the widget is still mounted when the callback runs.

      // --- 1. SETUP AUDIO SESSION FIRST (For iOS Backgrounding) ---
      if (!kIsWeb && Platform.isIOS) {
        Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioMode: AppleAudioMode.videoChat,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.mixWithOthers,
              AppleAudioCategoryOption.defaultToSpeaker
            }));
      }

      if (mounted) {
        // Now it is safe to call the method that modifies the provider's state.
        // We don't need to await it here, as the UI will react to the provider's
        // loading/data/error states.

        final sessionState = ref.read(mediaSessionProvider);

        // Only redirect if there's no active session AND we're not currently loading one.
        // If loading, let the build method show the loading indicator.
        if (sessionState.valueOrNull == null && !sessionState.isLoading) {
          GSLogger.log("No active session restored. Redirecting.");
          if (mounted) context.go('/dashboard/mediasetup');
          return;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    GSLogger.log("ClassroomWebInitializer: build()");

    // Its only job is to watch the provider and show the correct UI.

    final sessionState = ref.watch(mediaSessionProvider);

    // 2. We use `ref.listen` to perform SIDE EFFECTS (like navigation)
    //    when the state changes.
    ref.listen<AsyncValue<MediaSessionState>>(mediaSessionProvider,
        (previous, next) {
      // We only care about the transition to an error state.
      if (next is AsyncError) {
        GSLogger.log(
            "Initializer: Detected session failure. Navigating to login.");
        // Perform the navigation.
        context.go('/login');
      }
    });

    // 3. Return the PipWidget wrapper
    final Widget normalUI = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const ClassroomConnectWidgetWeb(),
        backgroundColor: Colors.grey.shade300,
        automaticallyImplyLeading: false,
        toolbarHeight: 10,
      ),
      body: sessionState.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                "Please hold while we connect to the user...",
                style: TextStyle(fontSize: 14, color: Colors.green),
              ),
            ],
          ),
        ),
        // This is the state if initialization fails.
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Error initializing session: $err'),
            ],
          ),
        ),
        // This is the state after a successful connection.
        data: (data) {
          GSLogger.log(
              "MediaSessionProvider has data. Building main classroom UI.");

          // 1. Check if we have a valid session.
          // If we are in the Classroom screen, we MUST be connected to signaling
          // OR have an active data connection.
          // If both are false, it means `rejoinPersistedSession` returned an empty state.
          final bool isValidSession =
              data.isSignalingConnected || data.isDataConnectionActive;

          if (!isValidSession) {
            GSLogger.log(
                "Classroom loaded with empty session. Redirecting to Setup.");

            // Trigger redirection
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/dashboard/mediasetup');
            });

            // Show a temporary loading/redirecting screen
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          GSLogger.log(
              "MediaSessionProvider has data. Building main classroom UI.");

          return Column(
            children: [
              // Hide toolbar when Google Doc tab is active
              const Expanded(child: WhiteboardCanvasContainerWeb()),
            ],
          );
        },
      ),
    );

    return normalUI;
  }


  Future<void> endSession(WidgetRef ref) async {
    GSLogger.info("ClassroomWebInitializer.endSession called ");

    // 2. Clear any active draft states.
    // 1. If sharing, stop it and notify peer.
    final mediaState = ref.read(mediaSessionProvider).valueOrNull;
    if (mediaState?.isLocalUserSharingScreen == true) {
      await ref.read(mediaSessionProvider.notifier).stopScreenShare();
    }
    // 2. Application-specific cleanup (this part is fine)
  }
}
