import '../models/conversation.dart';
import 'conversation_store.dart';

class ConversationRepository {
  const ConversationRepository();

  Future<List<Conversation>> getInbox() async {
    return ConversationStore().getAllSorted();
  }

  Future<Conversation?> getById(String id) async {
    return ConversationStore().getById(id);
  }
}
