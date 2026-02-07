import 'dart:convert';

import '../data/local_storage.dart';

class UnlockProfile {
  static const String _kKey = 'veil_unlock_profile_v1';

  final bool tripleTap;
  final bool holdToUnlock;
  final bool pullDownPanel;
  final bool doubleTapTitle;
  final bool tapPattern212;
  final bool tapPattern21;

  const UnlockProfile({
    required this.tripleTap,
    required this.holdToUnlock,
    required this.pullDownPanel,
    required this.doubleTapTitle,
    required this.tapPattern212,
    required this.tapPattern21,
  });

  factory UnlockProfile.defaults() {
    return const UnlockProfile(
      tripleTap: true,
      holdToUnlock: false,
      pullDownPanel: true,
      doubleTapTitle: true,
      tapPattern212: true,
      tapPattern21: true,
    );
  }

  UnlockProfile copyWith({
    bool? tripleTap,
    bool? holdToUnlock,
    bool? pullDownPanel,
    bool? doubleTapTitle,
    bool? tapPattern212,
    bool? tapPattern21,
  }) {
    return UnlockProfile(
      tripleTap: tripleTap ?? this.tripleTap,
      holdToUnlock: holdToUnlock ?? this.holdToUnlock,
      pullDownPanel: pullDownPanel ?? this.pullDownPanel,
      doubleTapTitle: doubleTapTitle ?? this.doubleTapTitle,
      tapPattern212: tapPattern212 ?? this.tapPattern212,
      tapPattern21: tapPattern21 ?? this.tapPattern21,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tripleTap': tripleTap,
      'holdToUnlock': holdToUnlock,
      'pullDownPanel': pullDownPanel,
      'doubleTapTitle': doubleTapTitle,
      'tapPattern212': tapPattern212,
      'tapPattern21': tapPattern21,
    };
  }

  factory UnlockProfile.fromMap(Map<String, dynamic> map) {
    return UnlockProfile(
      tripleTap: map['tripleTap'] == true,
      holdToUnlock: map['holdToUnlock'] == true,
      pullDownPanel: map['pullDownPanel'] == true,
      doubleTapTitle: map['doubleTapTitle'] == true,
      tapPattern212: map['tapPattern212'] == true,
      tapPattern21: map['tapPattern21'] == true,
    );
  }

  static Future<UnlockProfile> load() async {
    final raw = LocalStorage.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) {
      return UnlockProfile.defaults();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final profile = UnlockProfile.fromMap(map);
      return profile.copyWith(holdToUnlock: false);
    } catch (_) {
      return UnlockProfile.defaults();
    }
  }

  Future<void> save() async {
    final raw = jsonEncode(toMap());
    await LocalStorage.setString(_kKey, raw);
  }
}
