import 'dart:ui';

import '../data/local_storage.dart';

class BubbleUnlockPattern {
  final List<int> sequence;
  final List<Offset> path;

  const BubbleUnlockPattern(this.sequence, {this.path = const []});

  bool get isGesture => path.length >= 4;
  bool get isSet => isGesture || sequence.length >= 3;

  static const String _kPattern = 'veil_bubble_unlock_pattern_v1';

  static Future<BubbleUnlockPattern> load() async {
    final raw = LocalStorage.getString(_kPattern);
    if (raw == null || raw.trim().isEmpty) {
      return const BubbleUnlockPattern(<int>[]);
    }
    final trimmed = raw.trim();
    if (trimmed.startsWith('g:')) {
      final payload = trimmed.substring(2);
      final pts = <Offset>[];
      for (final pair in payload.split(';')) {
        final parts = pair.split(',');
        if (parts.length != 2) continue;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x == null || y == null) continue;
        pts.add(Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0)));
      }
      return BubbleUnlockPattern(const [], path: pts);
    }
    final parts =
        trimmed.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final seq = parts.where((v) => v >= 1 && v <= 9).toList(growable: false);
    return BubbleUnlockPattern(seq);
  }

  static Future<void> save(List<int> sequence) async {
    final cleaned = sequence.where((v) => v >= 1 && v <= 9).toList(growable: false);
    await LocalStorage.setString(_kPattern, cleaned.join(','));
  }

  static Future<void> saveGesture(List<Offset> path) async {
    final cleaned = path
        .map((p) => Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)))
        .toList(growable: false);
    final encoded = cleaned.map((p) => '${p.dx.toStringAsFixed(4)},${p.dy.toStringAsFixed(4)}').join(';');
    await LocalStorage.setString(_kPattern, 'g:$encoded');
  }

  static Future<void> clear() async {
    await LocalStorage.remove(_kPattern);
  }
}
