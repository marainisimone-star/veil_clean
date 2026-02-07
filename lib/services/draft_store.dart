import 'dart:convert';

import '../crypto/crypto_service.dart';
import '../data/local_storage.dart';

class DraftStore {
  DraftStore._();
  static final DraftStore I = DraftStore._();

  String _key(String conversationId) => 'draft_$conversationId';

  Future<void> saveDraft({
    required String conversationId,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) {
      await clearDraft(conversationId: conversationId);
      return;
    }

    final pack = await CryptoService().encrypt(
      conversationId: conversationId,
      plaintext: t,
    );

    final raw = jsonEncode(pack.toMap());
    await LocalStorage.setString(_key(conversationId), raw);
  }

  Future<String?> loadDraft({
    required String conversationId,
  }) async {
    try {
      final raw = LocalStorage.getString(_key(conversationId));
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final pack = CipherPack.fromMap(decoded.cast<String, dynamic>());
      final clear = await CryptoService().decrypt(
        conversationId: conversationId,
        pack: pack,
      );
      return clear;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearDraft({
    required String conversationId,
  }) async {
    await LocalStorage.remove(_key(conversationId));
  }
}
