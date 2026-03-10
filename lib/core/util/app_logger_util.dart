import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

enum GSLogLevel {
  debug,
  info,
  warning,
  error,
  none, // disable all logs
}

class GSLogger {
  static final DateFormat _formatter = DateFormat('HH:mm:ss.SSS');

  /// Change this at runtime if needed
  static GSLogLevel _currentLevel = kDebugMode ? GSLogLevel.debug : GSLogLevel.error;

  static void setLevel(GSLogLevel level) {
    _currentLevel = level;
  }

  static bool _shouldLog(GSLogLevel level) {
    if (_currentLevel == GSLogLevel.none) return false;
    // We log only if the message level is >= currentLevel
    return level.index >= _currentLevel.index;
  }

  static Future<File> get _logFile async {
    try {
      Directory? directory;

      // iOS/macOS may throw if the directory is not available
      directory = await getApplicationSupportDirectory();

      // Ensure directory exists
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final separator = Platform.pathSeparator;
      final path = '${directory.path}${separator}gswhiteboard_log.txt';
      return File(path);
    } catch (e) {
      //if (kDebugMode) {
      print('Log directory fetch failed: $e');
      //}
      // Fallback to temp directory
      final fallbackDir = await getTemporaryDirectory();
      final separator = Platform.pathSeparator;
      final path = '${fallbackDir.path}${separator}gswhiteboard_log.txt';
      return File(path);
    }
  }

  /// Lowest-level (verbose) logging – old `log()` now maps to DEBUG.
  static Future<void> log(String message) => debug(message);

  static Future<void> debug(String message) =>
      _log(message, GSLogLevel.debug);

  static Future<void> info(String message) =>
      _log(message, GSLogLevel.info);

  static Future<void> warning(String message) =>
      _log(message, GSLogLevel.warning);

  static Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' | error: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return _log(buffer.toString(), GSLogLevel.error);
  }

  static Future<void> _log(String message, GSLogLevel level) async {
    if (!_shouldLog(level)) return;

    final DateTime now = DateTime.now();
    final String timestamp = _formatter.format(now);
    final String levelStr = level.toString().split('.').last.toUpperCase();

    final line = '[$timestamp][$levelStr] $message';

    try {
      // Always print to console
      print(line);

      if (kIsWeb) {
        // On web we just use the console
        return;
      }

      final file = await _logFile;
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      if (kDebugMode) {
        print('Log write failed: $e');
      }
    }
  }

  static Future<void> logPrev(String message) async {
    try {
      
      print(message);
      
      if (kIsWeb) {
        // Web fallback: use browser console
        //if (kDebugMode)
        // 1. Get the current time.
        final DateTime now = DateTime.now();

        // 2. Format the time into a string.
        final String timestamp = _formatter.format(now);

        // 3. Prepend the timestamp to your message.
        print('WEB LOG [$timestamp]: $message');
        return;
      }

      final file = await _logFile;
      await file.writeAsString('$message\n',
          mode: FileMode.append, flush: true);
    } catch (e) {
      if (kDebugMode) {
        print('Log write failed: $e');
      }
    }
  }
}
