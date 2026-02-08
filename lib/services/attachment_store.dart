import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';

import '../crypto/crypto_service.dart';
import '../data/local_storage.dart';
import '../models/attachment_ref.dart';

class AttachmentStore {
  AttachmentStore._();

  static const String _kAttPrefix = 'att_pack_'; // att_pack_<cid>_<attId>

  static String _key(String conversationId, String attachmentId) =>
      '$_kAttPrefix${conversationId}_$attachmentId';

  static String _newId() => 'a${DateTime.now().microsecondsSinceEpoch}';

  /// Pick a file, encrypt bytes (base64 string) into CipherPack,
  /// persist to LocalStorage, return a reference to attach to a message.
  static Future<AttachmentRef?> importFromPicker({
    required String conversationId,
  }) async {
    try {
      final xf = await openFile();
      if (xf == null) return null;

      final bytes = await xf.readAsBytes();
      if (bytes.isEmpty) return null;

      final fileName = xf.name.isNotEmpty ? xf.name : 'file';
      final mime = xf.mimeType;

      final b64 = base64Encode(bytes);

      final pack = await CryptoService().encrypt(
        conversationId: conversationId,
        plaintext: b64,
      );

      final attId = _newId();

      // Save pack JSON
      final raw = jsonEncode(pack.toMap());
      await LocalStorage.setString(_key(conversationId, attId), raw);

      return AttachmentRef(
        id: attId,
        fileName: fileName,
        byteLength: bytes.length,
        mimeType: mime,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Encrypt raw bytes into CipherPack, persist to LocalStorage,
  /// return a reference to attach to a message.
  static Future<AttachmentRef?> importFromBytes({
    required String conversationId,
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    try {
      if (bytes.isEmpty) return null;

      final safeName = fileName.trim().isNotEmpty ? fileName.trim() : 'file';
      final b64 = base64Encode(bytes);

      final pack = await CryptoService().encrypt(
        conversationId: conversationId,
        plaintext: b64,
      );

      final attId = _newId();

      final raw = jsonEncode(pack.toMap());
      await LocalStorage.setString(_key(conversationId, attId), raw);

      return AttachmentRef(
        id: attId,
        fileName: safeName,
        byteLength: bytes.length,
        mimeType: mimeType,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<File>> listDownloadFiles() async {
    if (!Platform.isAndroid) return const [];
    try {
      final candidates = <String>[
        '/storage/emulated/0/Download',
        '/sdcard/Download',
      ];
      Directory? dir;
      for (final path in candidates) {
        final d = Directory(path);
        if (await d.exists()) {
          dir = d;
          break;
        }
      }
      if (dir == null) return const [];

      final files = await dir
          .list()
          .where((e) => e is File)
          .map((e) => e as File)
          .toList();

      files.sort((a, b) {
        final as = a.statSync();
        final bs = b.statSync();
        return bs.modified.compareTo(as.modified);
      });

      return files;
    } catch (_) {
      return const [];
    }
  }

  static Future<AttachmentRef?> importFromPath({
    required String conversationId,
    required String path,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final fileName = path.split(Platform.pathSeparator).last;

      final b64 = base64Encode(bytes);

      final pack = await CryptoService().encrypt(
        conversationId: conversationId,
        plaintext: b64,
      );

      final attId = _newId();

      // Save pack JSON
      final raw = jsonEncode(pack.toMap());
      await LocalStorage.setString(_key(conversationId, attId), raw);

      return AttachmentRef(
        id: attId,
        fileName: fileName.isNotEmpty ? fileName : 'file',
        byteLength: bytes.length,
        mimeType: null,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Decrypt and write to temp, open with OS, then delete temp (best-effort).
  static Future<void> openAttachment({
    required String conversationId,
    required AttachmentRef ref,
  }) async {
    Directory? dir;
    String? outPath;

    try {
      final raw = LocalStorage.getString(_key(conversationId, ref.id));
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final pack = CipherPack.fromMap(decoded.cast<String, dynamic>());

      final clearB64 = await CryptoService().decrypt(
        conversationId: conversationId,
        pack: pack,
      );

      final bytes = base64Decode(clearB64);
      if (bytes.isEmpty) return;

      // Create a unique temp folder for this open action
      dir = Directory.systemTemp.createTempSync('veil_att_');
      outPath = '${dir.path}${Platform.pathSeparator}${ref.fileName}';

      final f = File(outPath);
      await f.writeAsBytes(bytes, flush: true);

      // Open with OS default handler
      if (Platform.isWindows) {
        // Use cmd start; it returns immediately
        await Process.start('cmd', ['/c', 'start', '', outPath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [outPath]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [outPath]);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await OpenFilex.open(outPath);
      } else {
        // Unsupported platform: do nothing else
        return;
      }

      // ✅ Delay wipe slightly so Windows has time to open the file
      _wipeTempPathLater(outPath, dirPath: dir.path);
    } catch (_) {
      // If anything fails, still try cleanup if we created stuff
      if (outPath != null && dir != null) {
        _wipeTempPathNow(outPath, dirPath: dir.path);
      }
    }
  }

  static Future<void> deleteAttachment({
    required String conversationId,
    required String attachmentId,
  }) async {
    try {
      await LocalStorage.remove(_key(conversationId, attachmentId));
    } catch (_) {}
  }

  // ----------------- Temp wipe helpers -----------------

  static void _wipeTempPathLater(
    String filePath, {
    required String dirPath,
  }) {
    const delay = Duration(seconds: 3);
    Timer(delay, () {
      _wipeTempPathNow(filePath, dirPath: dirPath);
    });
  }

  /// Tries to delete the file. If the OS/app locks it briefly,
  /// retries a few times and then gives up silently.
  static void _wipeTempPathNow(
    String filePath, {
    required String dirPath,
  }) {
    const maxAttempts = 8; // short window (~4s total)
    const step = Duration(milliseconds: 500);

    int attempt = 0;

    Future<void> tryDelete() async {
      attempt += 1;

      try {
        final f = File(filePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {
        // ignore
      }

      // try delete folder too (will fail if file still locked or app created extra files)
      try {
        final d = Directory(dirPath);
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      } catch (_) {
        // ignore
      }

      // If still exists and we have attempts left, retry
      final stillFile = await File(filePath).exists().catchError((_) => false);
      final stillDir = await Directory(dirPath).exists().catchError((_) => false);

      if ((stillFile || stillDir) && attempt < maxAttempts) {
        Timer(step, () {
          // fire-and-forget
          tryDelete();
        });
      }
    }

    // 🔥 Immediate attempt
    // ignore: discarded_futures
    tryDelete();
  }
}
