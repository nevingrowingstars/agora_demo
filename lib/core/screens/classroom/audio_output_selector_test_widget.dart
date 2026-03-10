import 'package:agora_demo/core/screens/classroom/audio_output_check_widget.dart';
import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AudioOutputSelectorTestWidget extends ConsumerStatefulWidget {
  const AudioOutputSelectorTestWidget({super.key});

  @override
  ConsumerState<AudioOutputSelectorTestWidget> createState() =>
      _AudioOutputSelectorWithTestState();
}

class _AudioOutputSelectorWithTestState
    extends ConsumerState<AudioOutputSelectorTestWidget> {
  @override
  Widget build(BuildContext context) {
    final deviceList = ref.watch(deviceListProvider);
    final selectedDevices = ref.watch(deviceSelectionProvider);

    final selectedAudioOutput = deviceList.audioOutputs.firstWhereOrNull(
      (device) => device.deviceId == selectedDevices.audioOutputDeviceId,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.blue,
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
              "Select Audio Output Device",
              
            ),
          ),

          SizedBox(height: 1),

          // --- ROW 1: Dropdown ---
          DropdownButtonFormField<MediaDeviceInfo>(
            value: selectedAudioOutput,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.volume_up),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            items: deviceList.audioOutputs.map((device) {
              return DropdownMenuItem<MediaDeviceInfo>(
                value: device,
                child: Text(
                  device.label.isNotEmpty
                      ? device.label
                      : 'Speaker ${deviceList.audioOutputs.indexOf(device) + 1}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (device) async {
              if (device != null) {
                // 1. Update the provider state
                ref
                    .read(deviceSelectionProvider.notifier)
                    .setAudioOutputDevice(device.deviceId);

                // 2. If session is active, switch device in the active session
                try {
                  final mediaState = ref.read(mediaSessionProvider);
                  if (mediaState.hasValue && mediaState.value != null) {
                    GSLogger.info(
                        "AudioOutputSelector: Applying to active session...");
                    await ref
                        .read(mediaSessionProvider.notifier)
                        .setAudioOutputDevice(device.deviceId);
                    GSLogger.info(
                        "AudioOutputSelector: Applied to active session");
                  }
                } catch (e) {
                  GSLogger.error(
                      "AudioOutputSelector: Error applying to session: $e");
                }
              }
            },
          ),

          SizedBox(height: 1),

          // --- ROW 2: Play Audio + Status ---
          Row(
            children: [
              AudioOutputCheckWidget(),

              SizedBox(width: 2),

              Expanded(
                child: Text(
                  "Click 'Play Audio' to test speaker.",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}