import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../routes/app_routes.dart';
import '../security/secure_gate.dart';
import '../security/unlock_service.dart';
import '../widgets/background_scaffold.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text.trim();
      if (email.isEmpty || pass.isEmpty) {
        setState(() => _error = 'Email and password required.');
        return;
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      await _goNext();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text.trim();
      if (email.isEmpty || pass.isEmpty) {
        setState(() => _error = 'Email and password required.');
        return;
      }
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      await _goNext();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Registration failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goNext() async {
    final requireAppUnlock = await UnlockService().isAppUnlockRequired();
    if (!mounted) return;
    if (requireAppUnlock) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.lock, (r) => false);
    } else {
      SecureGate.unlockSession();
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.inbox, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return BackgroundScaffold(
      style: VeilBackgroundStyle.inbox,
      appBar: AppBar(
        title: Text('Sign in', style: TextStyle(color: fg)),
        foregroundColor: fg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _signIn,
                    child: Text(_busy ? 'Please wait…' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _register,
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Use your Firebase email/password.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
