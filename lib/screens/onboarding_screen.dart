import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../data/contact_repository.dart';
import '../data/local_storage.dart';
import '../models/contact.dart';
import '../routes/app_routes.dart';
import '../security/unlock_service.dart';
import '../security/unlock_profile.dart';
import '../widgets/background_scaffold.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const String _kSetupDone = 'veil_setup_done_v1';
  static const String _kOwnerName = 'veil_owner_name_v1';
  static const String _kOwnerPhoto = 'veil_owner_photo_b64_v1';

  final _unlock = UnlockService();
  final _contacts = ContactRepository();

  final _pinCtrl = TextEditingController();
  final _panicCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  UnlockProfile _unlockProfile = UnlockProfile.defaults();
  bool _requireAppUnlock = false;
  String? _ownerPhotoB64;

  bool _busy = false;
  bool _hasExistingPin = false;

  @override
  void initState() {
    super.initState();
    _warm();
  }

  Future<void> _warm() async {
    try {
      final has = await _unlock.hasPassphrase();
      if (!mounted) return;
      final profile = await UnlockProfile.load();
      final requireUnlock = await _unlock.isAppUnlockRequired();
      if (!mounted) return;
      setState(() {
        _hasExistingPin = has;
        _unlockProfile = profile;
        _requireAppUnlock = requireUnlock;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasExistingPin = false);
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _panicCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final pin = _pinCtrl.text.trim();
      final panic = _panicCtrl.text.trim();

      if (!_hasExistingPin) {
        if (pin.length < 4) {
          _toast('PIN too short (min 4).');
          return;
        }
        await _unlock.setPassphrase(pin);
      } else {
        if (pin.isNotEmpty) {
          final ok = await _unlock.verifyPassphrase(pin);
          if (!ok) {
            _toast('Wrong PIN.');
            return;
          }
        }
      }

      if (panic.isNotEmpty) {
        if (panic.length < 4) {
          _toast('Panic PIN too short (min 4).');
          return;
        }
        await _unlock.setPanicPassphrase(panic);
      }

      final ownerName = _ownerNameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();

      if (ownerName.isNotEmpty) {
        final c = Contact(
          id: _contacts.newId(),
          coverName: ownerName,
          coverEmoji: null,
          realName: ownerName,
          realEmoji: null,
          phone: phone.isEmpty ? null : phone,
          mode: ContactMode.plain,
          category: ContactCategory.private, // required
          photoB64: _ownerPhotoB64,
        );
        await _contacts.upsert(c);
      }

      await _unlockProfile.save();
      await _unlock.setAppUnlockRequired(_requireAppUnlock);
      await LocalStorage.setString(_kOwnerName, ownerName);
      if (_ownerPhotoB64 != null && _ownerPhotoB64!.trim().isNotEmpty) {
        await LocalStorage.setString(_kOwnerPhoto, _ownerPhotoB64!.trim());
      } else {
        await LocalStorage.remove(_kOwnerPhoto);
      }
      await LocalStorage.setString(_kSetupDone, '1');

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.lock, (r) => false);
    } catch (_) {
      _toast('Done.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        backgroundColor: scheme.surface,
      ),
    );
  }

  Future<void> _pickOwnerPhoto() async {
    final xf = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
        ),
      ],
    );
    if (xf == null) return;
    final bytes = await xf.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() => _ownerPhotoB64 = base64Encode(bytes));
  }

  void _clearOwnerPhoto() {
    setState(() => _ownerPhotoB64 = null);
  }

  ImageProvider? _ownerPhotoProvider() {
    final raw = _ownerPhotoB64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
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
        title: Text('Setup', style: TextStyle(color: fg)),
        foregroundColor: fg,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _card(
              title: 'Security',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require authentication on app open'),
                    value: _requireAppUnlock,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _requireAppUnlock = v),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _hasExistingPin ? 'PIN (optional)' : 'Set PIN (min 4)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _panicCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Panic PIN (optional)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              title: 'Owner profile (optional)',
              child: Column(
                children: [
                  TextField(
                    controller: _ownerNameCtrl,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.primary.withAlpha((0.12 * 255).round()),
                        backgroundImage: _ownerPhotoProvider(),
                        child: _ownerPhotoProvider() == null
                            ? const Icon(Icons.person_outline)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _ownerPhotoB64 == null ? 'No profile photo' : 'Profile photo set',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _pickOwnerPhoto,
                        child: const Text('Choose'),
                      ),
                      if (_ownerPhotoB64 != null)
                        TextButton(
                          onPressed: _busy ? null : _clearOwnerPhoto,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Category is managed in Contacts (Private / Business).',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _finish,
                child: Text(_busy ? 'Please wait…' : 'Finish'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withAlpha((0.45 * 255).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
