import 'dart:ui';

class AppConstants {
  static const double defaultFontSize = 14.0;
  static const double lineHeight = 1.5; // average multiplier

  static const double initialHeight =
      defaultFontSize * lineHeight * 3 + 16; // Add padding
  static const double defaultPageBreakHeight = 800;

  static const double DEFAULT_PENCIL_STROKE_WIDTH = 2.0;

  static const double kCanvasScrollbarWidth = 50.0;

  static const Size universalCanvasSize = Size(1875, 3750);

  static const Size pageBreakCanvasSize = Size(1500, 3750);
  static const double PAGE_BREAK_HEIGHT = 15.0;

  /// Timeout duration for tool sessions (3 hours).
  static const Duration kToolSessionTimeout = Duration(hours: 3);
  // Set your timeout. 30 mins? 1 hour?
  static const double SESSION_EXPIRY_IN_MINS = 30.0;
}
