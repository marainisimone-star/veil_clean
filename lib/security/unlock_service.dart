import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:veil_clean/data/local_storage.dart';
import 'package:veil_clean/security/secure_gate.dart';
import 'package:veil_clean/services/audit_log_service.dart';

class UnlockService {
  static final UnlockService _instance = UnlockService._internal();
  factory UnlockService() => _instance;
  UnlockService._internal();

  // Legacy keys (plaintext)
  static const String _kPassphrase = 'veil_passphrase_v1';
  static const String _kPanicPassphrase = 'veil_panic_passphrase_v1';

  // New hashed keys
  static const String _kPassphraseHash = 'veil_passphrase_hash_v1';
  static const String _kPassphraseSalt = 'veil_passphrase_salt_v1';
  static const String _kPanicHash = 'veil_panic_passphrase_hash_v1';
  static const String _kPanicSalt = 'veil_panic_passphrase_salt_v1';
  static const String _kHiddenPanelHash = 'veil_hidden_panel_hash_v1';
  static const String _kHiddenPanelSalt = 'veil_hidden_panel_salt_v1';
  static const String _kHiddenFailCount = 'veil_hidden_fail_count_v1';
  static const String _kHiddenLockedUntil = 'veil_hidden_locked_until_v1';

  static const String _kGlobalPanic = 'veil_global_panic_v1';
  static const String _kRequireAppUnlock = 'veil_require_app_unlock_v1';

  String _kUnlockedUntil(String conversationId) =>
      'veil_unlocked_until_$conversationId';

  // TTL unlock (5 min)
  static const Duration _ttl = Duration(minutes: 5);

  // PBKDF2 params
  static const int _kdfIterations = 100000;
  static const int _kdfBits = 256;

  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _kdfIterations,
    bits: _kdfBits,
  );

  // ---------------- Passphrase ----------------

  Future<bool> hasPassphrase() async {
    final hash = LocalStorage.getString(_kPassphraseHash);
    final salt = LocalStorage.getString(_kPassphraseSalt);
    if (hash != null &&
        hash.trim().isNotEmpty &&
        salt != null &&
        salt.trim().isNotEmpty) {
      return true;
    }

    // Legacy plaintext
    final v = LocalStorage.getString(_kPassphrase);
    return v != null && v.trim().isNotEmpty;
  }

  Future<void> setPassphrase(String pass) async {
    final salt = _randomSaltBytes(16);
    final hashB64 = await _deriveHashB64(pass, salt);

    await LocalStorage.setString(_kPassphraseHash, hashB64);
    await LocalStorage.setString(_kPassphraseSalt, base64Encode(salt));

    // Remove legacy plaintext if present
    await LocalStorage.remove(_kPassphrase);
    await AuditLogService.I.log('pin_set', status: 'ok');
  }

  Future<bool> verifyPassphrase(String pass) async {
    final hash = LocalStorage.getString(_kPassphraseHash);
    final saltB64 = LocalStorage.getString(_kPassphraseSalt);

    if (hash != null &&
        hash.trim().isNotEmpty &&
        saltB64 != null &&
        saltB64.trim().isNotEmpty) {
      final salt = base64Decode(saltB64);
      final derived = await _deriveHashB64(pass, salt);
      return derived == hash;
    }

    // Legacy plaintext fallback + migrate on success
    final stored = LocalStorage.getString(_kPassphrase);
    if (stored == null || stored.isEmpty) return false;
    final ok = stored == pass;
    if (ok) {
      await setPassphrase(pass);
    }
    return ok;
  }

  // ---------------- Per-conversation unlock (TTL) ----------------

  Future<bool> isConversationUnlocked(String conversationId) async {
    if (await isGlobalPanicActive()) return false;

    final raw = LocalStorage.getString(_kUnlockedUntil(conversationId));
    if (raw == null || raw.trim().isEmpty) return false;

    final untilMs = int.tryParse(raw);
    if (untilMs == null) return false;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ok = nowMs < untilMs;
    if (ok) {
      // Keep SecureGate aligned with TTL unlock state.
      SecureGate.unlockSession();
      SecureGate.unlockConversation(conversationId);
    }
    return ok;
  }

  Future<void> unlockConversation(String conversationId) async {
    if (await isGlobalPanicActive()) return;

    final until = DateTime.now().add(_ttl).millisecondsSinceEpoch;
    await LocalStorage.setString(
        _kUnlockedUntil(conversationId), until.toString());

    // IMPORTANT: Keep SecureGate aligned with TTL unlock
    SecureGate.unlockSession();
    SecureGate.unlockConversation(conversationId);
    await AuditLogService.I.log(
      'conversation_unlock',
      status: 'ok',
      conversationId: conversationId,
    );
  }

  Future<void> lockConversation(String conversationId) async {
    await LocalStorage.remove(_kUnlockedUntil(conversationId));

    // IMPORTANT: lock per-conversation gate and clear reason
    SecureGate.lockConversation(conversationId);
    await AuditLogService.I.log(
      'conversation_lock',
      status: 'ok',
      conversationId: conversationId,
    );
  }

  // ---------------- Panic passphrase ----------------

  Future<bool> hasPanicPassphrase() async {
    final hash = LocalStorage.getString(_kPanicHash);
    final salt = LocalStorage.getString(_kPanicSalt);
    if (hash != null &&
        hash.trim().isNotEmpty &&
        salt != null &&
        salt.trim().isNotEmpty) {
      return true;
    }

    // Legacy plaintext
    final v = LocalStorage.getString(_kPanicPassphrase);
    return v != null && v.trim().isNotEmpty;
  }

  Future<void> setPanicPassphrase(String pass) async {
    final salt = _randomSaltBytes(16);
    final hashB64 = await _deriveHashB64(pass, salt);

    await LocalStorage.setString(_kPanicHash, hashB64);
    await LocalStorage.setString(_kPanicSalt, base64Encode(salt));

    // Remove legacy plaintext if present
    await LocalStorage.remove(_kPanicPassphrase);
    await AuditLogService.I.log('panic_pin_set', status: 'ok');
  }

  Future<bool> isPanicPassphrase(String pass) async {
    final hash = LocalStorage.getString(_kPanicHash);
    final saltB64 = LocalStorage.getString(_kPanicSalt);

    if (hash != null &&
        hash.trim().isNotEmpty &&
        saltB64 != null &&
        saltB64.trim().isNotEmpty) {
      final salt = base64Decode(saltB64);
      final derived = await _deriveHashB64(pass, salt);
      return derived == hash;
    }

    // Legacy plaintext fallback + migrate on success
    final stored = LocalStorage.getString(_kPanicPassphrase);
    if (stored == null || stored.isEmpty) return false;
    final ok = stored == pass;
    if (ok) {
      await setPanicPassphrase(pass);
    }
    return ok;
  }

  // ---------------- Hidden panel PIN ----------------

  Future<bool> hasHiddenPanelPin() async {
    final hash = LocalStorage.getString(_kHiddenPanelHash);
    final salt = LocalStorage.getString(_kHiddenPanelSalt);
    return hash != null &&
        hash.trim().isNotEmpty &&
        salt != null &&
        salt.trim().isNotEmpty;
  }

  Future<void> setHiddenPanelPin(String pin) async {
    final salt = _randomSaltBytes(16);
    final hashB64 = await _deriveHashB64(pin, salt);

    await LocalStorage.setString(_kHiddenPanelHash, hashB64);
    await LocalStorage.setString(_kHiddenPanelSalt, base64Encode(salt));
    await AuditLogService.I.log('hidden_pin_set', status: 'ok');
  }

  Future<bool> verifyHiddenPanelPin(String pin) async {
    final hash = LocalStorage.getString(_kHiddenPanelHash);
    final saltB64 = LocalStorage.getString(_kHiddenPanelSalt);

    if (hash == null ||
        hash.trim().isEmpty ||
        saltB64 == null ||
        saltB64.trim().isEmpty) {
      return false;
    }

    final salt = base64Decode(saltB64);
    final derived = await _deriveHashB64(pin, salt);
    return derived == hash;
  }

  // ---------------- Hidden panel lockout ----------------

  Future<DateTime?> hiddenPanelLockedUntil() async {
    final raw = LocalStorage.getString(_kHiddenLockedUntil);
    if (raw == null || raw.trim().isEmpty) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<bool> isHiddenPanelLocked() async {
    final until = await hiddenPanelLockedUntil();
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Future<int> hiddenPanelFailCount() async {
    final raw = LocalStorage.getString(_kHiddenFailCount);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> resetHiddenPanelFailures() async {
    await LocalStorage.remove(_kHiddenFailCount);
    await LocalStorage.remove(_kHiddenLockedUntil);
  }

  Future<void> recordHiddenPanelFailure({
    int maxAttempts = 3,
    Duration lockout = const Duration(minutes: 5),
  }) async {
    final count = await hiddenPanelFailCount();
    final next = count + 1;
    await LocalStorage.setString(_kHiddenFailCount, next.toString());
    if (next >= maxAttempts) {
      final until =
          DateTime.now().add(lockout).millisecondsSinceEpoch.toString();
      await LocalStorage.setString(_kHiddenLockedUntil, until);
      await AuditLogService.I.log('hidden_pin_lockout', status: 'ok');
    }
  }

  // ---------------- Global panic ----------------

  Future<bool> isAppUnlockRequired() async {
    final v = LocalStorage.getString(_kRequireAppUnlock);
    if (v == null || v.trim().isEmpty) return false;
    return v != '0';
  }

  Future<void> setAppUnlockRequired(bool required) async {
    await LocalStorage.setString(_kRequireAppUnlock, required ? '1' : '0');
  }

  Future<bool> isGlobalPanicActive() async {
    final v = LocalStorage.getString(_kGlobalPanic);
    return v == '1';
  }

  Future<void> activateGlobalPanic() async {
    await LocalStorage.setString(_kGlobalPanic, '1');
    SecureGate.activateGlobalPanic();
    await AuditLogService.I.log('panic_activate', status: 'ok');
  }

  Future<void> clearGlobalPanic() async {
    await LocalStorage.remove(_kGlobalPanic);
    SecureGate.clearGlobalPanic();
    await AuditLogService.I.log('panic_clear', status: 'ok');
  }

  // ---------------- Reset setup ----------------

  Future<void> resetSetup() async {
    await LocalStorage.remove(_kPassphrase);
    await LocalStorage.remove(_kPanicPassphrase);

    await LocalStorage.remove(_kPassphraseHash);
    await LocalStorage.remove(_kPassphraseSalt);
    await LocalStorage.remove(_kPanicHash);
    await LocalStorage.remove(_kPanicSalt);
    await LocalStorage.remove(_kHiddenPanelHash);
    await LocalStorage.remove(_kHiddenPanelSalt);
    await LocalStorage.remove(_kHiddenFailCount);
    await LocalStorage.remove(_kHiddenLockedUntil);

    await LocalStorage.remove(_kGlobalPanic);
    await LocalStorage.remove(_kRequireAppUnlock);

    // Align gate too
    SecureGate.lockSession();
    await AuditLogService.I.log('security_reset', status: 'ok');
  }

  // ---------------- Internal ----------------

  List<int> _randomSaltBytes(int length) {
    final r = Random.secure();
    final out = <int>[];
    for (var i = 0; i < length; i++) {
      out.add(r.nextInt(256));
    }
    return out;
  }

  Future<String> _deriveHashB64(String pass, List<int> salt) async {
    final secret = SecretKey(utf8.encode(pass));
    final key = await _kdf.deriveKey(
      secretKey: secret,
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }
}
