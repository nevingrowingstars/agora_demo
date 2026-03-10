import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:agora_demo/core/constants/app_constants.dart';
import 'package:agora_demo/core/screens/classroom/audio_settings_overlay_widget.dart';
import 'package:agora_demo/core/state/media/media_session_notifier.dart';
import 'package:agora_demo/core/state/router/router_provider.dart';
import 'package:agora_demo/core/util/app_logger_util.dart';
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'dart:io' show Platform;
import 'package:go_router/go_router.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

final GlobalKey canvasRepaintBoundaryKey = GlobalKey();

class WhiteboardCanvasWidget extends StatefulHookConsumerWidget {
  const WhiteboardCanvasWidget({super.key});

  @override
  ConsumerState<WhiteboardCanvasWidget> createState() =>
      _WhiteboardCanvasWidgetCanvasState();
}

class _WhiteboardCanvasWidgetCanvasState
    extends ConsumerState<WhiteboardCanvasWidget> {
  late Color selectedColor = Colors.black;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final FocusNode focusNode = useFocusNode();
    
    return Actions(
      // 1. Wrap everything with Actions.
      actions: <Type, Action<Intent>>{
        // Map the Intent to the Action that does the work.
        //CopyIntent: CopyAction(ref),
      },

      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          // 4. Map the key combination to your custom Intent.
        },
        child: Stack(
          children: [
            Focus(
              focusNode: focusNode,
              autofocus: true,
              child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                // 1. Define the canvas width based on the available space.
                //    We can use the full available width or give it some padding.

                final double totalWidth = constraints.maxWidth;
                final double canvasWidth = totalWidth;

                // The total height of the scaled canvas on the screen.
                final double scaledCanvasHeight =
                    AppConstants.universalCanvasSize.height;

                // 1. The top-level widget is the Scrollbar.
                return RepaintBoundary(
                  //key: _canvasKey,
                  key: canvasRepaintBoundaryKey,
                  child: Container(
                    //RESOLUTION FIX
                    width: canvasWidth,
                    height: scaledCanvasHeight,

                    color: Colors.white,
                    child: MouseRegion(
                      onHover: (event) {},
                      onExit: (event) {},
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        dragStartBehavior: DragStartBehavior.start,
                        onTapDown: (details) {
                          GSLogger.info(" onTapDown:  ");
                          focusNode.requestFocus();
                        },
                        onVerticalDragStart: (details) {},
                        onVerticalDragUpdate: (details) {
                          GSLogger.log("onVerticalDragUpdate");
                        },
                        onVerticalDragEnd: (details) {
                          GSLogger.log(" onVerticalDragEnd:  ");
                        },
                        onPanStart: (details) {
                          focusNode.requestFocus();
                          GSLogger.log(" onPanStart:  ");
                        },
                        onPanUpdate: (details) {
                          GSLogger.log(" onPanUpdate:  ");
                        },
                        onPanEnd: (details) {
                          GSLogger.log(" onPanEnd:  ");
                        },
                        onTapUp: (details) {
                          GSLogger.log("WBCanvas: onTapUp called");
                        },
                        child: Stack(
                          children: [
                            // Main Canvas
                            CustomPaint(
                              size: Size.infinite,
                              painter:
                                  WhiteBoardCanvasPainter(Colors.white, 2.0),
                            ),
                            // Top Right Buttons
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSettingsButton(context),
                                  const SizedBox(width: 8),
                                  _buildLogoutButton(context),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: () => AudioSettingsOverlayWidget.show(context),
      icon: const Icon(Icons.settings, size: 20),
      label: const Text("Settings"),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: () => _showLogoutConfirmation(context),
      icon: const Icon(Icons.logout, size: 20),
      label: const Text("Logout"),
    );
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    final bool? confirmLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Leave Session?"),
        content: const Text(
            "Your session will end and you will be disconnected."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Stay"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Leave"),
          ),
        ],
      ),
    );

    if (confirmLeave == true && context.mounted) {
      GSLogger.info("WhiteboardCanvas: User confirmed logout, leaving session.");
      // Set flag to skip router's onExit dialog
      ref.read(isExitApprovedProvider.notifier).state = true;
      await ref.read(mediaSessionProvider.notifier).leaveSession();
      if (context.mounted) {
        context.go('/');
      }
    }
  }

  @override
  void dispose() {
    // This method is called when the widget is about to be destroyed.
    GSLogger.log(
        "WhiteboardCanvas: Disposing. Cleaning up any active overlays.");

    // Call the superclass's dispose method at the end.
    super.dispose();
  }
}

class WhiteBoardCanvasPainter extends CustomPainter {
  Color? color;
  double? strokeWidth;

  WhiteBoardCanvasPainter(Color? color, double? strokeWidth) {
    this.color = color;
    this.strokeWidth = strokeWidth;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true
      ..strokeWidth = strokeWidth ?? 2;

    Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, bgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

