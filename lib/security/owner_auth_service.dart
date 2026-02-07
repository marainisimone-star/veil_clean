import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OwnerAuthService {
  static final OwnerAuthService _instance = OwnerAuthService._internal();
  factory OwnerAuthService() => _instance;
  OwnerAuthService._internal();

  static const _kPinHash = 'owner_pin_hash_v1';
  static const _kAltPinHash = 'owner_alt_pin_hash_v1';

  final _storage = const FlutterSecureStorage();
  final _sha = Sha256();

  Future<bool> hasPin() async {
    final v = await _storage.read(key: _kPinHash);
    return v != null && v.isNotEmpty;
  }

  Future<bool> hasAlternativePin() async {
    final v = await _storage.read(key: _kAltPinHash);
    return v != null && v.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final h = await _hash(pin);
    await _storage.write(key: _kPinHash, value: h);
  }

  Future<void> setAlternativePin(String pin) async {
    final h = await _hash(pin);
    await _storage.write(key: _kAltPinHash, value: h);
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPinHash);
    if (stored == null || stored.isEmpty) return false;
    final h = await _hash(pin);
    return _timingSafeEq(stored, h);
  }

  Future<bool> verifyAlternativePin(String pin) async {
    final stored = await _storage.read(key: _kAltPinHash);
    if (stored == null || stored.isEmpty) return false;
    final h = await _hash(pin);
    return _timingSafeEq(stored, h);
  }

  /// ✅ usato dal flow: PIN primario o alternativo
  Future<bool> verifyAnyPin(String pin) async {
    final ok1 = await verifyPin(pin);
    if (ok1) return true;
    final ok2 = await verifyAlternativePin(pin);
    return ok2;
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kAltPinHash);
  }

  Future<String> _hash(String pin) async {
    final bytes = utf8.encode(pin);

    // sha256(pin)
    final digest = await _sha.hash(bytes);

    // whitening leggero deterministico
    var h = 0;
    for (final b in digest.bytes) {
      h = (h * 31 + b) & 0x7fffffff;
    }
    final out = ByteData(4)..setUint32(0, h);

    final salted = Uint8List.fromList([
      ...digest.bytes,
      ...out.buffer.asUint8List(),
    ]);

    // sha256(sha256(pin) + whitening)
    final digest2 = await _sha.hash(salted);
    return base64Encode(digest2.bytes);
  }

  bool _timingSafeEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
