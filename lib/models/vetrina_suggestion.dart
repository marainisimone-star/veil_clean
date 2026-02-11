class VetrinaSuggestion {
  VetrinaSuggestion({
    required this.id,
    required this.sourceVetrinaId,
    required this.suggestedTitle,
    required this.reason,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String sourceVetrinaId;
  final String suggestedTitle;
  final String reason;
  final DateTime createdAt;
  final String status; // pending | accepted | dismissed

  factory VetrinaSuggestion.fromMap(String id, Map<String, dynamic> map) {
    return VetrinaSuggestion(
      id: id,
      sourceVetrinaId: (map['sourceVetrinaId'] ?? '').toString(),
      suggestedTitle: (map['suggestedTitle'] ?? '').toString(),
      reason: (map['reason'] ?? '').toString(),
      createdAt: _asDate(map['createdAt']),
      status: (map['status'] ?? 'pending').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sourceVetrinaId': sourceVetrinaId,
      'suggestedTitle': suggestedTitle,
      'reason': reason,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status,
    };
  }

  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    final parsed = int.tryParse(v.toString());
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    return DateTime.now();
  }
}
