import 'package:agora_demo/core/config/session_role_enum.dart';
import 'package:agora_demo/core/screens/classroom/classroom_media_device_setup_widget.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ClassroomDeviceSetupScreen extends ConsumerStatefulWidget {
  final SessionRole role;
  
  const ClassroomDeviceSetupScreen({
    super.key,
    required this.role,
  });

  @override
  ConsumerState<ClassroomDeviceSetupScreen> createState() =>
      _ClassroomDeviceSetupScreenState();
}

class _ClassroomDeviceSetupScreenState
    extends ConsumerState<ClassroomDeviceSetupScreen> {
      
  @override
  void initState() {
    super.initState();
  }

  void _joinClassroom() async {
    // 1. Get current user and peer
    try {
      // 2. Initialize Media Session using strategy from server/default
      await _startMediaSession();
      // 3. Navigate (For BOTH)
      if (mounted) context.go('/dashboard/classroom');
      // --- UNIFIED LOGIC END ---
    } catch (e) {
      GSLogger.log("Error joining classroom: $e");
    } finally {
    }
  }

  // Helper method to contain the shared media session logic.
  Future<void> _startMediaSession() async {
    final selectedDevices = ref.read(deviceSelectionProvider);
    // Call the single, proactive session start method.
    await ref.read(mediaSessionProvider.notifier).initializeAndStartSession(
          role: widget.role,
          selectedAudioDeviceId: selectedDevices.audioInputDeviceId,
          selectedVideoDeviceId: selectedDevices.videoInputDeviceId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 1,
          children: [
            SizedBox(height: 5),
            Text(
              'Are These Settings Correct?',
              style: TextStyle(
                fontSize: 22,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 5),
            Text(
              "Check your camera, mic, and audio are working correctly. If you have any questions or issues before entering the classroom, use the chat to connect instantly with your tutor or support.",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            Expanded(
              child: Row(
                spacing: 1,
                children: const [
                  Expanded(flex: 6, child: ClassroomMediaDeviceSetupWidget()),
                ],
              ),
            ),
            // Join Button (Unified Logic)
            Padding(
              padding: const EdgeInsets.only(bottom: 100, top: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _joinClassroom,
                    icon: Icon(Icons.arrow_forward),
                    label: Text('Join Classroom'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/'),
                    icon: Icon(Icons.exit_to_app),
                    label: Text('Exit'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      backgroundColor: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
