class VetrinaPost {
  VetrinaPost({
    required this.id,
    required this.type,
    required this.label,
    required this.status,
    required this.createdAt,
    this.text,
    this.url,
    this.localPath,
    this.mimeType,
  });

  final String id;
  final String type; // photo | video | document | live | text | link
  final String label;
  final String status; // pending_upload | published
  final DateTime createdAt;
  final String? text;
  final String? url;
  final String? localPath;
  final String? mimeType;

  factory VetrinaPost.fromMap(String id, Map<String, dynamic> map) {
    return VetrinaPost(
      id: id,
      type: (map['type'] ?? 'text').toString(),
      label: (map['label'] ?? '').toString(),
      status: (map['status'] ?? 'pending_upload').toString(),
      createdAt: _asDate(map['createdAt']),
      text: map['text']?.toString(),
      url: map['url']?.toString(),
      localPath: map['localPath']?.toString(),
      mimeType: map['mimeType']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'label': label,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'text': text,
      'url': url,
      'localPath': localPath,
      'mimeType': mimeType,
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
