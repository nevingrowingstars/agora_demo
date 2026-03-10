import 'package:agora_demo/core/model/media_availability_status.dart';
import 'package:agora_demo/core/screens/classroom/audio_input_selector_test_widget.dart';
import 'package:agora_demo/core/screens/classroom/audio_output_selector_test_widget.dart';
import 'package:agora_demo/core/screens/classroom/video_input_selector_test_widget.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/device/media_availability_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ClassroomMediaDeviceSetupWidget extends ConsumerStatefulWidget {
  const ClassroomMediaDeviceSetupWidget({Key? key}) : super(key: key);

  @override
  ConsumerState<ClassroomMediaDeviceSetupWidget> createState() =>
      _ClassroomMediaDeviceSetupWidgetState();
}

class _ClassroomMediaDeviceSetupWidgetState
    extends ConsumerState<ClassroomMediaDeviceSetupWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceListProvider.notifier).refreshDevices();
      ref.read(mediaAvailabilityStatusProvider.notifier).checkAvailability();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = ref.watch(deviceListProvider);
    final mediaStatus = ref.watch(mediaAvailabilityStatusProvider);

    // Show loading if devices not loaded yet
    if (deviceList.audioInputs.isEmpty &&
        deviceList.audioOutputs.isEmpty &&
        deviceList.videoInputs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media Availability Warning Banner
          if (mediaStatus.isChecking) _buildCheckingBanner(),

          if (!mediaStatus.isChecking && mediaStatus.hasIssues)
            _buildMediaWarningBanner(mediaStatus),

          // Retry Button
          if (!mediaStatus.isChecking && mediaStatus.hasIssues)
            _buildRetryButton(),  

          // --- Audio Input ---
          const AudioInputSelectorTestWidget(showJoinSwitch: true),

          SizedBox(height: 2),

          // --- Audio Output ---
          const AudioOutputSelectorTestWidget(),

          SizedBox(height: 2),

          // --- Video Input ---
          const VideoInputSelectorTestWidget(
            showJoinSwitch: true,
            showPreview: true,
          ),
          SizedBox(height: 2),

          
        ],
      ),
    );
  }

  Widget _buildCheckingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Checking media availability...',
            style: TextStyle(color: Colors.blue.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaWarningBanner(MediaAvailabilityStatus status) {
    final issues = <Widget>[];

    if (!status.audioAvailable && status.audioError != null) {
      issues.add(_buildIssueRow(
        icon: Icons.mic_off,
        iconColor: Colors.red,
        text: status.audioError!,
      ));
    }

    if (!status.videoAvailable && status.videoError != null) {
      issues.add(_buildIssueRow(
        icon: Icons.videocam_off,
        iconColor: Colors.red,
        text: status.videoError!,
      ));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'Media Device Issue',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Issues list
          ...issues,

          const SizedBox(height: 12),

          // Suggestion
          if (status.suggestion != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.suggestion!,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // External tool hint
          if (!status.anyMediaAvailable)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can join without audio/video and use Skype, Teams, or another tool for communication.',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIssueRow({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  

  Widget _buildRetryButton() {
    return Center(
      child: OutlinedButton.icon(
        onPressed: () {
          ref
              .read(mediaAvailabilityStatusProvider.notifier)
              .checkAvailability();
        },
        icon: const Icon(Icons.refresh),
        label: const Text('Retry Media Check'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange.shade700,
          side: BorderSide(color: Colors.orange.shade300),
        ),
      ),
    );
  }
}
