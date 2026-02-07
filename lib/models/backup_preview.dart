class BackupPreview {
  final int version;
  final DateTime exportedAt;

  // Optional file metadata (nice to show in UI)
  final String? fileName;
  final int? byteLength;

  final int contactsCount;
  final int conversationsCount;
  final int messagesCount;
  final int attachmentsCount;

  const BackupPreview({
    required this.version,
    required this.exportedAt,
    required this.contactsCount,
    required this.conversationsCount,
    required this.messagesCount,
    required this.attachmentsCount,
    this.fileName,
    this.byteLength,
  });
}

/// Import strategy chosen by the user.
enum ImportMode {
  /// Replace contacts + conversations + messages included in the backup.
  replace,

  /// Merge backup into current data (safer).
  merge,
}
