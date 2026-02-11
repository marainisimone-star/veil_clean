import '../models/vetrina.dart';
import '../models/vetrina_message.dart';
import '../models/vetrina_post.dart';

abstract class VetrinaRepositoryBase {
  Future<List<Vetrina>> fetchVetrine();
  Future<Vetrina?> getById(String id);
  Stream<List<VetrinaMessage>> watchMessages(String vetrinaId);
  Stream<List<VetrinaPost>> watchPosts(String vetrinaId);
  Future<String> addMessage({
    required String vetrinaId,
    required String text,
  });
  Future<bool> promote(String vetrinaId);
  Future<bool> deleteVetrina(String vetrinaId);
  Future<void> requestAccess(String vetrinaId);
}
