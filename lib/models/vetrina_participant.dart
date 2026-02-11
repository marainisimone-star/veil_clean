class VetrinaParticipant {
  VetrinaParticipant({
    required this.userId,
    required this.status,
    required this.lastWarningAt,
    required this.warningsCount,
    this.acceptedRulesAt,
  });

  final String userId;
  final String status; // active | warned | restricted | excluded
  final DateTime? lastWarningAt;
  final int warningsCount;
  final DateTime? acceptedRulesAt;

  factory VetrinaParticipant.fromMap(String id, Map<String, dynamic> map) {
    final legacyStrike = (map['strikeCount'] is int)
        ? map['strikeCount'] as int
        : int.tryParse(map['strikeCount']?.toString() ?? '') ?? 0;
    return VetrinaParticipant(
      userId: id,
      status: (map['status'] ?? 'active').toString(),
      lastWarningAt: _asDate(map['lastWarningAt']),
      warningsCount: (map['warningsCount'] is int)
          ? map['warningsCount'] as int
          : int.tryParse(map['warningsCount']?.toString() ?? '') ?? legacyStrike,
      acceptedRulesAt: _asDate(map['acceptedRulesAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'lastWarningAt': lastWarningAt?.millisecondsSinceEpoch,
      'warningsCount': warningsCount,
      'acceptedRulesAt': acceptedRulesAt?.millisecondsSinceEpoch,
    };
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    final parsed = int.tryParse(v.toString());
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    return null;
  }
}
