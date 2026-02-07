import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../data/local_storage.dart';

class DeviceContact {
  final String id;
  final String displayName;
  final String phone; // può essere vuoto in demo
  final bool isInAddressBook;

  const DeviceContact({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.isInAddressBook,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': displayName,
        'phone': phone,
        'inBook': isInAddressBook,
      };

  static DeviceContact fromMap(Map<String, dynamic> m) {
    return DeviceContact(
      id: (m['id'] ?? '') as String,
      displayName: (m['name'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      isInAddressBook: (m['inBook'] ?? true) as bool,
    );
  }
}

/// Cross-platform service:
/// - Windows/Web: demo list (no permission)
/// - Mobile: per ora demo list (integrazione reale in una V successiva)
class DeviceContactsService {
  static final DeviceContactsService _instance =
      DeviceContactsService._internal();
  factory DeviceContactsService() => _instance;
  DeviceContactsService._internal();

  static const String _kSelectedHidden = 'hidden_contacts_v1';

  // Cache in-memory per lookup veloce
  List<DeviceContact>? _cache;

  /// (Demo) su desktop/web non chiediamo permessi: la UI deve rimanere stabile.
  Future<bool> requestPermissionIfNeeded() async {
    return true;
  }

  /// Ritorna lista contatti disponibile per selezione onboarding.
  Future<List<DeviceContact>> fetchContacts() async {
    // Per ora: lista demo valida su tutte le piattaforme.
    // Nota: id non numerico, phone simulato.
    const demo = <DeviceContact>[
      DeviceContact(
        id: 'ct_alice',
        displayName: 'Alice',
        phone: '+1 202 555 0101',
        isInAddressBook: true,
      ),
      DeviceContact(
        id: 'ct_bob',
        displayName: 'Bob',
        phone: '+1 202 555 0102',
        isInAddressBook: true,
      ),
      DeviceContact(
        id: 'ct_unknown',
        displayName: 'Unknown Number (demo)',
        phone: '+1 202 555 0199',
        isInAddressBook: false,
      ),
    ];

    // In futuro: differenziazione reale per piattaforma + rubrica.
    if (kIsWeb) {
      _cache = demo;
      return demo;
    }

    _cache = demo;
    return demo;
  }

  /// ✅ Metodo richiesto da MessageRepository
  /// Determina se un numero è presente nella "rubrica".
  ///
  /// Per ora (desktop/web) usiamo la demo list:
  /// - se il telefono normalizzato matcha uno dei contatti demo inBook=true => true
  /// - altrimenti false
  ///
  /// In futuro (mobile) questo metodo userà la vera rubrica.
  Future<bool> isPhoneInAddressBook(String phone) async {
    final digits = normalizePhone(phone);
    if (digits.isEmpty) return false;

    // assicura cache
    final list = _cache ?? await fetchContacts();

    for (final c in list) {
      if (!c.isInAddressBook) continue;
      final cd = normalizePhone(c.phone);
      if (cd.isNotEmpty && cd == digits) return true;
    }
    return false;
  }

  /// Selezione contatti "nascosti" salvata in LocalStorage.
  /// Salviamo per ID (non per phone), così resta stabile.
  Future<Set<String>> loadHiddenContactIds() async {
    final raw = LocalStorage.getString(_kSelectedHidden);
    if (raw == null || raw.trim().isEmpty) return <String>{};

    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveHiddenContactIds(Set<String> ids) async {
    final payload = jsonEncode(ids.toList(growable: false));
    await LocalStorage.setString(_kSelectedHidden, payload);
  }

  /// Utility: normalizza un numero (solo cifre)
  static String normalizePhone(String s) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return digits;
  }

  /// (Helper) Se un phone non è in rubrica → per default NON è hidden.
  static bool defaultHiddenForNotInAddressBook(bool isInAddressBook) {
    return isInAddressBook;
  }
}
