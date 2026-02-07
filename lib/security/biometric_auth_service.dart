import 'dart:async';

import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  BiometricAuthService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  // prevents re-entrant auth calls (Windows Hello is sensitive)
  static bool _inProgress = false;

  /// Pre-warm: helps Windows Hello appear faster on first real call.
  static Future<void> warmUp() async {
    try {
      // Just query something lightweight.
      await _auth.isDeviceSupported();
      await _auth.canCheckBiometrics;
    } catch (_) {}
  }

  static Future<bool> isSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final can = await _auth.canCheckBiometrics;
      return supported || can;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasAvailableBiometrics() async {
    try {
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if biometric/OS auth succeeded.
  /// On Windows this triggers Windows Hello.
  static Future<bool> authenticate({required String reason}) async {
    if (_inProgress) return false;
    _inProgress = true;

    try {
      final supported = await isSupported();
      if (!supported) return false;

      // Some local_auth versions expose `authenticate` with different params.
      // This call signature is compatible with current stable local_auth.
      final ok = await _auth.authenticate(
        localizedReason: reason,
      );
      return ok;
    } catch (_) {
      return false;
    } finally {
      _inProgress = false;
    }
  }

  /// Small helper to avoid "first attempt weirdness" on some platforms.
  static Future<bool> authenticateWithRetry({required String reason}) async {
    final attemptOnce = await authenticate(reason: reason);
    if (attemptOnce) return true;

    // short delay and try again once (kept tiny)
    await Future.delayed(const Duration(milliseconds: 120));
    return authenticate(reason: reason);
  }
}
