import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../security/owner_auth_flow.dart';
import '../security/reset_setup_service.dart';
import '../security/secure_gate.dart';
import '../security/unlock_service.dart';
import '../widgets/background_scaffold.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  Future<void> _goToOnboardingReset(BuildContext context) async {
    await ResetSetupService().resetOnboardingAndPolicies();
    if (!context.mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.onboarding,
      (route) => false,
    );
  }

  Future<void> _unlockApp(BuildContext context) async {
    final ctx = context;

    final requireAppUnlock = await UnlockService().isAppUnlockRequired();
    if (!ctx.mounted) return;
    if (!requireAppUnlock) {
      SecureGate.unlockSession();
      Navigator.pushNamedAndRemoveUntil(
        ctx,
        AppRoutes.inbox,
        (route) => false,
      );
      return;
    }

    // If panic is active, go to panic screen
    bool panic = false;
    try {
      panic = await UnlockService().isGlobalPanicActive();
    } catch (_) {
      panic = false;
    }

    if (!ctx.mounted) return;

    if (panic) {
      Navigator.pushNamedAndRemoveUntil(ctx, AppRoutes.panic, (r) => false);
      return;
    }

    // Hello only here (app entry)
    bool ok = false;
    try {
      ok = await OwnerAuthFlow.ensureOwnerSessionUnlocked(ctx);
    } catch (_) {
      ok = false;
    }

    if (!ctx.mounted) return;

    if (ok) {
      Navigator.pushNamedAndRemoveUntil(
        ctx,
        AppRoutes.inbox,
        (route) => false,
      );
      return;
    }

    // Fallback to PIN when biometrics are unavailable or fail
    final unlock = UnlockService();
    final hasPass = await unlock.hasPassphrase();
    if (!ctx.mounted) return;

    if (!hasPass) {
      SecureGate.unlockSession();
      Navigator.pushNamedAndRemoveUntil(
        ctx,
        AppRoutes.inbox,
        (route) => false,
      );
      return;
    }

    final pin = await _askPin(ctx);
    if (pin == null || pin.trim().isEmpty) return;

    final okPin = await unlock.verifyPassphrase(pin.trim());
    if (!ctx.mounted) return;
    if (!okPin) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Wrong PIN.')),
      );
      return;
    }

    SecureGate.unlockSession();
    Navigator.pushNamedAndRemoveUntil(
      ctx,
      AppRoutes.inbox,
      (route) => false,
    );
  }

  Future<String?> _askPin(BuildContext context) async {
    var pinText = '';

    final res = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return MediaQuery.removeViewInsets(
          context: dctx,
          removeBottom: true,
          child: AlertDialog(
            title: const Text(''),
            content: TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'PIN'),
              onChanged: (v) => pinText = v,
              onSubmitted: (_) => Navigator.pop(dctx, pinText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, pinText),
                child: const Text('Unlock'),
              ),
            ],
          ),
        );
      },
    );
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return BackgroundScaffold(
      style: VeilBackgroundStyle.lock,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, color: fg, size: 52),
                const SizedBox(height: 16),
                Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Unlock the app to access inbox.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: muted),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _unlockApp(context),
                    child: const Text('Unlock'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _goToOnboardingReset(context),
                  child: Text(
                    'Back to onboarding',
                    style: TextStyle(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
