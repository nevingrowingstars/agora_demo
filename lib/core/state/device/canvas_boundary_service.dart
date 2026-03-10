import 'dart:math';
import 'dart:ui';

import 'package:hooks_riverpod/hooks_riverpod.dart';

final screenDimensionsProvider = StateProvider<Size>((ref) {
  //return const Size(1280, 720);
  return const Size(1875, 3750);
});

class CanvasBoundaryService {
  final Ref _ref;

  CanvasBoundaryService(this._ref);

  
  Offset clampVideoScreenPosition({
    required Offset position,
    required Size widgetSize,
    required Rect screenBounds,
    double visibleThreshold = 50.0, // How many pixels must remain visible
  }) {
    // Calculate the maximum allowable coordinates for the widget's TOP-LEFT corner.
    final double maxDx = screenBounds.right - widgetSize.width;
    final double maxDy = screenBounds.bottom - widgetSize.height;

    // The minimum allowable coordinates are the screen's top-left.
    final double minDx = screenBounds.left; // Usually 0
    final double minDy = screenBounds.top; // Usually 0

    // Clamp the proposed position using these precise boundaries.
    final double clampedDx = position.dx.clamp(minDx, maxDx);
    final double clampedDy = position.dy.clamp(minDy, maxDy);

    return Offset(clampedDx, clampedDy);
  }

}
final canvasBoundaryServiceProvider = Provider((ref) {
  return CanvasBoundaryService(ref);
});
