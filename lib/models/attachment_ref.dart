class AttachmentRef {
  final String id; // unique per attachment
  final String fileName;
  final int byteLength;
  final String? mimeType;
  final DateTime createdAt;

  const AttachmentRef({
    required this.id,
    required this.fileName,
    required this.byteLength,
    required this.createdAt,
    this.mimeType,
  });

  AttachmentRef copyWith({
    String? id,
    String? fileName,
    int? byteLength,
    String? mimeType,
    DateTime? createdAt,
  }) {
    return AttachmentRef(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      byteLength: byteLength ?? this.byteLength,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'byteLength': byteLength,
        'mimeType': mimeType,
        'createdAt': createdAt.toIso8601String(),
      };

  static AttachmentRef fromMap(Map<String, dynamic> m) {
    return AttachmentRef(
      id: (m['id'] ?? '').toString(),
      fileName: (m['fileName'] ?? '').toString(),
      byteLength: (m['byteLength'] ?? 0) as int,
      mimeType: (m['mimeType'] as String?),
      createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}
