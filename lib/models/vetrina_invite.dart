class VetrinaInvite {
  VetrinaInvite({
    required this.id,
    required this.inviterId,
    required this.targetEmail,
    required this.targetUserId,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String inviterId;
  final String? targetEmail;
  final String? targetUserId;
  final DateTime createdAt;
  final String status; // sent | accepted | expired

  factory VetrinaInvite.fromMap(String id, Map<String, dynamic> map) {
    return VetrinaInvite(
      id: id,
      inviterId: (map['inviterId'] ?? '').toString(),
      targetEmail: map['targetEmail']?.toString(),
      targetUserId: map['targetUserId']?.toString(),
      createdAt: _asDate(map['createdAt']),
      status: (map['status'] ?? 'sent').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inviterId': inviterId,
      'targetEmail': targetEmail,
      'targetUserId': targetUserId,
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
