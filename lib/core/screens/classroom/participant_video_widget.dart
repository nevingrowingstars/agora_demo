import 'package:agora_demo/core/screens/classroom/video_widget_state_enum.dart';
import 'package:agora_demo/core/state/device/canvas_boundary_service.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ParticipantVideoWidgetWeb extends ConsumerStatefulWidget {
  const ParticipantVideoWidgetWeb({super.key});

  @override
  ConsumerState<ParticipantVideoWidgetWeb> createState() =>
      _ParticipantVideoWidgetState();
}

class _ParticipantVideoWidgetState
    extends ConsumerState<ParticipantVideoWidgetWeb> {
  VideoWidgetState _currentViewState = VideoWidgetState.half;

  Offset position = const Offset(0, 0);
  // A flag to ensure we only set the initial position once.
  bool _isInitialPositionSet = false;
  bool _hasUserMovedWidget = false;
  bool minimize = false;
  double widgetHeight = 250;
  int _viewRefreshCounter = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only run this logic ONCE to set the starting position.
    if (!_isInitialPositionSet) {
      final screenSize = MediaQuery.sizeOf(context);

      // We need to know the dimensions to position it correctly.
      // Let's assume the default state is 'half'.
      double initialWidth = 240.0; // Same as your 'half' logic

      // Safety check for tiny screens (like PiP mode)
      if (screenSize.width < 400) return;

      const margin = 20.0; // Reduced margin to fit better

      setState(() {
        // Position it at Top-Right
        position = Offset(screenSize.width - initialWidth - margin, margin);
        _isInitialPositionSet = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Watch the single, unified provider to get the session state.
    final sessionState = ref.watch(mediaSessionProvider);
    final screenSize = MediaQuery.sizeOf(context);

    // 1. Determine size based on the current state
    double currentWidth;
    double currentHeight;

    switch (_currentViewState) {
      case VideoWidgetState.full:
        // Full Mode: Occupy ~20-25% of screen width (Sidebar style)
        // or fixed width like 300px.
        currentWidth = 300.0;

        // Height = (VideoHeight * 2) + Header + Padding
        // VideoHeight = Width * (9/16)
        final double singleVideoHeight = currentWidth * (9 / 16);
        currentHeight = (singleVideoHeight * 2) + 40 + 30 + 20;
        break;

      case VideoWidgetState.minimized:
        // Minimized: Just the header bar
        currentWidth = 240.0;
        currentHeight = 50.0;
        break;

      case VideoWidgetState.half:
        // Half Mode: Maybe slightly smaller width?
        currentWidth = 240.0;

        final double singleVideoHeight = currentWidth * (9 / 16);
        currentHeight = (singleVideoHeight * 2) + 40 + 30 + 20;
        break;
    }

    // --- 2. Determine the Position ---
    Offset finalPosition;

    if (_hasUserMovedWidget) {
      // CASE B: User has moved it manually -> Use stored position
      finalPosition = position;
    } else if (_currentViewState == VideoWidgetState.full) {
      // CASE A: Maximize Mode -> Always Center
      finalPosition = Offset(
        (screenSize.width - currentWidth) / 2,
        (screenSize.height - currentHeight) / 2,
      );

      position = Offset(
        (screenSize.width - currentWidth) / 2,
        (screenSize.height - currentHeight) / 2,
      );
    } else {
      // CASE C: Default / Initial State -> Top Right
      // Calculate the explicit offset for top-right instead of using Align
      // so we can use Positioned consistently.
      finalPosition = Offset(
        screenSize.width - currentWidth - 100, // 100 margin from right
        100, // 100 margin from top
      );
      position = Offset(
        screenSize.width - currentWidth - 100,
        100,
      );
    }

    // This contains your GestureDetector logic.
    final Widget content = GestureDetector(
      onPanStart: (details) {
        // Before we start moving, ensure 'position' matches where the widget ACTUALLY is.
        if (!_hasUserMovedWidget) {
          position = finalPosition;
          _hasUserMovedWidget = true; // Now we are in "Moved" mode
        }
      },
      onPanUpdate: (details) {
        setState(() {
          _hasUserMovedWidget = true; // Mark as moved!

          // Initialize position from current screen if this is the first move
          if (position == Offset.zero) {
            // Calculate default top-right position
            // (Screen Width - Widget Width - Margin)
            position = Offset(screenSize.width - currentWidth - 100, 100);
          }

          // Standard move logic
          final boundaryService = ref.read(canvasBoundaryServiceProvider);
          final Rect screenBounds =
              Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
          final Size widgetSize = Size(currentWidth, currentHeight);
          final Offset newPotentialPosition = position;

          position = boundaryService.clampVideoScreenPosition(
            position: newPotentialPosition,
            widgetSize: widgetSize,
            screenBounds: screenBounds,
          );
        });
      },
      onPanEnd: (details) {
        /*setState(() {
          _viewRefreshCounter++;
        });*/
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
            horizontal: currentWidth * 0.01, vertical: currentHeight * 0.03),
        curve: Curves.easeInOut,
        width: currentWidth,
        height: currentHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade800,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade800,
              offset: const Offset(2, 2),
              blurRadius: 12,
            ),
          ],
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          return Column(
            children: [
              

              // 2. Conditionally render the video and name content
              //if (_currentViewState != VideoWidgetState.minimized)
              // 3. Use Expanded to fill the remaining space flexibly
              Expanded(
                child: Visibility(
                  visible: _currentViewState != VideoWidgetState.minimized,
                  maintainState: true,
                  maintainSize: false,
                  maintainAnimation: true,
                  child: ClipRect(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        height: currentHeight - 40 - (currentHeight * 0.03 * 2),
                        child: sessionState.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (err, stack) =>
                              Center(child: Text("Error: $err")),
                          data: (data) => Column(
                            children: [
                              // ========== ROW 1: Remote Video ==========
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 5),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.black,
                                        width: 1),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ColoredBox(
                                      color: Colors
                                          .black, // ← Background to cover any gaps
                                      child: data.remoteVideoView ,
                                    ),
                                  ),
                                ),
                              ),

                              // ========== ROW 2: Remote Audio/Video Icons + Status ==========
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Top: Audio & Video toggles
                                    
                                    // Right: Online/Offline status
                                    _buildParticipantStatusBadge(
                                      onlineStatus:
                                          data?.isPeerPresentInRoom == true,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ========== ROW 3: Local Video ==========
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 5),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.grey.shade700, width: 1),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: ref
                                              .read(
                                                  mediaSessionProvider.notifier)
                                              .activeStrategy
                                              ?.localVideoView ??
                                          const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),

                              // ========== ROW 4: Local Audio/Video Icons + Status ==========
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Left: Audio & Video toggles
                                    Row(
                                      children: [
                                        _buildMediaToggleButton(
                                          isEnabled: data.isLocalAudioEnabled,
                                          enabledIcon: Icons.mic,
                                          disabledIcon: Icons.mic_off,
                                          enabledTooltip: 'Mute My Audio',
                                          disabledTooltip: 'Unmute My Audio',
                                          onTap: () {
                                            ref
                                                .read(mediaSessionProvider
                                                    .notifier)
                                                .toggleLocalAudio();
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _buildMediaToggleButton(
                                          isEnabled: data.isLocalVideoEnabled,
                                          enabledIcon: Icons.videocam,
                                          disabledIcon: Icons.videocam_off,
                                          enabledTooltip: 'Turn Off My Video',
                                          disabledTooltip: 'Turn On My Video',
                                          onTap: () {
                                            ref
                                                .read(mediaSessionProvider
                                                    .notifier)
                                                .toggleLocalVideo();
                                          },
                                        ),
                                      ],
                                    ),
                                    // Right: Online/Offline status
                                    _buildParticipantStatusBadge(
                                      onlineStatus: data.isSignalingConnected ||
                                          data.isDataConnectionActive,
                                    ),
                                  ],
                                ),
                              ),
                              // Bottom name row (approx 60 px)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );

    return Positioned(
      left: finalPosition.dx,
      top: finalPosition.dy,
      child: content,
    );
  }

  Widget _buildParticipantStatusBadge({required bool onlineStatus}) {
    return Container(
      width: 70,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        onlineStatus ? 'Online' : 'Offline',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  

  Widget _buildMediaToggleButton({
    required bool isEnabled,
    required IconData enabledIcon,
    required IconData disabledIcon,
    required String enabledTooltip,
    required String disabledTooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: isEnabled ? enabledTooltip : disabledTooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isEnabled
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isEnabled
                    ? Colors.green.withOpacity(0.5)
                    : Colors.red.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Icon(
              isEnabled ? enabledIcon : disabledIcon,
              size: 24,
              color: isEnabled ? Colors.green : Colors.red,
            ),
          ),
        ),
      ),
    );
  }
}
