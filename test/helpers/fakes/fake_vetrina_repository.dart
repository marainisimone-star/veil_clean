import 'package:veil_clean/models/vetrina.dart';
import 'package:veil_clean/models/vetrina_message.dart';
import 'package:veil_clean/models/vetrina_post.dart';
import 'package:veil_clean/services/vetrina_repository_base.dart';

class FakeVetrinaRepository implements VetrinaRepositoryBase {
  FakeVetrinaRepository({
    List<Vetrina>? vetrine,
    Map<String, Vetrina>? byId,
    Map<String, List<VetrinaMessage>>? messagesByVetrinaId,
    Map<String, List<VetrinaPost>>? postsByVetrinaId,
    this.addMessageResult = 'ok',
  })  : _vetrine = vetrine ?? [sampleVetrina()],
        _byId = byId ?? {'v1': sampleVetrina()},
        _messagesByVetrinaId = messagesByVetrinaId ?? _defaultMessages(),
        _postsByVetrinaId = postsByVetrinaId ?? _defaultPosts();

  final List<Vetrina> _vetrine;
  final Map<String, Vetrina> _byId;
  final Map<String, List<VetrinaMessage>> _messagesByVetrinaId;
  final Map<String, List<VetrinaPost>> _postsByVetrinaId;
  final String addMessageResult;

  String? lastSentText;
  String? lastSentVetrinaId;
  String? lastAccessRequestVetrinaId;

  @override
  Future<String> addMessage({required String vetrinaId, required String text}) async {
    lastSentText = text;
    lastSentVetrinaId = vetrinaId;
    return addMessageResult;
  }

  @override
  Future<bool> deleteVetrina(String vetrinaId) async => true;

  @override
  Future<List<Vetrina>> fetchVetrine() async => _vetrine;

  @override
  Future<Vetrina?> getById(String id) async => _byId[id];

  @override
  Future<bool> promote(String vetrinaId) async => true;

  @override
  Future<void> requestAccess(String vetrinaId) async {
    lastAccessRequestVetrinaId = vetrinaId;
  }

  @override
  Stream<List<VetrinaMessage>> watchMessages(String vetrinaId) {
    return Stream.value(_messagesByVetrinaId[vetrinaId] ?? const <VetrinaMessage>[]);
  }

  @override
  Stream<List<VetrinaPost>> watchPosts(String vetrinaId) {
    return Stream.value(_postsByVetrinaId[vetrinaId] ?? const <VetrinaPost>[]);
  }

  static Vetrina sampleVetrina({
    String id = 'v1',
    String title = 'Test Showcase',
  }) {
    return Vetrina(
      id: id,
      title: title,
      theme: 'Science',
      tags: const ['test', 'science'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 1, 1),
      visibility: 'public',
      status: 'active',
      coreRules: const ['no_insults', 'no_discrimination', 'be_civil'],
      ruleOptions: const {
        'cite_sources_5w': true,
        'stay_on_topic': true,
        'respect_expertise': false,
        'no_spam': true,
      },
      guidelines: const ['Use sources'],
      quizEnabled: false,
      quizLink: null,
      rulesCoreVersion: 'v1',
      rulesCustom: const <String, dynamic>{},
      accessPolicy: const <String, dynamic>{},
      parentVetrinaId: null,
      counters: const <String, dynamic>{},
      ranking: const <String, dynamic>{},
      coverTone: 'amber',
      coverUrl: null,
    );
  }

  static Map<String, List<VetrinaMessage>> _defaultMessages() {
    return {
      'v1': [
        VetrinaMessage(
          id: 'm1',
          userId: 'u1',
          text: 'Latest message from fake repo',
          createdAt: DateTime(2026, 1, 1, 10, 0),
          ai: const {'moderation': 'ok', 'flags': <String>[]},
          meta: const <String, dynamic>{},
        ),
        VetrinaMessage(
          id: 'm2',
          userId: 'u2',
          text: 'Hello from fake repo',
          createdAt: DateTime(2026, 1, 1, 9, 0),
          ai: const {'moderation': 'ok', 'flags': <String>[]},
          meta: const <String, dynamic>{},
        ),
      ],
    };
  }

  static Map<String, List<VetrinaPost>> _defaultPosts() {
    return {
      'v1': [
        VetrinaPost(
          id: 'p1',
          type: 'text',
          label: 'Intro',
          status: 'published',
          createdAt: DateTime(2026, 1, 1, 8, 0),
          text: 'Showcase intro from fake repo',
        ),
      ],
    };
  }
}
