import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_storage.dart';
import '../routes/app_routes.dart';
import '../security/biometric_auth_service.dart';
import '../security/unlock_service.dart';
import '../security/secure_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_backend.dart';

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  static const String _kSetupDone = 'veil_setup_done_v1';

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    // Pre-warm biometrics (helps Windows Hello show faster later)
    try {
      await BiometricAuthService.warmUp();
    } catch (_) {}

    final unlock = UnlockService();

    bool panicActive = false;
    try {
      panicActive = await unlock.isGlobalPanicActive();
    } catch (_) {
      panicActive = false;
    }

    if (!mounted) return;

    if (panicActive) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.panic, (r) => false);
      return;
    }

    bool hasPin = false;
    try {
      hasPin = await unlock.hasPassphrase();
    } catch (_) {
      hasPin = false;
    }

    bool setupDone = false;
    try {
      setupDone = (LocalStorage.getString(_kSetupDone) == '1');
    } catch (_) {
      setupDone = false;
    }

    if (!mounted) return;

    if (setupDone && hasPin) {
      final firebaseSupported =
          kIsWeb ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows;
      if (firebaseSupported) {
        try {
          await FirebaseBackend.I.init();
        } catch (_) {
          // If Firebase init fails, fall back to auth screen so user can retry.
        }
        if (!mounted) return;
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
          Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (r) => false);
          return;
        }
      }
      final requireAppUnlock = await unlock.isAppUnlockRequired();
      if (!mounted) return;
      if (requireAppUnlock) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.lock, (r) => false);
      } else {
        SecureGate.unlockSession();
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.inbox, (r) => false);
      }
      return;
    }

    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.onboarding, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator()),
      ),
    );
  }
}
