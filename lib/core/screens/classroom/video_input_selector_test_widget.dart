import 'package:agora_demo/core/state/device/device_selection_provider.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:agora_demo/core/util/video_constraints_helper.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class VideoInputSelectorTestWidget extends ConsumerStatefulWidget {
  const VideoInputSelectorTestWidget({
    super.key,
    this.showJoinSwitch = true,
    this.showPreview = true,
    this.showVideoStatus = true,
  });

  final bool showJoinSwitch;
  final bool showPreview;
  final bool showVideoStatus;

  @override
  ConsumerState<VideoInputSelectorTestWidget> createState() =>
      _VideoInputSelectorWithPreviewState();
}

class _VideoInputSelectorWithPreviewState
    extends ConsumerState<VideoInputSelectorTestWidget> {
  RTCVideoRenderer? _localRenderer;
  MediaStream? _localStream;

  // Store the actual device being used for verification
  String? _actualDeviceLabel;
  String? _actualDeviceId;
  bool _hasLoggedDevices = false;

  @override
  void initState() {
    super.initState();
    if (widget.showPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeRenderer();
      });
    }
  }

  Future<void> _initializeRenderer() async {
    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
    await _startVideoPreview();
  }

  Future<void> _startVideoPreview() async {
    if (!mounted) return;
    final deviceId = ref.read(deviceSelectionProvider).videoInputDeviceId;

    GSLogger.info("=== VideoInputSelector: _startVideoPreview ===");
    GSLogger.info("  Requested deviceId: $deviceId");

    try {
      // Build constraints with device ID

      final videoConstraints = VideoConstraintsHelper.getConstraints(deviceId: deviceId);

      final constraints = <String, dynamic>{
        'audio': false,
        'video': videoConstraints,
      };

      /*final constraints = <String, dynamic>{
        'audio': false,
        'video':
            deviceId != null && deviceId.isNotEmpty && deviceId != 'default'
                ? {
                    'deviceId': {
                      'exact': deviceId
                    }, // Use 'exact' to force specific device
                    'width': {'ideal': 1280},
                    'height': {'ideal': 720},
                  }
                : {
                    'width': {'ideal': 1280},
                    'height': {'ideal': 720},
                  },
      };*/
      GSLogger.info("  Constraints: $constraints");

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      // Log the actual video track being used
      final videoTrack = _localStream?.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        _actualDeviceLabel = videoTrack.label;

        GSLogger.info("=== VideoInputSelector: Got Video Track ===");
        GSLogger.info("  Track ID: ${videoTrack.id}");
        GSLogger.info(
            "  Track Label: ${videoTrack.label}"); // Shows actual device name
        GSLogger.info("  Track Kind: ${videoTrack.kind}");
        GSLogger.info("  Track Enabled: ${videoTrack.enabled}");
        GSLogger.info("  Track Muted: ${videoTrack.muted}");

        // Try to get settings
        try {
          final settings = videoTrack.getSettings();
          _actualDeviceId = settings['deviceId'] as String?;
          GSLogger.info("  Track Settings: $settings");
        } catch (e) {
          GSLogger.info("  Track Settings: (not available)");
        }
      }

      _localRenderer?.srcObject = _localStream;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      GSLogger.error("Error starting video preview: $e");
    }
  }

  Future<void> _stopVideoPreview() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      await _localStream!.dispose();
      _localStream = null;
    }
    _localRenderer?.srcObject = null;
    _actualDeviceLabel = null;
    _actualDeviceId = null;
  }

  @override
  void dispose() {
    _stopVideoPreview();
    _localRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceList = ref.watch(deviceListProvider);
    final selectedDevices = ref.watch(deviceSelectionProvider);
    final selectedDeviceId = selectedDevices.videoInputDeviceId;

    final selectedVideoInput = deviceList.videoInputs.firstWhereOrNull(
      (device) => device.deviceId == selectedDevices.videoInputDeviceId,
    );

    // Log devices only once
    if (!_hasLoggedDevices && deviceList.videoInputs.isNotEmpty) {
      _hasLoggedDevices = true;
      GSLogger.info(
          "VideoInputSelector: Available devices: ${deviceList.videoInputs.length}");
      for (var d in deviceList.videoInputs) {
        GSLogger.info("  - ${d.label} (${d.deviceId})");
      }
      GSLogger.info(
          "VideoInputSelector: Selected device ID: $selectedDeviceId");
    }

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
              "Select Video Input Device",
              
            ),
          ),

          SizedBox(height: 1),

          // --- ROW 1: Dropdown + Switch + Preview ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<MediaDeviceInfo>(
                  value: selectedVideoInput,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.videocam),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: deviceList.videoInputs.map((device) {
                    return DropdownMenuItem<MediaDeviceInfo>(
                      value: device,
                      child: Text(
                        device.label.isNotEmpty
                            ? device.label
                            : 'Camera ${deviceList.videoInputs.indexOf(device) + 1}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (device) async {
                    if (device != null) {
                      GSLogger.info(
                          "VideoInputSelector: Selected device: ${device.label} (${device.deviceId})");

                      // 1. Update the provider state
                      ref
                          .read(deviceSelectionProvider.notifier)
                          .setVideoInputDevice(device.deviceId);

                      // 2. If session is active, switch device in the active session
                      try {
                        final mediaState = ref.read(mediaSessionProvider);
                        if (mediaState.hasValue && mediaState.value != null) {
                          GSLogger.info(
                              "VideoInputSelector: Applying to active session...");
                          await ref
                              .read(mediaSessionProvider.notifier)
                              .setVideoInputDevice(device.deviceId);
                          GSLogger.info(
                              "VideoInputSelector: Applied to active session");
                        }
                      } catch (e) {
                        GSLogger.error(
                            "VideoInputSelector: Error applying to session: $e");
                      }

                      // 3. Restart video preview if active
                      if (widget.showPreview && _localRenderer != null) {
                        await _stopVideoPreview();
                        await _startVideoPreview();
                      }
                    }
                  },
                ),
              ),

              if (widget.showJoinSwitch) ...[
                SizedBox(width: 2),
                // Join with Camera Switch
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Join with camera",
                      
                    ),
                    SizedBox(width: 0.5),
                    Switch(
                      value: selectedDevices.isVideoEnabledOnJoin,
                      onChanged: (isEnabled) => ref
                          .read(deviceSelectionProvider.notifier)
                          .setVideoEnabled(isEnabled),
                    ),
                    SizedBox(width: 0.5),
                  ],
                ),
              ],

              // --- Video Preview Section ---
              if (widget.showPreview) ...[
                SizedBox(height: 1, width: 1,),
                // Video Preview Container
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _localRenderer != null && _localStream != null
                      ? RTCVideoView(
                          _localRenderer!,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                ),

                // Device status text below the preview
                SizedBox(width: 0.5,height: 0.5),
                if (widget.showVideoStatus)
                  _buildCameraStatus(context),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraStatus(BuildContext context) {
    if (_actualDeviceLabel != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "✔ Camera is working!",
            
          ),
          Text(
            "Using: $_actualDeviceLabel",
            
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return Text(
      "Loading camera preview...",
      
    );
  }
}
