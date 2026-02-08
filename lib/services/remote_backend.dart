abstract class RemoteBackend {
  Future<void> init();

  Future<String?> signInEmail({
    required String email,
    required String password,
  });

  Future<String?> registerEmail({
    required String email,
    required String password,
  });

  Stream<RemoteMessage> messagesStream({
    required String conversationId,
  });

  Future<void> sendMessage(RemoteMessage message);

  Future<void> setConversationHiddenForUser({
    required String uid,
    required String conversationId,
    required bool hidden,
  });
}

class RemoteMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final bool hidden;
  final DateTime createdAt;

  const RemoteMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.hidden,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'text': text,
        'hidden': hidden,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static RemoteMessage fromMap(Map<String, dynamic> m) {
    return RemoteMessage(
      id: (m['id'] ?? '').toString(),
      conversationId: (m['conversationId'] ?? '').toString(),
      senderId: (m['senderId'] ?? '').toString(),
      text: (m['text'] ?? '').toString(),
      hidden: (m['hidden'] ?? false) == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse((m['createdAt'] ?? '').toString()) ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
