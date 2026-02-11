import 'dart:async';
import 'dart:convert';

import '../crypto/crypto_service.dart';
import '../data/local_storage.dart';
import '../models/attachment_ref.dart';
import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/attachment_store.dart';
import '../services/cover_ai_service.dart';
import '../services/firebase_backend.dart';
import '../services/remote_backend.dart';
import '../services/app_logger.dart';
import 'contact_repository.dart';
import 'conversation_store.dart';
import 'message_events.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class MessageRepository {
  static final MessageRepository _instance = MessageRepository._internal();
  factory MessageRepository() => _instance;
  MessageRepository._internal();

  final _crypto = CryptoService();
  final _convs = ConversationStore();
  final _contacts = ContactRepository();

  final StreamController<MessageEvent> _events =
      StreamController<MessageEvent>.broadcast();
  Stream<MessageEvent> get events => _events.stream;

  String _keyMsgs(String conversationId) => 'msgs_$conversationId';
  String _keySeeded(String conversationId) => 'seeded_$conversationId';
  String _keyCoverHistory(String conversationId) =>
      'cover_history_$conversationId';
  static const int _coverHistoryMax = 24;

  // ---------------- PUBLIC API ----------------

  Future<List<Message>> getMessages(String conversationId) async {
    await _seedIfNeeded(conversationId);

    final msgs = [...await _load(conversationId)];
    msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final cleaned = await _applyTtlIfNeeded(conversationId, msgs);
    return cleaned;
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
    required bool isMe,
    AttachmentRef? attachmentRef,
    bool? hiddenOverride,
  }) async {
    final now = DateTime.now();
    final msgId = _newId();

    final conv = await _convs.getById(conversationId);
    final recent = await _load(conversationId);
    final coverHistory = await _loadCoverHistory(conversationId);
    final isGroup = conv?.isGroup == true;
    final contact = await _contactForConversation(conv);

    final isCovert = await _isConversationCovert(conversationId);

    late String cover;
    late final MessageContentMode mode;
    CipherPack? realPack;

    if (!isCovert) {
      cover = text;
      mode = MessageContentMode.plain;
      realPack = null;
    } else {
      final style = await _getCoverStyle(conversationId);
      cover = await _coverForOutgoing(
        real: text,
        conversationId: conversationId,
        style: style,
        recent: recent,
        coverHistory: coverHistory,
        conversation: conv,
        contact: contact,
      );
      if (cover.trim().isEmpty) cover = 'Ok.';

      final payloadText = text.trim().isEmpty ? ' ' : text;
      realPack = await _crypto.encrypt(
        conversationId: conversationId,
        plaintext: payloadText,
      );
      mode = MessageContentMode.dual;
    }

    // se è solo attachment, niente testo cover
    if (text.trim().isEmpty && attachmentRef != null) {
      cover = '';
    }

    final msg = Message(
      id: msgId,
      conversationId: conversationId,
      coverText: cover,
      real: realPack,
      mode: mode,
      isMe: isMe,
      timestamp: now,
      status: 'sending',
      attachment: attachmentRef,
      authorId: isGroup ? 'me' : null,
      authorName: isGroup ? 'You' : null,
    );

    final list = await _load(conversationId);
    final next = [...list, msg];
    await _save(conversationId, next);
    if (isCovert && cover.trim().isNotEmpty) {
      await _rememberCover(conversationId, cover);
    }

    if (hiddenOverride == true) {
      await _convs.setHidden(conversationId: conversationId, hidden: true);
    } else if (hiddenOverride == false && (conv?.isHidden == true)) {
      await _convs.setHidden(conversationId: conversationId, hidden: false);
    }

    _events.add(MessageEvent(type: MessageEventType.added, message: msg));

    await _convs.updateLastMessage(
      conversationId: conversationId,
      lastMessage: cover.trim().isEmpty ? ' ' : cover,
      when: now,
    );

    // Best-effort: send to remote backend (cover text only for now).
    try {
      final firebaseSupported =
          kIsWeb ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows;
      if (firebaseSupported) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final hiddenFlag = (hiddenOverride == true) || (conv?.isHidden == true);
          final remote = RemoteMessage(
            id: msg.id,
            conversationId: conversationId,
            senderId: uid,
            text: cover.trim().isEmpty ? ' ' : cover.trim(),
            hidden: hiddenFlag,
            createdAt: now,
          );
          await FirebaseBackend.I.sendMessage(remote);
        }
      }
    } catch (e, st) {
      AppLogger.w('Remote send failed', error: e, stackTrace: st);
    }

    await Future.delayed(const Duration(milliseconds: 250));
    final updated = msg.copyWith(status: 'sent');
    await _updateMessage(conversationId, updated);
  }

  /// Ingest a remote message into local storage (cover text only).
  Future<bool> ingestRemoteMessage(RemoteMessage rm) async {
    try {
      final list = await _load(rm.conversationId);
      if (list.any((m) => m.id == rm.id)) return false;

      final msg = Message(
        id: rm.id,
        conversationId: rm.conversationId,
        coverText: rm.text,
        real: null,
        mode: MessageContentMode.plain,
        isMe: false,
        timestamp: rm.createdAt,
        status: 'delivered',
      );

      final next = [...list, msg];
      await _save(rm.conversationId, next);
      _events.add(MessageEvent(type: MessageEventType.added, message: msg));

      await _convs.updateLastMessage(
        conversationId: rm.conversationId,
        lastMessage: rm.text.trim().isEmpty ? ' ' : rm.text.trim(),
        when: rm.createdAt,
      );

      if (rm.hidden) {
        await _convs.setHidden(conversationId: rm.conversationId, hidden: true);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> receiveMessage({
    required String conversationId,
    required String text,
    String? authorId,
    String? authorName,
  }) async {
    final now = DateTime.now();
    final msgId = _newId();

    final conv = await _convs.getById(conversationId);
    final recent = await _load(conversationId);
    final coverHistory = await _loadCoverHistory(conversationId);
    final isGroup = conv?.isGroup == true;
    final contact = await _contactForConversation(conv);

    final isCovert = await _isConversationCovert(conversationId);

    late String cover;
    late final MessageContentMode mode;
    CipherPack? realPack;

    if (!isCovert) {
      cover = text;
      mode = MessageContentMode.plain;
      realPack = null;
    } else {
      final style = await _getCoverStyle(conversationId);
      cover = await _coverForIncoming(
        real: text,
        conversationId: conversationId,
        style: style,
        recent: recent,
        coverHistory: coverHistory,
        conversation: conv,
        contact: contact,
      );
      if (cover.trim().isEmpty) cover = 'Ok.';

      final payloadText = text.trim().isEmpty ? ' ' : text;
      realPack = await _crypto.encrypt(
        conversationId: conversationId,
        plaintext: payloadText,
      );
      mode = MessageContentMode.dual;
    }

    final msg = Message(
      id: msgId,
      conversationId: conversationId,
      coverText: cover,
      real: realPack,
      mode: mode,
      isMe: false,
      timestamp: now,
      status: 'delivered',
      authorId: isGroup ? authorId : null,
      authorName: isGroup ? (authorName ?? 'Member') : null,
    );

    final list = await _load(conversationId);
    final next = [...list, msg];
    await _save(conversationId, next);
    if (isCovert && cover.trim().isNotEmpty) {
      await _rememberCover(conversationId, cover);
    }

    _events.add(MessageEvent(type: MessageEventType.added, message: msg));

    final c = await _convs.getById(conversationId);
    final currentUnread = c?.unreadCount ?? 0;

    await _convs.updateLastMessage(
      conversationId: conversationId,
      lastMessage: cover.trim().isEmpty ? ' ' : cover,
      when: now,
      unreadCount: currentUnread + 1,
    );
  }

  Future<String?> revealRealText(Message m) async {
    try {
      if (m.mode != MessageContentMode.dual) return null;

      final pack = m.real;
      if (pack == null) return null;

      final cid = m.conversationId.trim();
      if (cid.isEmpty) return null;

      final clear = await _crypto.decrypt(
        conversationId: cid,
        pack: pack,
      );

      final out = clear.trim();
      if (out.isEmpty) return null;

      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearConversation(String conversationId) async {
    await LocalStorage.remove(_keyMsgs(conversationId));
    await LocalStorage.remove(_keySeeded(conversationId));
    await LocalStorage.remove(_keyCoverHistory(conversationId));
  }

  Future<bool> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      final list = await _load(conversationId);
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx < 0) return false;

      final toDelete = list[idx];
      final next = [...list]..removeAt(idx);
      await _save(conversationId, next);

      final att = toDelete.attachment;
      if (att != null) {
        await AttachmentStore.deleteAttachment(
          conversationId: conversationId,
          attachmentId: att.id,
        );
      }

      if (next.isNotEmpty) {
        final last = next.last;
        final preview =
            last.coverText.trim().isNotEmpty ? last.coverText.trim() : ' ';
        await _convs.updateLastMessage(
          conversationId: conversationId,
          lastMessage: preview,
          when: DateTime.now(),
        );
      } else {
        await _convs.updateLastMessage(
          conversationId: conversationId,
          lastMessage: ' ',
          when: DateTime.now(),
          unreadCount: 0,
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Internal persistence ----------------

  Future<List<Message>> _load(String conversationId) async {
    try {
      final raw = LocalStorage.getString(_keyMsgs(conversationId));
      if (raw == null || raw.trim().isEmpty) return const [];

      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list
          .whereType<Map>()
          .map((m) => Message.fromMap(m.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(String conversationId, List<Message> msgs) async {
    final payload =
        jsonEncode(msgs.map((m) => m.toMap()).toList(growable: false));
    await LocalStorage.setString(_keyMsgs(conversationId), payload);
  }

  Future<void> _updateMessage(String conversationId, Message updated) async {
    final list = await _load(conversationId);
    final next = list
        .map((m) => m.id == updated.id ? updated : m)
        .toList(growable: false);
    await _save(conversationId, next);
    _events.add(MessageEvent(type: MessageEventType.updated, message: updated));
  }

  Future<void> _seedIfNeeded(String conversationId) async {
    final seeded = LocalStorage.getString(_keySeeded(conversationId)) == '1';
    if (seeded) return;
    await LocalStorage.setString(_keySeeded(conversationId), '1');
  }

  // ---------------- TTL cleanup ----------------

  Future<List<Message>> _applyTtlIfNeeded(
      String conversationId, List<Message> list) async {
    final conv = await _convs.getById(conversationId);
    final ttl = conv?.messageTtlMinutes;

    if (ttl == null || ttl <= 0) return list;

    final cutoff = DateTime.now().subtract(Duration(minutes: ttl));
    final removed =
        list.where((m) => m.timestamp.isBefore(cutoff)).toList(growable: false);

    if (removed.isEmpty) return list;

    for (final m in removed) {
      final att = m.attachment;
      if (att != null) {
        await AttachmentStore.deleteAttachment(
          conversationId: conversationId,
          attachmentId: att.id,
        );
      }
    }

    final next = list
        .where((m) => !m.timestamp.isBefore(cutoff))
        .toList(growable: false);
    await _save(conversationId, next);

    if (next.isEmpty) {
      await _convs.updateLastMessage(
        conversationId: conversationId,
        lastMessage: ' ',
        when: DateTime.now(),
        unreadCount: 0,
      );
    } else {
      final last = next.last;
      final preview =
          last.coverText.trim().isNotEmpty ? last.coverText.trim() : ' ';
      await _convs.updateLastMessage(
        conversationId: conversationId,
        lastMessage: preview,
        when: last.timestamp,
        unreadCount: 0,
      );
    }

    return next;
  }

  // ---------------- Covert decision ----------------

  Future<bool> _isConversationCovert(String conversationId) async {
    try {
      final c = await _convs.getById(conversationId);
      final cid = c?.contactId;
      if (cid == null || cid.trim().isEmpty) {
        return true;
      }
      final contact = await _contacts.getById(cid);
      if (contact == null) return true;

      return contact.mode == ContactMode.dualHidden;
    } catch (_) {
      return true;
    }
  }

  // ---------------- Cover style ----------------

  Future<CoverStyle> _getCoverStyle(String conversationId) async {
    try {
      final c = await _convs.getById(conversationId);
      if (c == null) return CoverStyle.private;
      final contact = await _contactForConversation(c);
      if (contact != null) {
        switch (contact.coverStyleOverride) {
          case CoverStyleOverride.business:
            return CoverStyle.business;
          case CoverStyleOverride.private:
            return CoverStyle.private;
          case CoverStyleOverride.auto:
            break;
        }
      }
      return c.coverStyle;
    } catch (_) {
      return CoverStyle.private;
    }
  }

  // ---------------- Cover text generation ----------------

  Future<Contact?> _contactForConversation(Conversation? c) async {
    final cid = c?.contactId?.trim();
    if (cid == null || cid.isEmpty) return null;
    try {
      return await _contacts.getById(cid);
    } catch (_) {
      return null;
    }
  }

  Future<String> _coverForOutgoing({
    required String real,
    required String conversationId,
    required CoverStyle style,
    required List<Message> recent,
    required List<String> coverHistory,
    required Conversation? conversation,
    required Contact? contact,
  }) {
    return _generateSmartCover(
      real: real,
      conversationId: conversationId,
      style: style,
      recent: recent,
      coverHistory: coverHistory,
      conversation: conversation,
      contact: contact,
      outgoing: true,
    );
  }

  Future<String> _coverForIncoming({
    required String real,
    required String conversationId,
    required CoverStyle style,
    required List<Message> recent,
    required List<String> coverHistory,
    required Conversation? conversation,
    required Contact? contact,
  }) {
    return _generateSmartCover(
      real: real,
      conversationId: conversationId,
      style: style,
      recent: recent,
      coverHistory: coverHistory,
      conversation: conversation,
      contact: contact,
      outgoing: false,
    );
  }

  Future<String> _generateSmartCover({
    required String real,
    required String conversationId,
    required CoverStyle style,
    required List<Message> recent,
    required List<String> coverHistory,
    required Conversation? conversation,
    required Contact? contact,
    required bool outgoing,
  }) async {
    final recentCovers = recent
        .map((m) => m.coverText.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final settings = await CoverAiService.I.loadSettings();
    final forceAuto = conversation?.isGroup == true;
    final effectiveSettings =
        forceAuto ? settings.copyWith(languageMode: 'auto') : settings;
    final languageHint = CoverAiService.I.resolveLanguageHintForConversation(
      real,
      conversationId,
      override: effectiveSettings.languageMode,
    );
    final aiCover = await CoverAiService.I.generateCover(
      realText: real,
      conversationId: conversationId,
      languageHint: languageHint,
      businessTone: style == CoverStyle.business,
      outgoing: outgoing,
      recentCovers: recentCovers,
      contactName: contact?.coverName,
      groupMembers:
          conversation?.groupMembers.map((m) => m.name).toList(growable: false),
      settings: effectiveSettings,
    );
    if (aiCover != null && aiCover.trim().isNotEmpty) {
      return aiCover.trim();
    }

    final isBusiness = style == CoverStyle.business;

    final topic = _inferTopic(real, isBusiness: isBusiness);
    final person = _inferPerson(
        conversation: conversation,
        contact: contact,
        conversationId: conversationId);
    final when = _inferTimeHint();

    final templates = _templates(
      outgoing: outgoing,
      isBusiness: isBusiness,
      topic: topic,
      person: person,
      when: when,
    );

    final baseSeed = _hash(
      '$conversationId|$real|${style.name}|${recent.length}|${DateTime.now().minute}|$outgoing',
    );

    for (var i = 0; i < templates.length; i++) {
      final idx = (baseSeed + i) % templates.length;
      final candidate = templates[idx].trim();
      if (candidate.isEmpty) continue;
      if (!_isRecentDuplicate(candidate, recentCovers, coverHistory)) {
        return candidate;
      }
    }

    return templates[baseSeed % templates.length].trim();
  }

  List<String> _templates({
    required bool outgoing,
    required bool isBusiness,
    required String topic,
    required String person,
    required String when,
  }) {
    if (isBusiness) {
      if (outgoing) {
        return <String>[
          'Ricevuto, procedo su $topic.',
          'Perfetto, aggiorno $person $when.',
          'Chiaro, prendo in carico e ti allineo.',
          'Ok, mi attivo ora e chiudo appena pronto.',
          'Confermato, tengo traccia e condivido update.',
          'Va bene, coordino il prossimo passo su $topic.',
          'Ricevuto, faccio un check rapido e torno da te.',
          'Perfect, I will handle it and message you later.',
        ];
      }
      return <String>[
        'Ok, ricevuto su $topic.',
        'Perfetto, resto allineato.',
        'Chiaro, grazie per l’update.',
        'Confirmed, let us proceed this way.',
        'Ricevuto, tengo monitorato.',
        'Ok, ci sentiamo $when per il punto.',
        'Tutto chiaro, aggiorno il team.',
        'Va bene, grazie $person.',
      ];
    }

    if (outgoing) {
      return <String>[
        'Ok, ci penso io $when.',
        'Perfetto, poi aggiorno $person.',
        'Sounds good, let us do it this way for $topic.',
        'Ricevuto, ti scrivo appena riesco.',
        'Ci sta, controllo e ti dico dopo.',
        'Ok, intanto sistemo questa cosa.',
        'Perfetto, passo io e poi ti faccio sapere.',
        'Great, we will catch up later.',
      ];
    }

    return <String>[
      'Ok, perfetto.',
      'Va bene, grazie.',
      'Chiaro, ricevuto.',
      'Tutto ok, ci sentiamo $when.',
      'Perfect, then we will proceed this way.',
      'Ricevuto 👍',
      'Va bene $person, ci sta.',
      'Ok, ottimo su $topic.',
    ];
  }

  bool _isRecentDuplicate(
    String candidate,
    List<String> recentCovers,
    List<String> coverHistory,
  ) {
    final c = _normalizeCover(candidate);
    final tail = recentCovers.reversed.take(6);
    for (final r in tail) {
      if (_normalizeCover(r) == c) return true;
    }
    final histTail = coverHistory.reversed.take(12);
    for (final r in histTail) {
      if (_normalizeCover(r) == c) return true;
    }
    final nearTail = [
      ...recentCovers.reversed.take(3),
      ...coverHistory.reversed.take(3),
    ];
    for (final r in nearTail) {
      if (_isTooSimilar(candidate, r)) return true;
    }
    return false;
  }

  String _normalizeCover(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isTooSimilar(String a, String b) {
    final ta = _tokenizeForSimilarity(a);
    final tb = _tokenizeForSimilarity(b);
    if (ta.isEmpty || tb.isEmpty) return false;

    final inter = ta.intersection(tb).length.toDouble();
    final union = ta.union(tb).length.toDouble();
    if (union <= 0) return false;

    final jaccard = inter / union;
    return jaccard >= 0.72;
  }

  Set<String> _tokenizeForSimilarity(String s) {
    final clean = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9àèéìòù ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return <String>{};

    final stop = <String>{
      'ok',
      'va',
      'bene',
      'grazie',
      'perfetto',
      'ricevuto',
      'allora',
      'ci',
      'ti',
      'te',
      'io',
      'a',
      'di',
      'in',
      'the',
      'and',
      'to',
      'for',
    };

    return clean
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.length >= 3 && !stop.contains(w))
        .toSet();
  }

  String _inferTopic(String real, {required bool isBusiness}) {
    final l = real.toLowerCase();

    if (l.contains('contratt') ||
        l.contains('agreement') ||
        l.contains('nda')) {
      return isBusiness ? 'il contratto' : 'i documenti';
    }
    if (l.contains('budget') ||
        l.contains('costo') ||
        l.contains('preventiv')) {
      return isBusiness ? 'il budget' : 'le spese';
    }
    if (l.contains('deadline') ||
        l.contains('scadenza') ||
        l.contains('urgent')) {
      return isBusiness ? 'la scadenza' : 'i tempi';
    }
    if (l.contains('cliente') ||
        l.contains('client') ||
        l.contains('partner')) {
      return isBusiness ? 'il cliente' : 'la persona';
    }
    if (l.contains('support') || l.contains('ticket') || l.contains('bug')) {
      return isBusiness ? 'il supporto' : 'il problema';
    }
    if (l.contains('present') || l.contains('slide') || l.contains('deck')) {
      return isBusiness ? 'la presentazione' : 'il materiale';
    }
    if (l.contains('viaggio') || l.contains('flight') || l.contains('hotel')) {
      return isBusiness ? 'la trasferta' : 'il viaggio';
    }
    if (l.contains('spesa') || l.contains('cena') || l.contains('pranzo')) {
      return isBusiness ? 'le note spese' : 'il programma';
    }
    if (l.contains('family') || l.contains('famiglia') || l.contains('casa')) {
      return isBusiness ? 'l’agenda' : 'la casa';
    }

    if (l.contains('meeting') || l.contains('riun') || l.contains('call')) {
      return isBusiness ? 'la riunione' : 'l’organizzazione';
    }
    if (l.contains('doc') || l.contains('file') || l.contains('report')) {
      return isBusiness ? 'il documento' : 'quel file';
    }
    if (l.contains('pag') || l.contains('invoice') || l.contains('fattur')) {
      return isBusiness ? 'la parte amministrativa' : 'i conti';
    }
    if (l.contains('sped') || l.contains('delivery') || l.contains('ordine')) {
      return isBusiness ? 'la consegna' : 'l’ordine';
    }

    if (isBusiness) return 'la pratica';
    return 'la cosa';
  }

  String _inferPerson({
    required Conversation? conversation,
    required Contact? contact,
    required String conversationId,
  }) {
    if (conversation?.isGroup == true) {
      final members = conversation?.groupMembers ?? const [];
      final others = members
          .where((m) => m.id != 'me' && m.name.trim().isNotEmpty)
          .map((m) => m.name.trim())
          .toList(growable: false);
      if (others.isNotEmpty) {
        return others[
            _hash(conversationId + others.length.toString()) % others.length];
      }
    }

    final c = contact?.coverName.trim() ?? '';
    if (c.isNotEmpty) return c;
    return 'te';
  }

  String _inferTimeHint() {
    final h = DateTime.now().hour;
    if (h < 12) return 'in mattinata';
    if (h < 18) return 'nel pomeriggio';
    return 'later';
  }

  Future<List<String>> _loadCoverHistory(String conversationId) async {
    final raw = LocalStorage.getString(_keyCoverHistory(conversationId)) ?? '';
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _rememberCover(String conversationId, String cover) async {
    final text = cover.trim();
    if (text.isEmpty) return;
    final current = await _loadCoverHistory(conversationId);
    final next = [...current, text];
    while (next.length > _coverHistoryMax) {
      next.removeAt(0);
    }
    await LocalStorage.setString(
        _keyCoverHistory(conversationId), jsonEncode(next));
  }

  int _hash(String s) {
    var h = 0;
    for (final code in s.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    return 'm$t';
  }
}
