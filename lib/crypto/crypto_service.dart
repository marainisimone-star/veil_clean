import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:veil_clean/security/secure_gate.dart';

class CipherPack {
  final String version; // "v1"
  final String nonceB64;
  final String cipherTextB64;
  final String macB64;

  const CipherPack({
    required this.version,
    required this.nonceB64,
    required this.cipherTextB64,
    required this.macB64,
  });

  Map<String, dynamic> toMap() => {
        'v': version,
        'nonce': nonceB64,
        'ct': cipherTextB64,
        'mac': macB64,
      };

  static CipherPack fromMap(Map<String, dynamic> m) {
    return CipherPack(
      version: (m['v'] ?? 'v1') as String,
      nonceB64: (m['nonce'] ?? '') as String,
      cipherTextB64: (m['ct'] ?? '') as String,
      macB64: (m['mac'] ?? '') as String,
    );
  }
}

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _storage = const FlutterSecureStorage();
  final Cipher _cipher = AesGcm.with256bits();

  String _keyNameForConversation(String conversationId) => 'ck_$conversationId';

  Future<SecretKey> _getOrCreateConversationKey(String conversationId) async {
    final keyName = _keyNameForConversation(conversationId);
    final existing = await _storage.read(key: keyName);

    if (existing != null && existing.isNotEmpty) {
      final keyBytes = base64Decode(existing);
      return SecretKey(keyBytes);
    }

    final newKey = await _cipher.newSecretKey();
    final bytes = await newKey.extractBytes();
    await _storage.write(key: keyName, value: base64Encode(bytes));
    return newKey;
  }

  /// IMPORTANT:
  /// - encrypt NON deve essere bloccato dal gate (serve per salvare "real" anche quando UI è fredda)
  /// - decrypt invece SI (serve owner auth + unlock conversazione)
  Future<CipherPack> encrypt({
    required String conversationId,
    required String plaintext,
  }) async {
    final key = await _getOrCreateConversationKey(conversationId);
    final nonce = _cipher.newNonce();

    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    return CipherPack(
      version: 'v1',
      nonceB64: base64Encode(box.nonce),
      cipherTextB64: base64Encode(box.cipherText),
      macB64: base64Encode(box.mac.bytes),
    );
  }

  Future<String> decrypt({
    required String conversationId,
    required CipherPack pack,
  }) async {
    // ✅ Gate SOLO su decrypt/reveal
    SecureGate.ensureUnlockedOrThrow(conversationId: conversationId);

    final key = await _getOrCreateConversationKey(conversationId);

    final box = SecretBox(
      base64Decode(pack.cipherTextB64),
      nonce: base64Decode(pack.nonceB64),
      mac: Mac(base64Decode(pack.macB64)),
    );

    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
    );

    return utf8.decode(clear);
  }
}
