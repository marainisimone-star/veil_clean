import '../crypto/crypto_service.dart';
import 'attachment_ref.dart';

enum MessageContentMode {
  dual,
  plain,
}

MessageContentMode _modeFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'plain':
      return MessageContentMode.plain;
    case 'dual':
    default:
      return MessageContentMode.dual;
  }
}

String _modeToString(MessageContentMode m) {
  return (m == MessageContentMode.plain) ? 'plain' : 'dual';
}

class Message {
  final String id;
  final String conversationId;

  /// Cover/innocuo
  final String coverText;

  /// (Legacy/compat) Some parts of the UI used `text` in the past.
  /// Keep it for backward compatibility. We mirror `coverText` into it.
  final String text;

  /// Encrypted real content (base64 etc.), used when unlocked.
  final CipherPack? real;

  final MessageContentMode mode;
  final bool isMe;
  final DateTime timestamp;
  final String status;

  /// Optional single attachment reference
  final AttachmentRef? attachment;

  /// Optional author info (for group chats)
  final String? authorId;
  final String? authorName;

  const Message({
    required this.id,
    required this.conversationId,
    required this.coverText,
    required this.real,
    required this.mode,
    required this.isMe,
    required this.timestamp,
    required this.status,
    this.attachment,
    this.authorId,
    this.authorName,
  }) : text = coverText;

  Message copyWith({
    String? id,
    String? conversationId,
    String? coverText,
    CipherPack? real,
    MessageContentMode? mode,
    bool? isMe,
    DateTime? timestamp,
    String? status,
    AttachmentRef? attachment,
    bool clearAttachment = false,
    String? authorId,
    String? authorName,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      coverText: coverText ?? this.coverText,
      real: real ?? this.real,
      mode: mode ?? this.mode,
      isMe: isMe ?? this.isMe,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'coverText': coverText,
        'text': text, // backward compatible
        'real': real?.toMap(),
        'mode': _modeToString(mode),
        'isMe': isMe,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'attachment': attachment?.toMap(),
        'authorId': authorId,
        'authorName': authorName,
      };

  static Message fromMap(Map<String, dynamic> m) {
    final cover = (m['coverText'] ?? m['text'] ?? '').toString();

    CipherPack? pack;
    final rawReal = m['real'];
    if (rawReal is Map) {
      pack = CipherPack.fromMap(rawReal.cast<String, dynamic>());
    }

    AttachmentRef? att;
    final rawAtt = m['attachment'];
    if (rawAtt is Map) {
      att = AttachmentRef.fromMap(rawAtt.cast<String, dynamic>());
    }

    return Message(
      id: (m['id'] ?? '').toString(),
      conversationId: (m['conversationId'] ?? '').toString(),
      coverText: cover,
      real: pack,
      mode: _modeFromString(m['mode']?.toString()),
      isMe: (m['isMe'] ?? false) == true,
      timestamp: DateTime.tryParse((m['timestamp'] ?? '').toString()) ?? DateTime.now(),
      status: (m['status'] ?? 'sent').toString(),
      attachment: att,
      authorId: (m['authorId'] ?? '').toString().isEmpty ? null : (m['authorId'] ?? '').toString(),
      authorName: (m['authorName'] ?? '').toString().isEmpty ? null : (m['authorName'] ?? '').toString(),
    );
  }
}
