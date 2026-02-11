import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../data/local_storage.dart';
import '../models/backup_preview.dart';
import 'audit_log_service.dart';

class BackupService {
  BackupService._();

  static const int version = 1;
  static String? lastExportPath;
  static const String _kLastExportAt = 'veil_backup_last_export_at_v1';
  static const String _kLastImportAt = 'veil_backup_last_import_at_v1';
  static const String _kLastExportPath = 'veil_backup_last_export_path_v1';

  // Keys used by the app
  static const String _kContacts = 'veil_contacts_v2';
  static const String _kConvsAll = 'convs_all_v1';

  // Messages keys are per-conversation:
  // msgs_<conversationId>
  // seeded_<conversationId>
  static String _kMsgs(String cid) => 'msgs_$cid';
  static String _kSeeded(String cid) => 'seeded_$cid';

  // ---------------- EXPORT ----------------

  static Future<bool> exportSaveAs() async {
    try {
      final payload = await _buildBackupPayload();

      final suggestedName = _suggestedFileName();
      final ok = await _savePayloadAs(payload, suggestedName: suggestedName);
      if (ok) {
        await _setLastExport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_export_full',
        status: ok ? 'ok' : 'failed',
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log('backup_export_full', status: 'failed');
      return false;
    }
  }

  static Future<bool> exportContactsOnlySaveAs() async {
    try {
      final payload = await _buildContactsOnlyPayload();
      final suggestedName = _suggestedFileName(prefix: 'veil_contacts_backup');
      final ok = await _savePayloadAs(payload, suggestedName: suggestedName);
      if (ok) {
        await _setLastExport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_export_contacts',
        status: ok ? 'ok' : 'failed',
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log('backup_export_contacts', status: 'failed');
      return false;
    }
  }

  static Future<bool> exportConversationSaveAs({
    required String conversationId,
  }) async {
    try {
      final payload = await _buildConversationPayload(conversationId);
      if (payload == null) return false;
      final suggestedName =
          _suggestedFileName(prefix: 'veil_conversation_backup');
      final ok = await _savePayloadAs(payload, suggestedName: suggestedName);
      if (ok) {
        await _setLastExport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_export_conversation',
        status: ok ? 'ok' : 'failed',
        conversationId: conversationId,
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log(
        'backup_export_conversation',
        status: 'failed',
        conversationId: conversationId,
      );
      return false;
    }
  }

  static Future<bool> _savePayloadAs(
    Map<String, dynamic> payload, {
    required String suggestedName,
  }) async {
    if (Platform.isAndroid) {
      return _savePayloadToDownloads(payload, suggestedName: suggestedName);
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'JSON', extensions: <String>['json']),
      ],
    );

    if (location == null) return false;

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    final xf = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: suggestedName,
    );

    await xf.saveTo(location.path);
    lastExportPath = location.path;
    await LocalStorage.setString(_kLastExportPath, location.path);

    // verify file exists (best-effort)
    try {
      final f = File(location.path);
      if (!await f.exists()) return false;
    } catch (_) {}
    return true;
  }

  static Future<bool> _savePayloadToDownloads(
    Map<String, dynamic> payload, {
    required String suggestedName,
  }) async {
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      final dirCandidates = <String>[
        '/storage/emulated/0/Download',
        '/sdcard/Download',
      ];

      Directory? targetDir;
      for (final path in dirCandidates) {
        final d = Directory(path);
        if (await d.exists()) {
          targetDir = d;
          break;
        }
      }

      targetDir ??= await Directory('/storage/emulated/0/Download').create(
        recursive: true,
      );

      final outPath = '${targetDir.path}/$suggestedName';
      final file = File(outPath);
      await file.writeAsBytes(bytes, flush: true);
      lastExportPath = outPath;
      await LocalStorage.setString(_kLastExportPath, outPath);

      if (!await file.exists()) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _buildBackupPayload() async {
    final contactsRaw = LocalStorage.getString(_kContacts) ?? '';
    final convsRaw = LocalStorage.getString(_kConvsAll) ?? '';

    // Parse conversations to collect IDs (best-effort)
    final convIds = <String>[];
    try {
      final decoded = jsonDecode(convsRaw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final id = (item['id'] ?? '').toString().trim();
            if (id.isNotEmpty) convIds.add(id);
          }
        }
      }
    } catch (_) {}

    final msgsByCid = <String, String>{};
    final seededByCid = <String, String>{};

    for (final cid in convIds) {
      final rawMsgs = LocalStorage.getString(_kMsgs(cid));
      if (rawMsgs != null && rawMsgs.trim().isNotEmpty) {
        msgsByCid[cid] = rawMsgs;
      }
      final rawSeeded = LocalStorage.getString(_kSeeded(cid));
      if (rawSeeded != null && rawSeeded.trim().isNotEmpty) {
        seededByCid[cid] = rawSeeded;
      }
    }

    return <String, dynamic>{
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': <String, dynamic>{
        'contactsRaw': contactsRaw,
        'conversationsRaw': convsRaw,
        'msgsByConversationRaw': msgsByCid,
        'seededByConversationRaw': seededByCid,
      },
    };
  }

  static Future<Map<String, dynamic>> _buildContactsOnlyPayload() async {
    final contactsRaw = LocalStorage.getString(_kContacts) ?? '';
    return <String, dynamic>{
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': <String, dynamic>{
        'contactsRaw': contactsRaw,
        'conversationsRaw': '[]',
        'msgsByConversationRaw': <String, String>{},
        'seededByConversationRaw': <String, String>{},
      },
    };
  }

  static Future<Map<String, dynamic>?> _buildConversationPayload(
      String conversationId) async {
    final convsRaw = LocalStorage.getString(_kConvsAll) ?? '';
    final convsList = _safeList(convsRaw);
    final convMap = convsList.firstWhere(
      (m) => (m['id'] ?? '').toString().trim() == conversationId,
      orElse: () => <String, dynamic>{},
    );
    if (convMap.isEmpty) return null;

    final contactId = (convMap['contactId'] ?? '').toString().trim();
    final contactsRaw = LocalStorage.getString(_kContacts) ?? '';
    String contactsScopedRaw = '[]';
    if (contactId.isNotEmpty) {
      final contactsList = _safeList(contactsRaw);
      final filtered = contactsList
          .where((m) => (m['id'] ?? '').toString().trim() == contactId)
          .toList();
      contactsScopedRaw = jsonEncode(filtered);
    }

    final msgsByCid = <String, String>{};
    final seededByCid = <String, String>{};

    final rawMsgs = LocalStorage.getString(_kMsgs(conversationId));
    if (rawMsgs != null && rawMsgs.trim().isNotEmpty) {
      msgsByCid[conversationId] = rawMsgs;
    }
    final rawSeeded = LocalStorage.getString(_kSeeded(conversationId));
    if (rawSeeded != null && rawSeeded.trim().isNotEmpty) {
      seededByCid[conversationId] = rawSeeded;
    }

    return <String, dynamic>{
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': <String, dynamic>{
        'contactsRaw': contactsScopedRaw,
        'conversationsRaw': jsonEncode([convMap]),
        'msgsByConversationRaw': msgsByCid,
        'seededByConversationRaw': seededByCid,
      },
    };
  }

  static String _suggestedFileName({String prefix = 'veil_backup'}) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '${prefix}_$y$m${day}_$hh$mm.json';
  }

  // ---------------- IMPORT: PICK + PREVIEW ----------------

  static Future<PickedBackup?> pickBackupForImport() async {
    try {
      final xf = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
      );
      if (xf == null) return null;

      final bytes = await xf.readAsBytes();
      if (bytes.isEmpty) return null;

      final decoded = _decodeBackup(bytes);
      if (decoded == null) return null;

      final preview = _buildPreviewFromDecoded(
        decoded,
        fileName: xf.name,
        byteLength: bytes.length,
      );

      if (preview.version != version) return null;

      return PickedBackup(
        bytes: bytes,
        fileName: xf.name,
        byteLength: bytes.length,
        preview: preview,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<FileSystemEntity>> listDownloadBackups() async {
    if (!Platform.isAndroid) return const [];
    try {
      final dirCandidates = <String>[
        '/storage/emulated/0/Download',
        '/sdcard/Download',
      ];
      Directory? targetDir;
      for (final path in dirCandidates) {
        final d = Directory(path);
        if (await d.exists()) {
          targetDir = d;
          break;
        }
      }
      if (targetDir == null) return const [];
      final files = await targetDir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
          .toList();
      return files;
    } catch (_) {
      return const [];
    }
  }

  static Future<PickedBackup?> readBackupFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final decoded = _decodeBackup(bytes);
      if (decoded == null) return null;

      final name = path.split(Platform.pathSeparator).last;
      final preview = _buildPreviewFromDecoded(
        decoded,
        fileName: name,
        byteLength: bytes.length,
      );
      if (preview.version != version) return null;

      return PickedBackup(
        bytes: bytes,
        fileName: name,
        byteLength: bytes.length,
        preview: preview,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------- IMPORT: APPLY ----------------

  static Future<bool> applyImportBytes(
    Uint8List bytes, {
    required ImportMode mode,
  }) async {
    try {
      final decoded = _decodeBackup(bytes);
      if (decoded == null) return false;
      final ok = await _applyImportDecoded(decoded, mode: mode);
      if (ok) {
        await _setLastImport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_import_full',
        status: ok ? 'ok' : 'failed',
        note: mode.name,
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log(
        'backup_import_full',
        status: 'failed',
        note: mode.name,
      );
      return false;
    }
  }

  static Future<bool> applyImportContactsBytes(
    Uint8List bytes, {
    required ImportMode mode,
  }) async {
    try {
      final decoded = _decodeBackup(bytes);
      if (decoded == null) return false;
      final ok = await _applyImportContactsOnly(decoded, mode: mode);
      if (ok) {
        await _setLastImport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_import_contacts',
        status: ok ? 'ok' : 'failed',
        note: mode.name,
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log(
        'backup_import_contacts',
        status: 'failed',
        note: mode.name,
      );
      return false;
    }
  }

  static Future<ContactImportReport?> previewContactsImport(
    Uint8List bytes, {
    required ImportMode mode,
  }) async {
    try {
      final decoded = _decodeBackup(bytes);
      if (decoded == null) return null;

      final v = decoded['version'];
      if (v is! int || v != version) return null;

      final data = decoded['data'];
      if (data is! Map) return null;
      final d = data.cast<String, dynamic>();
      final contactsRaw = (d['contactsRaw'] ?? '') as String;

      final incomingCount = _countListFromRawJson(contactsRaw);
      if (mode == ImportMode.replace) {
        return ContactImportReport(
          mode: mode,
          incomingCount: incomingCount,
          newCount: incomingCount,
          mergedCount: 0,
        );
      }

      final existingRaw = LocalStorage.getString(_kContacts) ?? '';
      return _analyzeContactsMerge(
        existingRaw: existingRaw,
        incomingRaw: contactsRaw,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> applyImportConversationsBytes(
    Uint8List bytes, {
    required ImportMode mode,
  }) async {
    try {
      final decoded = _decodeBackup(bytes);
      if (decoded == null) return false;
      final ok = await _applyImportConversationsOnly(decoded, mode: mode);
      if (ok) {
        await _setLastImport(DateTime.now());
      }
      await AuditLogService.I.log(
        'backup_import_conversations',
        status: ok ? 'ok' : 'failed',
        note: mode.name,
      );
      return ok;
    } catch (_) {
      await AuditLogService.I.log(
        'backup_import_conversations',
        status: 'failed',
        note: mode.name,
      );
      return false;
    }
  }

  static Map<String, dynamic>? _decodeBackup(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static BackupPreview _buildPreviewFromDecoded(
    Map<String, dynamic> root, {
    String? fileName,
    int? byteLength,
  }) {
    final v = (root['version'] is int) ? root['version'] as int : -1;

    DateTime exportedAt = DateTime.now();
    final rawDate = root['exportedAt']?.toString();
    if (rawDate != null && rawDate.trim().isNotEmpty) {
      exportedAt = DateTime.tryParse(rawDate.trim()) ?? DateTime.now();
    }

    int contactsCount = 0;
    int convsCount = 0;
    int messagesCount = 0;
    int attachmentsCount = 0;

    final data = root['data'];
    if (data is Map) {
      final dataMap = data.cast<String, dynamic>();

      final contactsRaw = (dataMap['contactsRaw'] ?? '') as String;
      contactsCount = _countListFromRawJson(contactsRaw);

      final convsRaw = (dataMap['conversationsRaw'] ?? '') as String;
      convsCount = _countListFromRawJson(convsRaw);

      final msgsBy = dataMap['msgsByConversationRaw'];
      if (msgsBy is Map) {
        for (final e in msgsBy.entries) {
          final raw = e.value?.toString() ?? '';
          messagesCount += _countListFromRawJson(raw);
        }
      }
    }

    return BackupPreview(
      version: v,
      exportedAt: exportedAt,
      contactsCount: contactsCount,
      conversationsCount: convsCount,
      messagesCount: messagesCount,
      attachmentsCount: attachmentsCount,
      fileName: fileName,
      byteLength: byteLength,
    );
  }

  static Future<BackupPreview> buildLocalPreview() async {
    final payload = await _buildBackupPayload();
    return _buildPreviewFromDecoded(payload);
  }

  static DateTime? getLastExportAt() {
    final raw = LocalStorage.getString(_kLastExportAt);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  static DateTime? getLastImportAt() {
    final raw = LocalStorage.getString(_kLastImportAt);
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  static String? getLastExportPath() {
    final raw = LocalStorage.getString(_kLastExportPath);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  static Future<void> _setLastExport(DateTime when) async {
    await LocalStorage.setString(_kLastExportAt, when.toIso8601String());
  }

  static Future<void> _setLastImport(DateTime when) async {
    await LocalStorage.setString(_kLastImportAt, when.toIso8601String());
  }

  static int _countListFromRawJson(String raw) {
    try {
      if (raw.trim().isEmpty) return 0;
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.length;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> _applyImportDecoded(
    Map<String, dynamic> root, {
    required ImportMode mode,
  }) async {
    final v = root['version'];
    if (v is! int || v != version) return false;

    final data = root['data'];
    if (data is! Map) return false;
    final d = data.cast<String, dynamic>();

    final contactsRaw = (d['contactsRaw'] ?? '') as String;
    final convsRaw = (d['conversationsRaw'] ?? '') as String;

    final msgsByCid = <String, String>{};
    final seededByCid = <String, String>{};

    final rawMsgs = d['msgsByConversationRaw'];
    if (rawMsgs is Map) {
      for (final e in rawMsgs.entries) {
        final k = e.key.toString().trim();
        final v2 = e.value?.toString() ?? '';
        if (k.isNotEmpty && v2.trim().isNotEmpty) {
          msgsByCid[k] = v2;
        }
      }
    }

    final rawSeeded = d['seededByConversationRaw'];
    if (rawSeeded is Map) {
      for (final e in rawSeeded.entries) {
        final k = e.key.toString().trim();
        final v2 = e.value?.toString() ?? '';
        if (k.isNotEmpty && v2.trim().isNotEmpty) {
          seededByCid[k] = v2;
        }
      }
    }

    if (mode == ImportMode.replace) {
      await LocalStorage.setString(_kContacts, contactsRaw);
      await LocalStorage.setString(_kConvsAll, convsRaw);

      for (final entry in msgsByCid.entries) {
        await LocalStorage.setString(_kMsgs(entry.key), entry.value);
      }
      for (final entry in seededByCid.entries) {
        await LocalStorage.setString(_kSeeded(entry.key), entry.value);
      }
      return true;
    }

    final mergedContactsRaw = _mergeContactsSmart(
      existingRaw: LocalStorage.getString(_kContacts) ?? '',
      incomingRaw: contactsRaw,
    );
    await LocalStorage.setString(_kContacts, mergedContactsRaw);

    final mergedConvsRaw = _mergeListById(
      existingRaw: LocalStorage.getString(_kConvsAll) ?? '',
      incomingRaw: convsRaw,
    );
    await LocalStorage.setString(_kConvsAll, mergedConvsRaw);

    for (final entry in msgsByCid.entries) {
      final cid = entry.key;
      final incomingMsgsRaw = entry.value;

      final existingMsgsRaw = LocalStorage.getString(_kMsgs(cid)) ?? '';
      final mergedMsgsRaw = _mergeListById(
        existingRaw: existingMsgsRaw,
        incomingRaw: incomingMsgsRaw,
      );
      await LocalStorage.setString(_kMsgs(cid), mergedMsgsRaw);

      await LocalStorage.setString(_kSeeded(cid), '1');
    }

    return true;
  }

  static Future<bool> _applyImportContactsOnly(
    Map<String, dynamic> root, {
    required ImportMode mode,
  }) async {
    final v = root['version'];
    if (v is! int || v != version) return false;

    final data = root['data'];
    if (data is! Map) return false;
    final d = data.cast<String, dynamic>();

    final contactsRaw = (d['contactsRaw'] ?? '') as String;
    if (contactsRaw.trim().isEmpty) return false;

    if (mode == ImportMode.replace) {
      await LocalStorage.setString(_kContacts, contactsRaw);
      return true;
    }

    final mergedContactsRaw = _mergeContactsSmart(
      existingRaw: LocalStorage.getString(_kContacts) ?? '',
      incomingRaw: contactsRaw,
    );
    await LocalStorage.setString(_kContacts, mergedContactsRaw);
    return true;
  }

  static Future<bool> _applyImportConversationsOnly(
    Map<String, dynamic> root, {
    required ImportMode mode,
  }) async {
    final v = root['version'];
    if (v is! int || v != version) return false;

    final data = root['data'];
    if (data is! Map) return false;
    final d = data.cast<String, dynamic>();

    final convsRaw = (d['conversationsRaw'] ?? '') as String;
    final contactsRaw = (d['contactsRaw'] ?? '') as String;

    final msgsByCid = <String, String>{};
    final seededByCid = <String, String>{};

    final rawMsgs = d['msgsByConversationRaw'];
    if (rawMsgs is Map) {
      for (final e in rawMsgs.entries) {
        final k = e.key.toString().trim();
        final v2 = e.value?.toString() ?? '';
        if (k.isNotEmpty && v2.trim().isNotEmpty) {
          msgsByCid[k] = v2;
        }
      }
    }

    final rawSeeded = d['seededByConversationRaw'];
    if (rawSeeded is Map) {
      for (final e in rawSeeded.entries) {
        final k = e.key.toString().trim();
        final v2 = e.value?.toString() ?? '';
        if (k.isNotEmpty && v2.trim().isNotEmpty) {
          seededByCid[k] = v2;
        }
      }
    }

    if (convsRaw.trim().isNotEmpty) {
      final mergedConvsRaw = _mergeListById(
        existingRaw: LocalStorage.getString(_kConvsAll) ?? '',
        incomingRaw: convsRaw,
      );
      await LocalStorage.setString(_kConvsAll, mergedConvsRaw);
    }

    if (contactsRaw.trim().isNotEmpty) {
      final mergedContactsRaw = _mergeContactsSmart(
        existingRaw: LocalStorage.getString(_kContacts) ?? '',
        incomingRaw: contactsRaw,
      );
      await LocalStorage.setString(_kContacts, mergedContactsRaw);
    }

    for (final entry in msgsByCid.entries) {
      final cid = entry.key;
      final incomingMsgsRaw = entry.value;

      if (mode == ImportMode.replace) {
        await LocalStorage.setString(_kMsgs(cid), incomingMsgsRaw);
      } else {
        final existingMsgsRaw = LocalStorage.getString(_kMsgs(cid)) ?? '';
        final mergedMsgsRaw = _mergeListById(
          existingRaw: existingMsgsRaw,
          incomingRaw: incomingMsgsRaw,
        );
        await LocalStorage.setString(_kMsgs(cid), mergedMsgsRaw);
      }

      await LocalStorage.setString(_kSeeded(cid), '1');
    }

    return true;
  }

  static String _mergeListById({
    required String existingRaw,
    required String incomingRaw,
  }) {
    try {
      final existing = _safeList(existingRaw);
      final incoming = _safeList(incomingRaw);

      final byId = <String, Map<String, dynamic>>{};
      for (final m in existing) {
        final id = (m['id'] ?? '').toString().trim();
        if (id.isNotEmpty) byId[id] = m;
      }
      for (final m in incoming) {
        final id = (m['id'] ?? '').toString().trim();
        if (id.isNotEmpty) byId[id] = m;
      }

      final out = byId.values.toList(growable: false);
      return jsonEncode(out);
    } catch (_) {
      return incomingRaw;
    }
  }

  static String _mergeContactsSmart({
    required String existingRaw,
    required String incomingRaw,
  }) {
    try {
      final existing = _safeList(existingRaw);
      final incoming = _safeList(incomingRaw);

      final byId = <String, Map<String, dynamic>>{};
      final phoneToId = <String, String>{};
      final nameToId = <String, String>{};

      void indexContact(Map<String, dynamic> c) {
        final id = (c['id'] ?? '').toString().trim();
        if (id.isEmpty) return;
        byId[id] = c;

        final phoneKey = _normalizedPhone(c['phone']);
        if (phoneKey != null) phoneToId[phoneKey] = id;

        final nameKey =
            _normalizedName(c['realName']) ?? _normalizedName(c['coverName']);
        if (nameKey != null) nameToId[nameKey] = id;
      }

      for (final c in existing) {
        indexContact(Map<String, dynamic>.from(c));
      }

      for (final c in incoming) {
        final incomingMap = Map<String, dynamic>.from(c);
        final incomingId = (incomingMap['id'] ?? '').toString().trim();
        if (incomingId.isEmpty) continue;

        String? targetId;
        if (byId.containsKey(incomingId)) {
          targetId = incomingId;
        } else {
          final phoneKey = _normalizedPhone(incomingMap['phone']);
          if (phoneKey != null) {
            targetId = phoneToId[phoneKey];
          }
          if (targetId == null) {
            final nameKey = _normalizedName(incomingMap['realName']) ??
                _normalizedName(incomingMap['coverName']);
            if (nameKey != null) {
              targetId = nameToId[nameKey];
            }
          }
        }

        if (targetId == null) {
          indexContact(incomingMap);
          continue;
        }

        final existingMap = byId[targetId] ?? <String, dynamic>{'id': targetId};
        final merged =
            _mergeContactRecord(existingMap, incomingMap, keepId: targetId);
        byId[targetId] = merged;
        indexContact(merged);
      }

      return jsonEncode(byId.values.toList(growable: false));
    } catch (_) {
      return incomingRaw;
    }
  }

  static ContactImportReport _analyzeContactsMerge({
    required String existingRaw,
    required String incomingRaw,
  }) {
    try {
      final existing = _safeList(existingRaw);
      final incoming = _safeList(incomingRaw);

      final byId = <String, Map<String, dynamic>>{};
      final phoneToId = <String, String>{};
      final nameToId = <String, String>{};

      void indexContact(Map<String, dynamic> c) {
        final id = (c['id'] ?? '').toString().trim();
        if (id.isEmpty) return;
        byId[id] = c;

        final phoneKey = _normalizedPhone(c['phone']);
        if (phoneKey != null) phoneToId[phoneKey] = id;

        final nameKey =
            _normalizedName(c['realName']) ?? _normalizedName(c['coverName']);
        if (nameKey != null) nameToId[nameKey] = id;
      }

      for (final c in existing) {
        indexContact(Map<String, dynamic>.from(c));
      }

      var newCount = 0;
      var mergedCount = 0;

      for (final c in incoming) {
        final incomingMap = Map<String, dynamic>.from(c);
        final incomingId = (incomingMap['id'] ?? '').toString().trim();
        if (incomingId.isEmpty) continue;

        String? targetId;
        if (byId.containsKey(incomingId)) {
          targetId = incomingId;
        } else {
          final phoneKey = _normalizedPhone(incomingMap['phone']);
          if (phoneKey != null) {
            targetId = phoneToId[phoneKey];
          }
          if (targetId == null) {
            final nameKey = _normalizedName(incomingMap['realName']) ??
                _normalizedName(incomingMap['coverName']);
            if (nameKey != null) {
              targetId = nameToId[nameKey];
            }
          }
        }

        if (targetId == null) {
          newCount += 1;
          indexContact(incomingMap);
          continue;
        }

        mergedCount += 1;
        final existingMap = byId[targetId] ?? <String, dynamic>{'id': targetId};
        final merged =
            _mergeContactRecord(existingMap, incomingMap, keepId: targetId);
        byId[targetId] = merged;
        indexContact(merged);
      }

      return ContactImportReport(
        mode: ImportMode.merge,
        incomingCount: incoming.length,
        newCount: newCount,
        mergedCount: mergedCount,
      );
    } catch (_) {
      return ContactImportReport(
        mode: ImportMode.merge,
        incomingCount: _countListFromRawJson(incomingRaw),
        newCount: 0,
        mergedCount: 0,
      );
    }
  }

  static Map<String, dynamic> _mergeContactRecord(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming, {
    required String keepId,
  }) {
    final out = Map<String, dynamic>.from(existing);
    out['id'] = keepId;

    for (final e in incoming.entries) {
      if (e.key == 'id') continue;
      final value = e.value;
      if (_hasMeaningfulValue(value)) {
        out[e.key] = value;
      } else if (!out.containsKey(e.key)) {
        out[e.key] = value;
      }
    }
    return out;
  }

  static bool _hasMeaningfulValue(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true;
  }

  static String? _normalizedPhone(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return null;
    return normalized;
  }

  static String? _normalizedName(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    return normalized;
  }

  static List<Map<String, dynamic>> _safeList(String raw) {
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is Map) out.add(item.cast<String, dynamic>());
    }
    return out;
  }
}

class PickedBackup {
  final Uint8List bytes;
  final String fileName;
  final int byteLength;
  final BackupPreview preview;

  const PickedBackup({
    required this.bytes,
    required this.fileName,
    required this.byteLength,
    required this.preview,
  });
}

class ContactImportReport {
  final ImportMode mode;
  final int incomingCount;
  final int newCount;
  final int mergedCount;

  const ContactImportReport({
    required this.mode,
    required this.incomingCount,
    required this.newCount,
    required this.mergedCount,
  });
}
