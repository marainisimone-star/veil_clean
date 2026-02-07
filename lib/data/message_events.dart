import '../models/message.dart';

enum MessageEventType {
  added,
  updated,
  removed,
}

class MessageEvent {
  final MessageEventType type;
  final Message message;

  const MessageEvent({
    required this.type,
    required this.message,
  });
}
