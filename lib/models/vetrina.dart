class Vetrina {
  Vetrina({
    required this.id,
    required this.title,
    required this.theme,
    required this.tags,
    required this.creatorId,
    required this.createdAt,
    required this.visibility,
    required this.status,
    required this.coreRules,
    required this.ruleOptions,
    required this.guidelines,
    required this.quizEnabled,
    required this.quizLink,
    required this.rulesCoreVersion,
    required this.rulesCustom,
    required this.accessPolicy,
    required this.parentVetrinaId,
    required this.counters,
    required this.ranking,
    required this.coverTone,
    required this.coverUrl,
  });

  final String id;
  final String title;
  final String theme;
  final List<String> tags;
  final String creatorId;
  final DateTime createdAt;
  final String visibility;
  final String status;
  final List<String> coreRules;
  final Map<String, bool> ruleOptions;
  final List<String> guidelines;
  final bool quizEnabled;
  final String? quizLink;
  final String rulesCoreVersion;
  final Map<String, dynamic> rulesCustom;
  final Map<String, dynamic> accessPolicy;
  final String? parentVetrinaId;
  final Map<String, dynamic> counters;
  final Map<String, dynamic> ranking;
  final String? coverTone;
  final String? coverUrl;

  factory Vetrina.fromMap(String id, Map<String, dynamic> map) {
    final rawCoreRules = (map['coreRules'] is List) ? (map['coreRules'] as List) : const [];
    final rawOptions = (map['ruleOptions'] is Map)
        ? Map<String, dynamic>.from(map['ruleOptions'])
        : const <String, dynamic>{};
    final rawGuidelines = (map['guidelines'] is List) ? (map['guidelines'] as List) : const [];
    return Vetrina(
      id: id,
      title: (map['title'] ?? '').toString(),
      theme: (map['theme'] ?? '').toString(),
      tags: (map['tags'] is List) ? (map['tags'] as List).map((e) => e.toString()).toList() : const [],
      creatorId: (map['creatorId'] ?? '').toString(),
      createdAt: _asDate(map['createdAt']),
      visibility: (map['visibility'] ?? 'public').toString(),
      status: (map['status'] ?? 'active').toString(),
      coreRules: rawCoreRules.map((e) => e.toString()).toList(),
      ruleOptions: rawOptions.map((key, value) => MapEntry(key, value == true)),
      guidelines: rawGuidelines.map((e) => e.toString()).toList(),
      quizEnabled: map['quizEnabled'] == true || map['quizOptional'] == true,
      quizLink: map['quizLink']?.toString(),
      rulesCoreVersion: (map['rulesCoreVersion'] ?? 'v1').toString(),
      rulesCustom: (map['rulesCustom'] is Map) ? Map<String, dynamic>.from(map['rulesCustom']) : <String, dynamic>{},
      accessPolicy: (map['accessPolicy'] is Map) ? Map<String, dynamic>.from(map['accessPolicy']) : <String, dynamic>{},
      parentVetrinaId: map['parentVetrinaId']?.toString(),
      counters: (map['counters'] is Map) ? Map<String, dynamic>.from(map['counters']) : <String, dynamic>{},
      ranking: (map['ranking'] is Map) ? Map<String, dynamic>.from(map['ranking']) : <String, dynamic>{},
      coverTone: map['coverTone']?.toString(),
      coverUrl: map['coverUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'theme': theme,
      'tags': tags,
      'creatorId': creatorId,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'visibility': visibility,
      'status': status,
      'coreRules': coreRules,
      'ruleOptions': ruleOptions,
      'guidelines': guidelines,
      'quizEnabled': quizEnabled,
      'quizLink': quizLink,
      'rulesCoreVersion': rulesCoreVersion,
      'rulesCustom': rulesCustom,
      'accessPolicy': accessPolicy,
      'parentVetrinaId': parentVetrinaId,
      'counters': counters,
      'ranking': ranking,
      'coverTone': coverTone,
      'coverUrl': coverUrl,
    };
  }

  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    final s = v.toString().trim();
    final parsed = int.tryParse(s);
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    return DateTime.now();
  }
}
