import 'dart:convert';

import '../data/local_storage.dart';
import '../models/contact.dart';

class ContactRepository {
  static const String _kContacts = 'veil_contacts_v2';

  String newId() => 'c${DateTime.now().microsecondsSinceEpoch}';

  Future<List<Contact>> getAll() async {
    try {
      final raw = LocalStorage.getString(_kContacts);
      if (raw == null || raw.trim().isEmpty) return const [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final out = <Contact>[];
      for (final item in decoded) {
        try {
          if (item is Map<String, dynamic>) {
            out.add(Contact.fromJson(item));
          } else if (item is Map) {
            out.add(Contact.fromJson(item.map((k, v) => MapEntry(k.toString(), v))));
          }
        } catch (_) {
          // Non bloccare tutta la lista se un record è vecchio/corrotto.
          continue;
        }
      }

      // Sort innocuo: coverName
      out.sort((a, b) => a.coverName.toLowerCase().compareTo(b.coverName.toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<Contact?> getById(String contactId) async {
    final all = await getAll();
    for (final c in all) {
      if (c.id == contactId) return c;
    }
    return null;
  }

  Future<void> upsert(Contact c) async {
    final all = await getAll();
    final idx = all.indexWhere((x) => x.id == c.id);

    final next = List<Contact>.from(all);
    if (idx >= 0) {
      next[idx] = c;
    } else {
      next.add(c);
    }

    await _save(next);
  }

  Future<void> delete(String contactId) async {
    final all = await getAll();
    final next = all.where((c) => c.id != contactId).toList(growable: false);
    await _save(next);
  }

  Future<void> _save(List<Contact> items) async {
    final encoded = jsonEncode(items.map((c) => c.toJson()).toList(growable: false));
    await LocalStorage.setString(_kContacts, encoded);
  }
}
