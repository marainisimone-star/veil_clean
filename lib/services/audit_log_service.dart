import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../data/local_storage.dart';

class AuditLogService {
  AuditLogService._();

  static final AuditLogService I = AuditLogService._();

  static const String _kAuditLog = 'veil_audit_log_v1';
  static const int _maxEntries = 200;

  Future<void> log(
    String event, {
    String? status,
    String? conversationId,
    String? note,
  }) async {
    try {
      final list = _readRawList();
      list.add({
        'ts': DateTime.now().toIso8601String(),
        'event': event,
        'status': (status ?? '').trim(),
        'conversationId': (conversationId ?? '').trim(),
        'note': (note ?? '').trim(),
      });

      if (list.length > _maxEntries) {
        final trimmed = list.sublist(list.length - _maxEntries);
        await LocalStorage.setString(_kAuditLog, jsonEncode(trimmed));
        return;
      }

      await LocalStorage.setString(_kAuditLog, jsonEncode(list));
    } catch (_) {
      // Never crash for audit trail failures.
    }
  }

  Future<List<AuditLogEntry>> readRecent({int limit = 30}) async {
    final out = <AuditLogEntry>[];
    try {
      final list = _readRawList();
      final start = (list.length - limit).clamp(0, list.length);
      final recent = list.sublist(start);

      for (final m in recent.reversed) {
        final tsRaw = (m['ts'] ?? '').toString().trim();
        final dt = DateTime.tryParse(tsRaw) ?? DateTime.now();
        out.add(
          AuditLogEntry(
            timestamp: dt,
            event: (m['event'] ?? '').toString().trim(),
            status: (m['status'] ?? '').toString().trim(),
            conversationId: (m['conversationId'] ?? '').toString().trim(),
            note: (m['note'] ?? '').toString().trim(),
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  Future<void> clear() async {
    try {
      await LocalStorage.remove(_kAuditLog);
    } catch (_) {}
  }

  Future<bool> exportSaveAs() async {
    try {
      final rows = _readRawList();
      final payload = <String, dynamic>{
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'entries': rows,
      };

      final location = await getSaveLocation(
        suggestedName: _suggestedFileName(),
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
        name: _suggestedFileName(),
      );
      await xf.saveTo(location.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _readRawList() {
    final raw = LocalStorage.getString(_kAuditLog) ?? '';
    if (raw.trim().isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is Map) {
        out.add(item.cast<String, dynamic>());
      }
    }
    return out;
  }

  String _suggestedFileName() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return 'veil_audit_log_$y$m${d}_$hh$mm.json';
  }
}

class AuditLogEntry {
  final DateTime timestamp;
  final String event;
  final String status;
  final String conversationId;
  final String note;

  const AuditLogEntry({
    required this.timestamp,
    required this.event,
    required this.status,
    required this.conversationId,
    required this.note,
  });
}
