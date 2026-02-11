import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void d(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    if (error != null) {
      debugPrint('[Veil] $message | $error');
    } else {
      debugPrint('[Veil] $message');
    }
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    if (error != null) {
      debugPrint('[Veil][warn] $message | $error');
    } else {
      debugPrint('[Veil][warn] $message');
    }
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    if (error != null) {
      debugPrint('[Veil][error] $message | $error');
    } else {
      debugPrint('[Veil][error] $message');
    }
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
