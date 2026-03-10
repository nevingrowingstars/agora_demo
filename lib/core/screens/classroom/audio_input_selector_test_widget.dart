import 'package:agora_demo/core/screens/classroom/mic_test_controller_web.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AudioInputSelectorTestWidget extends ConsumerStatefulWidget {
  const AudioInputSelectorTestWidget({
    super.key,
    this.showJoinSwitch = true,
  });

  final bool showJoinSwitch;

  @override
  ConsumerState<AudioInputSelectorTestWidget> createState() =>
      _AudioInputSelectorWithTestState();
}

class _AudioInputSelectorWithTestState
    extends ConsumerState<AudioInputSelectorTestWidget> {
  final MicTestController _micTestController = MicTestController();
  bool _isTestingMic = false;
  double _micLevel = 0.0;
  bool _micIsWorking = false;

  @override
  void initState() {
    super.initState();
    _micTestController.onLevelChanged = (level) {
      if (mounted) {
        setState(() => _micLevel = level);
      }
    };
    _micTestController.onMicStatusChanged = (isWorking) {
      if (mounted) {
        setState(() => _micIsWorking = isWorking);
      }
    };
  }

  @override
  void dispose() {
    _micTestController.dispose();
    super.dispose();
  }

  void _toggleMicTest() {
    if (_isTestingMic) {
      _stopMicTest();
    } else {
      _startMicTest();
    }
  }

  Future<void> _startMicTest() async {
    final selectedDeviceId =
        ref.read(deviceSelectionProvider).audioInputDeviceId;
    setState(() {
      _isTestingMic = true;
      _micIsWorking = false;
    });
    await _micTestController.startMicTest(selectedDeviceId);
  }

  Future<void> _stopMicTest() async {
    await _micTestController.stopMicTest();
    setState(() {
      _isTestingMic = false;
      _micLevel = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = ref.watch(deviceListProvider);
    final selectedDevices = ref.watch(deviceSelectionProvider);
    final selectedDeviceId =
        ref.watch(deviceSelectionProvider).audioInputDeviceId;

    final selectedAudioInput = deviceList.audioInputs.firstWhereOrNull(
      (device) => device.deviceId == selectedDevices.audioInputDeviceId,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(8.0),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Label ---
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Select Audio Input Device",
            ),
          ),

          SizedBox(height: 1),

          // --- ROW 1: Dropdown + Join with Microphone ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<MediaDeviceInfo>(
                  value: deviceList.audioInputs.firstWhereOrNull(
                    (d) => d.deviceId == selectedDeviceId,
                  ),
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.mic),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: deviceList.audioInputs.map((device) {
                    final label = device.label.isNotEmpty
                        ? device.label
                        : _generateDeviceLabel(device, deviceList.audioInputs);

                    return DropdownMenuItem<MediaDeviceInfo>(
                      value: device,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (device) async {
                    if (device != null) {
                      // 1. Update the provider state
                      ref
                          .read(deviceSelectionProvider.notifier)
                          .setAudioInputDevice(device.deviceId);

                      // 2. If session is active, switch device in the active session
                      try {
                        final mediaState = ref.read(mediaSessionProvider);
                        if (mediaState.hasValue && mediaState.value != null) {
                          await ref
                              .read(mediaSessionProvider.notifier)
                              .setAudioInputDevice(device.deviceId);
                          GSLogger.info(
                              "AudioInputSelector: Applied to active session");
                        }
                      } catch (e) {
                        GSLogger.error(
                            "AudioInputSelector: Error applying to session: $e");
                      }
                      // If testing, restart with new device
                      if (_isTestingMic) {
                        _stopMicTest();
                        _startMicTest();
                      }
                    }
                  },
                ),
              ),
            ],
          ),

          SizedBox(height: 1),

          // --- ROW 2: Test Mic + Status ---
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _toggleMicTest,
                icon: Icon(_isTestingMic ? Icons.stop : Icons.mic),
                label: Text(_isTestingMic ? "Stop" : "Test Mic"),
              ),
              SizedBox(width: 2),
              Expanded(
                child: _buildMicStatus(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Add helper method
  String _generateDeviceLabel(
      MediaDeviceInfo device, List<MediaDeviceInfo> allDevices) {
    if (device.label.isNotEmpty) return device.label;

    // Find index in list for numbering
    final index = allDevices.indexOf(device) + 1;

    switch (device.kind) {
      case 'audioinput':
        return 'Microphone $index';
      case 'audiooutput':
        return 'Speaker $index';
      case 'videoinput':
        return 'Camera $index';
      default:
        return 'Device $index';
    }
  }

  Widget _buildMicStatus(BuildContext context) {
    final selectedDeviceId =
        ref.watch(deviceSelectionProvider).audioInputDeviceId;
    final deviceList = ref.watch(deviceListProvider);
    final selectedDevice = deviceList.audioInputs.firstWhereOrNull(
      (d) => d.deviceId == selectedDeviceId,
    );
    final deviceName = selectedDevice?.label ?? 'Unknown';
    if (_isTestingMic && _micIsWorking) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "✔ Microphone is working!",
          ),
          
        ],
      );
    }

    if (_isTestingMic) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _micLevel,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _micLevel > 0.1 ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 0.5),
              Icon(
                _micLevel > 0.1 ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: _micLevel > 0.1 ? Colors.green : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 4),
          
        ],
      );
    }

    return Text(
      "Click 'Test Mic' to check your microphone.",
    );
  }
}
