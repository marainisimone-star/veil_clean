class VetrinaMessage {
  VetrinaMessage({
    required this.id,
    required this.userId,
    required this.text,
    required this.createdAt,
    required this.ai,
    required this.meta,
  });

  final String id;
  final String userId;
  final String text;
  final DateTime createdAt;
  final Map<String, dynamic> ai;
  final Map<String, dynamic> meta;

  factory VetrinaMessage.fromMap(String id, Map<String, dynamic> map) {
    return VetrinaMessage(
      id: id,
      userId: (map['userId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      createdAt: _asDate(map['createdAt']),
      ai: (map['ai'] is Map) ? Map<String, dynamic>.from(map['ai']) : <String, dynamic>{},
      meta: (map['meta'] is Map) ? Map<String, dynamic>.from(map['meta']) : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'text': text,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'ai': ai,
      'meta': meta,
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
