import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import 'owner_auth_flow.dart';
import 'panic_controller.dart';
import 'unlock_service.dart';

class PanicLockScreen extends StatelessWidget {
  const PanicLockScreen({super.key, required this.reason});

  final PanicReason reason;

  String _reasonLabel(PanicReason r) {
    switch (r) {
      case PanicReason.userPressed:
        return 'Sessione bloccata';
      case PanicReason.tooManyAttempts:
        return 'Sessione bloccata';
      case PanicReason.appBackgrounded:
        return 'Sessione bloccata';
      case PanicReason.tamperDetected:
        return 'Sessione bloccata';
      case PanicReason.timeout:
        return 'Sessione bloccata';
      case PanicReason.unknown:
        return 'Sessione bloccata';
    }
  }

  Future<void> _unlock(BuildContext context) async {
    final okOwner = await OwnerAuthFlow.ensureOwnerSessionUnlockedForPanic(context);
    if (!okOwner) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Done.')),
      );
      return;
    }

    final unlock = UnlockService();
    final hasPass = await unlock.hasPassphrase();

    if (!context.mounted) return;

    if (!hasPass) {
      await unlock.clearGlobalPanic();
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.inbox, (r) => false);
      return;
    }

    final pin = await _askPin(context);
    if (pin == null || pin.trim().isEmpty) return;

    final okPin = await unlock.verifyPassphrase(pin.trim());
    if (!okPin) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong PIN.')),
      );
      return;
    }

    await unlock.clearGlobalPanic();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.inbox, (r) => false);
  }

  Future<String?> _askPin(BuildContext context) async {
    final ctrl = TextEditingController();

    final res = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dctx) {
        return AlertDialog(
          title: const Text(''),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'PIN'),
            onSubmitted: (_) => Navigator.pop(dctx, ctrl.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );

    ctrl.dispose();
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.lock, size: 40, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'Sessione bloccata',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                _reasonLabel(reason),
                style: const TextStyle(fontSize: 14, height: 1.3, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              const Text(
                'Per continuare serve re-autenticazione.',
                style: TextStyle(fontSize: 14, height: 1.35, color: Colors.white70),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _unlock(context),
                  child: const Text('Unlock'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
