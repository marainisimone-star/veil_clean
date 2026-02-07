import 'package:flutter/material.dart';

import '../services/audit_log_service.dart';
import 'biometric_auth_service.dart';
import 'secure_gate.dart';

class OwnerAuthFlow {
  OwnerAuthFlow._();

  /// Always require owner-auth (Windows Hello) when requested.
  static Future<bool> ensureOwnerSessionUnlocked(BuildContext context) async {
    if (SecureGate.isPanicActive) return false;

    final supported = await BiometricAuthService.isSupported();
    final hasBio = supported && await BiometricAuthService.hasAvailableBiometrics();

    SecureGate.beginOwnerAuth();
    try {
      bool ok = false;
      if (hasBio) {
        ok = await BiometricAuthService.authenticate(reason: 'Unlock');
      } else {
        // No biometrics available (e.g., Android emulator) -> allow PIN flow
        ok = true;
      }
      if (!ok) {
        await AuditLogService.I.log('owner_auth', status: 'failed');
        return false;
      }

      SecureGate.unlockSession();
      await AuditLogService.I.log('owner_auth', status: 'ok');
      return true;
    } finally {
      SecureGate.endOwnerAuth();
    }
  }

  /// Panic recovery: allow owner-auth even if panic is active.
  static Future<bool> ensureOwnerSessionUnlockedForPanic(
      BuildContext context) async {
    final supported = await BiometricAuthService.isSupported();
    final hasBio = supported && await BiometricAuthService.hasAvailableBiometrics();

    SecureGate.beginOwnerAuth();
    try {
      bool ok = false;
      if (hasBio) {
        ok = await BiometricAuthService.authenticate(reason: 'Unlock');
      } else {
        ok = true;
      }
      if (!ok) {
        await AuditLogService.I.log('owner_auth_panic', status: 'failed');
        return false;
      }

      SecureGate.unlockSession();
      await AuditLogService.I.log('owner_auth_panic', status: 'ok');
      return true;
    } finally {
      SecureGate.endOwnerAuth();
    }
  }
}
