import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ContactPolicyStore {
  static final ContactPolicyStore _instance = ContactPolicyStore._internal();
  factory ContactPolicyStore() => _instance;
  ContactPolicyStore._internal();

  final _storage = const FlutterSecureStorage();

  // chiavi contatti marcati come “hidden”
  static const _kHiddenKeys = 'contact_policy_hidden_keys_v1';

  Future<Set<String>> _loadHidden() async {
    final raw = await _storage.read(key: _kHiddenKeys);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveHidden(Set<String> keys) async {
    final payload = jsonEncode(keys.toList(growable: false));
    await _storage.write(key: _kHiddenKeys, value: payload);
  }

  Future<bool> isHidden(String contactKey) async {
    final set = await _loadHidden();
    return set.contains(contactKey);
  }

  Future<void> setHidden(String contactKey, bool hidden) async {
    final set = await _loadHidden();
    if (hidden) {
      set.add(contactKey);
    } else {
      set.remove(contactKey);
    }
    await _saveHidden(set);
  }

  Future<List<String>> getAllHiddenKeys() async {
    final set = await _loadHidden();
    final list = set.toList()..sort();
    return list;
  }

  /// Applica in blocco (utile dopo onboarding)
  Future<void> setHiddenKeysBulk(List<String> keys) async {
    final set = <String>{};
    for (final k in keys) {
      final t = k.trim();
      if (t.isNotEmpty) set.add(t);
    }
    await _saveHidden(set);
  }

  Future<void> reset() async {
    await _storage.delete(key: _kHiddenKeys);
  }
}
