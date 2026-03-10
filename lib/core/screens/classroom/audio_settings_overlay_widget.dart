import 'package:agora_demo/core/screens/classroom/audio_input_selector_test_widget.dart';
import 'package:agora_demo/core/screens/classroom/audio_output_selector_test_widget.dart';
import 'package:agora_demo/core/screens/classroom/video_input_selector_test_widget.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AudioSettingsOverlayWidget extends ConsumerStatefulWidget {
  const AudioSettingsOverlayWidget({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AudioSettingsOverlayWidget(),
    );
  }

  @override
  ConsumerState<AudioSettingsOverlayWidget> createState() =>
      _AudioSettingsOverlayWidgetState();
}

class _AudioSettingsOverlayWidgetState
    extends ConsumerState<AudioSettingsOverlayWidget> {
  bool _isLoading = true;
  bool _isSessionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDevices();
      _checkSessionStatus();
    });
  }

  void _checkSessionStatus() {
    final mediaState = ref.read(mediaSessionProvider);
    setState(() {
      _isSessionActive = mediaState.hasValue && mediaState.value != null;
    });
    GSLogger.info("AudioSettingsOverlay: Session active: $_isSessionActive");
  }

  Future<void> _loadDevices() async {
    try {
      await ref.read(deviceListProvider.notifier).refreshDevices();
      final deviceList = ref.read(deviceListProvider);
      GSLogger.info(
          "AudioSettingsOverlay: Loaded ${deviceList.audioInputs.length} audio inputs");
      GSLogger.info(
          "AudioSettingsOverlay: Loaded ${deviceList.audioOutputs.length} audio outputs");
      GSLogger.info(
          "AudioSettingsOverlay: Loaded ${deviceList.videoInputs.length} video inputs");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = ref.watch(deviceListProvider);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Loading devices..."),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Header ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Audio & Video Settings",
                          
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),

                    // Show info if session is active
                    if (_isSessionActive) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Changes will be applied to your active session immediately.",
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: 2),

                    // --- Audio Input ---
                    const AudioInputSelectorTestWidget(showJoinSwitch: false),

                    SizedBox(height: 2),

                    // --- Audio Output ---
                    const AudioOutputSelectorTestWidget(),

                    SizedBox(height: 2),

                    // --- Video Input ---
                    const VideoInputSelectorTestWidget(
                      showJoinSwitch: false,
                      showPreview: true,
                      showVideoStatus: false,
                    ),

                    SizedBox(height: 2),
                    // --- Done Button ---
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Done"),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
