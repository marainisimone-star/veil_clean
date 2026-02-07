import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PIN minimale (V4.2):
/// - salva un PIN in secure storage
/// - verifica PIN
///
/// Nota: è una base DEV/POC.
/// In V5 potremo fare hashing + policy + tentativi + backoff + biometria.
class PinService {
  PinService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pinKey = 'veil_pin_v1';

  static Future<bool> hasPin() async {
    final v = await _storage.read(key: _pinKey);
    return v != null && v.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  static Future<bool> verifyPin(String pin) async {
    final v = await _storage.read(key: _pinKey);
    if (v == null || v.isEmpty) return false;
    return v == pin;
  }
}
