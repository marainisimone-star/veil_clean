// lib/data/local_storage.dart
//
// Local storage WITHOUT shared_preferences.
// Data is stored in a JSON file on disk.
// This is stable on Windows and desktop.
//
// IMPORTANT:
// Call `await LocalStorage.init();` ONCE in main() before runApp().

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  static bool _initialized = false;
  static final Map<String, String> _cache = {};

  static File? _file;
  static SharedPreferences? _prefs;

  /// Must be called once at startup
  static Future<void> init() async {
    if (_initialized) return;

    if (_useSharedPrefs) {
      _prefs = await SharedPreferences.getInstance();
      _cache.clear();
      final keys = _prefs!.getKeys();
      for (final k in keys) {
        final v = _prefs!.getString(k);
        if (v != null) {
          _cache[k] = v;
        }
      }
    } else {
      _file = File(_resolvePath());
      await _ensureDirectory(_file!);

      if (await _file!.exists()) {
        try {
          final raw = await _file!.readAsString();
          if (raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              _cache.clear();
              decoded.forEach((k, v) {
                if (k is String && v is String) {
                  _cache[k] = v;
                }
              });
            }
          }
        } catch (_) {
          // Corrupted file → start clean (fail-safe)
          _cache.clear();
        }
      }
    }

    _initialized = true;
  }

  static String? getString(String key) {
    return _cache[key];
  }

  static Future<void> setString(String key, String value) async {
    _cache[key] = value;
    await _flush();
  }

  static Future<void> remove(String key) async {
    _cache.remove(key);
    if (_useSharedPrefs && _prefs != null) {
      await _prefs!.remove(key);
    }
    await _flush();
  }

  // ---------------- Internal ----------------

  static String _resolvePath() {
    // Prefer Windows AppData if available
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\veil_clean\\storage.json';
    }

    // Fallback: current directory
    return '${Directory.current.path}${Platform.pathSeparator}veil_clean_storage.json';
  }

  static Future<void> _ensureDirectory(File file) async {
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  static Future<void> _flush() async {
    if (_useSharedPrefs) {
      if (_prefs == null) return;
      for (final entry in _cache.entries) {
        await _prefs!.setString(entry.key, entry.value);
      }
      return;
    }

    if (_file == null) return;

    try {
      final json = jsonEncode(_cache);
      await _file!.writeAsString(json, flush: true);
    } catch (_) {
      // Never crash the app because of storage
    }
  }

  static bool get _useSharedPrefs {
    if (kIsWeb) return true;
    return !(Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  }
}
