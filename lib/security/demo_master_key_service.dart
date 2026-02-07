import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'panic_controller.dart';
import 'secure_session.dart';

/// V4.1 (demo persistente):
/// - crea/legge una "master key demo" persistita in FlutterSecureStorage
/// - la carica in RAM (SecureSession) quando l'utente fa Unlock/Skip/Continue
///
/// IMPORTANTISSIMO:
/// Questa è una chiave DEMO per sviluppo.
/// In produzione: la key va derivata da PIN/biometria + salt + KDF,
/// e NON deve essere salvata in chiaro nello storage.
class DemoMasterKeyService {
  DemoMasterKeyService._();

  static const String _storageKey = 'veil_demo_master_key_v1';
  static const int _keyLen = 32;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Garantisce che:
  /// - esista una chiave persistente nello storage
  /// - sia caricata in RAM (SecureSession.setKeys)
  /// - panic venga resettato (clearAfterReauth)
  static Future<void> ensureSessionReady() async {
    final keyBytes = await _getOrCreatePersistentMasterKey();
    SecureSession.I.setKeys(masterKey: keyBytes);

    // Dopo un vero panic, questa chiamata equivale a "re-auth completato"
    PanicController.I.clearAfterReauth();
  }

  /// Utile solo per test/debug
  static Future<void> resetPersistentKey() async {
    await _storage.delete(key: _storageKey);
  }

  static Future<Uint8List> _getOrCreatePersistentMasterKey() async {
    final existing = await _storage.read(key: _storageKey);

    if (existing != null && existing.isNotEmpty) {
      final bytes = base64Decode(existing);
      if (bytes.length == _keyLen) {
        return Uint8List.fromList(bytes);
      }
      // Se la lunghezza non è corretta, rigeneriamo
    }

    final newBytes = _secureRandomBytes(_keyLen);
    await _storage.write(key: _storageKey, value: base64Encode(newBytes));
    return Uint8List.fromList(newBytes);
  }

  /// Generatore di byte sicuro (no cryptography.randomBytes)
  static Uint8List _secureRandomBytes(int length) {
    final rnd = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    return bytes;
  }
}
