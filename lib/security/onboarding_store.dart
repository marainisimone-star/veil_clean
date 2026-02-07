import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OnboardingStore {
  static final OnboardingStore _instance = OnboardingStore._internal();
  factory OnboardingStore() => _instance;
  OnboardingStore._internal();

  final _storage = const FlutterSecureStorage();

  static const _kCompleted = 'onboarding_completed_v1';
  static const _kHiddenKeys = 'onboarding_hidden_contact_keys_v1';

  // Snapshot “contatti già visti” (per rilevare nuovi contatti tra un avvio e l’altro)
  static const _kSeenContactKeys = 'onboarding_seen_contact_keys_v1';

  Future<bool> isCompleted() async {
    final v = await _storage.read(key: _kCompleted);
    return v == '1';
  }

  Future<void> setCompleted(bool completed) async {
    await _storage.write(key: _kCompleted, value: completed ? '1' : '0');
  }

  /// Contatti selezionati come “hidden/cover” durante onboarding
  Future<List<String>> getHiddenContactKeys() async {
    final raw = await _storage.read(key: _kHiddenKeys);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> setHiddenContactKeys(List<String> keys) async {
    final uniq = <String>{};
    for (final k in keys) {
      final t = k.trim();
      if (t.isNotEmpty) uniq.add(t);
    }
    final payload = jsonEncode(uniq.toList(growable: false));
    await _storage.write(key: _kHiddenKeys, value: payload);
  }

  /// Snapshot contatti “visti” (serve per trovare nuovi contatti da classificare)
  Future<List<String>> getSeenContactKeys() async {
    final raw = await _storage.read(key: _kSeenContactKeys);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> setSeenContactKeys(List<String> keys) async {
    final uniq = <String>{};
    for (final k in keys) {
      final t = k.trim();
      if (t.isNotEmpty) uniq.add(t);
    }
    final payload = jsonEncode(uniq.toList(growable: false));
    await _storage.write(key: _kSeenContactKeys, value: payload);
  }

  /// Utility: reset completo (solo per debug / futuro “Reset setup” in B3)
  Future<void> resetAll() async {
    await _storage.delete(key: _kCompleted);
    await _storage.delete(key: _kHiddenKeys);
    await _storage.delete(key: _kSeenContactKeys);
  }
}
