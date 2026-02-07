import 'dart:convert';

import '../data/local_storage.dart';
import '../models/conversation.dart';
import '../models/group_member.dart';

class ConversationStore {
  static final ConversationStore _instance = ConversationStore._internal();
  factory ConversationStore() => _instance;
  ConversationStore._internal();

  static const String _kAll = 'convs_all_v1';

  String newId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    return 't$t';
  }

  String newGroupMemberId() {
    final t = DateTime.now().microsecondsSinceEpoch;
    return 'gm$t';
  }

  // ---------------- PUBLIC API ----------------

  Future<List<Conversation>> getAllSorted() async {
    final all = await _getAll();
    final sorted = [...all];
    sorted.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return sorted;
  }

  Future<Conversation?> getById(String id) async {
    final all = await _getAll();
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<Conversation> createConversation({required String title}) async {
    final now = DateTime.now();

    final conv = Conversation(
      id: newId(),
      title: title.trim(),
      lastMessage: '',
      lastUpdated: now,
      unreadCount: 0,
    );

    final all = await _getAll();
    await _save([...all, conv]);
    return conv;
  }

  Future<Conversation> createGroup({required String title}) async {
    final now = DateTime.now();
    final me = GroupMember(id: 'me', name: 'You', isAdmin: true);

    final conv = Conversation(
      id: newId(),
      title: title.trim().isEmpty ? 'Group' : title.trim(),
      lastMessage: '',
      lastUpdated: now,
      unreadCount: 0,
      isGroup: true,
      groupMembers: [me],
    );

    final all = await _getAll();
    await _save([...all, conv]);
    return conv;
  }

  Future<Conversation> getOrCreateForContact({
    required String contactId,
    required String fallbackTitle,
  }) async {
    final all = await _getAll();

    for (final c in all) {
      if ((c.contactId ?? '') == contactId) {
        return c;
      }
    }

    final now = DateTime.now();
    final conv = Conversation(
      id: newId(),
      title: fallbackTitle.trim().isEmpty ? 'Contact' : fallbackTitle.trim(),
      lastMessage: '',
      lastUpdated: now,
      unreadCount: 0,
      contactId: contactId,
    );

    await _save([...all, conv]);
    return conv;
  }

  Future<void> updateLastMessage({
    required String conversationId,
    required String lastMessage,
    required DateTime when,
    int? unreadCount,
  }) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(
        lastMessage: lastMessage,
        lastUpdated: when,
        unreadCount: unreadCount ?? c.unreadCount,
      );
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> markRead(String conversationId) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(unreadCount: 0);
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> removeConversation(String conversationId) async {
    final all = await _getAll();
    final next = all.where((c) => c.id != conversationId).toList(growable: false);
    await _save(next);
  }

  Future<void> clearConversation({
    required String conversationId,
    DateTime? when,
  }) async {
    final all = await _getAll();
    final now = when ?? DateTime.now();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(
        lastMessage: '',
        lastUpdated: now,
        unreadCount: 0,
      );
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> setCoverStyle(String conversationId, CoverStyle style) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(coverStyle: style);
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> setMessageTtl({
    required String conversationId,
    int? minutes,
  }) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(messageTtlMinutes: minutes);
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> setHidden({
    required String conversationId,
    required bool hidden,
  }) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(isHidden: hidden);
    }).toList(growable: false);

    await _save(next);
  }

  Future<void> setGroupMembers({
    required String conversationId,
    required List<GroupMember> members,
  }) async {
    final all = await _getAll();

    final next = all.map((c) {
      if (c.id != conversationId) return c;
      return c.copyWith(groupMembers: members, isGroup: true);
    }).toList(growable: false);

    await _save(next);
  }

  // ---------------- INTERNAL PERSISTENCE ----------------

  Future<List<Conversation>> _getAll() async {
    final raw = LocalStorage.getString(_kAll);
    if (raw == null || raw.trim().isEmpty) return const [];

    final list = (jsonDecode(raw) as List).cast<dynamic>();
    final out = list
        .whereType<Map>()
        .map((m) => Conversation.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);

    return out;
  }

  Future<void> _save(List<Conversation> list) async {
    final payload = jsonEncode(list.map((c) => c.toMap()).toList(growable: false));
    await LocalStorage.setString(_kAll, payload);
  }
}
