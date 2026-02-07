import 'dart:convert';

import '../data/local_storage.dart';

class CoverAiSettings {
  final bool enabled;
  final String languageMode; // 'auto' | 'it' | 'en'

  const CoverAiSettings({
    required this.enabled,
    required this.languageMode,
  });

  factory CoverAiSettings.defaults() {
    return const CoverAiSettings(enabled: true, languageMode: 'auto');
  }

  CoverAiSettings copyWith({bool? enabled, String? languageMode}) {
    return CoverAiSettings(
      enabled: enabled ?? this.enabled,
      languageMode: languageMode ?? this.languageMode,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'languageMode': languageMode,
      };

  factory CoverAiSettings.fromMap(Map<String, dynamic> map) {
    return CoverAiSettings(
      enabled: map['enabled'] == true,
      languageMode: (map['languageMode'] ?? 'auto').toString(),
    );
  }
}

class CoverAiService {
  CoverAiService._();

  static final CoverAiService I = CoverAiService._();

  static const String _kSettings = 'veil_cover_ai_settings_v1';
  static const String _kLangPrefix = 'veil_cover_lang_';

  Future<CoverAiSettings> loadSettings() async {
    final raw = LocalStorage.getString(_kSettings);
    if (raw == null || raw.trim().isEmpty) {
      return CoverAiSettings.defaults();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CoverAiSettings.fromMap(map);
    } catch (_) {
      return CoverAiSettings.defaults();
    }
  }

  Future<void> saveSettings(CoverAiSettings settings) async {
    final raw = jsonEncode(settings.toMap());
    await LocalStorage.setString(_kSettings, raw);
  }

  String resolveLanguageHint(String text, {String? override}) {
    if (override == 'it' || override == 'en') return override!;
    return detectLanguage(text);
  }

  String resolveLanguageHintForConversation(
    String text,
    String conversationId, {
    String? override,
    String? fallback,
  }) {
    if (override == 'it' || override == 'en') return override!;
    final trimmed = text.trim();
    if (trimmed.length < 8) {
      final last = _getLastLang(conversationId);
      if (last != null) return last;
      if (fallback == 'it' || fallback == 'en') return fallback!;
    }
    return detectLanguage(text);
  }

  /// Genera cover localmente (nessuna API). Ritorna null se disabilitato.
  Future<String?> generateCover({
    required String realText,
    required String conversationId,
    required String languageHint,
    required bool businessTone,
    required bool outgoing,
    required List<String> recentCovers,
    String? contactName,
    List<String>? groupMembers,
    CoverAiSettings? settings,
  }) async {
    final resolved = settings ?? await loadSettings();
    if (!resolved.enabled) return null;

    final lang = resolveLanguageHintForConversation(
      realText,
      conversationId,
      override: resolved.languageMode,
      fallback: languageHint,
    );
    _setLastLang(conversationId, lang);
    final topic = _inferTopic(realText, isBusiness: businessTone, lang: lang);
    final person = _inferPerson(
      contactName: contactName,
      groupMembers: groupMembers,
      conversationId: conversationId,
      lang: lang,
    );
    final when = _inferTimeHint(lang: lang);

    final templates = _templates(
      outgoing: outgoing,
      isBusiness: businessTone,
      topic: topic,
      person: person,
      when: when,
      lang: lang,
    );

    final baseSeed = _hash(
      '$conversationId|$realText|${businessTone ? 'biz' : 'priv'}|${recentCovers.length}|${DateTime.now().minute}|$outgoing|$lang',
    );

    for (var i = 0; i < templates.length; i++) {
      final idx = (baseSeed + i) % templates.length;
      final candidate = templates[idx].trim();
      if (candidate.isEmpty) continue;
      if (!_isRecentDuplicate(candidate, recentCovers)) {
        return candidate;
      }
    }

    return templates[baseSeed % templates.length].trim();
  }

  String _keyLastLang(String conversationId) => '$_kLangPrefix$conversationId';

  String? _getLastLang(String conversationId) {
    final v = LocalStorage.getString(_keyLastLang(conversationId));
    if (v == null || v.trim().isEmpty) return null;
    if (v != 'it' && v != 'en') return null;
    return v;
  }

  void _setLastLang(String conversationId, String lang) {
    if (lang != 'it' && lang != 'en') return;
    LocalStorage.setString(_keyLastLang(conversationId), lang);
  }


  // ---------------- Language ----------------

  String detectLanguage(String text) {
    final lower = text.toLowerCase();
    if (_scoreItalian(lower) >= _scoreEnglish(lower)) return 'it';
    return 'en';
  }

  int _scoreItalian(String text) {
    var score = 0;
    const markers = [
      ' che ',
      ' non ',
      ' per ',
      ' con ',
      ' una ',
      ' come ',
      ' qui ',
      ' quindi ',
      ' allora ',
      ' grazie ',
      ' ok ',
      ' ciao ',
      ' domani ',
      ' oggi ',
      ' dopo ',
      ' stasera ',
      ' riun',
      ' fattur',
      ' consegna',
      ' progetto',
    ];
    for (final m in markers) {
      if (text.contains(m)) score += 2;
    }
    const chars = ['à', 'è', 'é', 'ì', 'ò', 'ù'];
    for (final c in chars) {
      if (text.contains(c)) score += 3;
    }
    return score;
  }

  int _scoreEnglish(String text) {
    var score = 0;
    const markers = [
      ' the ',
      ' and ',
      ' for ',
      ' with ',
      ' you ',
      ' hi ',
      ' hello ',
      ' thanks ',
      ' ok ',
      ' tomorrow ',
      ' today ',
      ' later ',
      ' meeting ',
      ' invoice ',
      ' project ',
      ' delivery ',
      ' update ',
    ];
    for (final m in markers) {
      if (text.contains(m)) score += 2;
    }
    return score;
  }

  // ---------------- Templates ----------------

  String _inferTopic(String real, {required bool isBusiness, required String lang}) {
    final l = real.toLowerCase();

    if (l.contains('contract') || l.contains('contratt') || l.contains('nda')) {
      return isBusiness ? (lang == 'it' ? 'il contratto' : 'the contract') : (lang == 'it' ? 'i documenti' : 'the docs');
    }
    if (l.contains('budget') || l.contains('costo') || l.contains('preventiv')) {
      return isBusiness ? (lang == 'it' ? 'il budget' : 'the budget') : (lang == 'it' ? 'le spese' : 'the costs');
    }
    if (l.contains('deadline') || l.contains('scadenza') || l.contains('urgent')) {
      return isBusiness ? (lang == 'it' ? 'la scadenza' : 'the deadline') : (lang == 'it' ? 'i tempi' : 'timing');
    }
    if (l.contains('client') || l.contains('cliente') || l.contains('partner')) {
      return isBusiness ? (lang == 'it' ? 'il cliente' : 'the client') : (lang == 'it' ? 'la persona' : 'the person');
    }
    if (l.contains('support') || l.contains('ticket') || l.contains('bug')) {
      return isBusiness ? (lang == 'it' ? 'il supporto' : 'support') : (lang == 'it' ? 'il problema' : 'the issue');
    }
    if (l.contains('present') || l.contains('slide') || l.contains('deck')) {
      return isBusiness ? (lang == 'it' ? 'la presentazione' : 'the deck') : (lang == 'it' ? 'il materiale' : 'the material');
    }
    if (l.contains('viaggio') || l.contains('flight') || l.contains('hotel')) {
      return isBusiness ? (lang == 'it' ? 'la trasferta' : 'the trip') : (lang == 'it' ? 'il viaggio' : 'the trip');
    }
    if (l.contains('spesa') || l.contains('cena') || l.contains('pranzo')) {
      return isBusiness ? (lang == 'it' ? 'le note spese' : 'expenses') : (lang == 'it' ? 'il programma' : 'the plan');
    }
    if (l.contains('family') || l.contains('famiglia') || l.contains('casa')) {
      return isBusiness ? (lang == 'it' ? 'l’agenda' : 'the agenda') : (lang == 'it' ? 'la casa' : 'home');
    }
    if (l.contains('meeting') || l.contains('riun') || l.contains('call')) {
      return isBusiness ? (lang == 'it' ? 'la riunione' : 'the meeting') : (lang == 'it' ? 'l’organizzazione' : 'the plan');
    }
    if (l.contains('doc') || l.contains('file') || l.contains('report')) {
      return isBusiness ? (lang == 'it' ? 'il documento' : 'the document') : (lang == 'it' ? 'quel file' : 'that file');
    }
    if (l.contains('pag') || l.contains('invoice') || l.contains('fattur')) {
      return isBusiness ? (lang == 'it' ? 'la parte amministrativa' : 'billing') : (lang == 'it' ? 'i conti' : 'payments');
    }
    if (l.contains('sped') || l.contains('delivery') || l.contains('ordine')) {
      return isBusiness ? (lang == 'it' ? 'la consegna' : 'delivery') : (lang == 'it' ? 'l’ordine' : 'the order');
    }

    if (isBusiness) return lang == 'it' ? 'la pratica' : 'the task';
    return lang == 'it' ? 'la cosa' : 'that thing';
  }

  String _inferPerson({
    required String? contactName,
    required List<String>? groupMembers,
    required String conversationId,
    required String lang,
  }) {
    final members = groupMembers ?? const [];
    final others = members.where((n) => n.trim().isNotEmpty).toList(growable: false);
    if (others.isNotEmpty) {
      return others[_hash(conversationId + others.length.toString()) % others.length];
    }
    final c = (contactName ?? '').trim();
    if (c.isNotEmpty) return c;
    return lang == 'it' ? 'te' : 'you';
  }

  String _inferTimeHint({required String lang}) {
    final h = DateTime.now().hour;
    if (lang == 'it') {
      if (h < 12) return 'in mattinata';
      if (h < 18) return 'nel pomeriggio';
      return 'più tardi';
    }
    if (h < 12) return 'this morning';
    if (h < 18) return 'this afternoon';
    return 'later';
  }

  List<String> _templates({
    required bool outgoing,
    required bool isBusiness,
    required String topic,
    required String person,
    required String when,
    required String lang,
  }) {
    if (lang == 'en') {
      if (isBusiness) {
        if (outgoing) {
          return <String>[
            'Got it, I’ll handle $topic.',
            'Perfect, I’ll update $person $when.',
            'OK, I’m on it and will follow up.',
            'Confirmed, I’ll take the next step on $topic.',
            'Understood, I’ll check and get back to you.',
          ];
        }
        return <String>[
          'OK, received about $topic.',
          'Perfect, thanks for the update.',
          'Understood, we’ll proceed.',
          'All clear, let’s sync $when.',
        ];
      }
      if (outgoing) {
        return <String>[
          'Ok, I’ll take care of it $when.',
          'Got it, I’ll let you know soon.',
          'Sounds good, I’ll check and reply.',
          'Perfect, I’ll handle $topic.',
        ];
      }
      return <String>[
        'Ok, perfect.',
        'Sure, thanks.',
        'Got it.',
        'Alright, talk $when.',
      ];
    }

    // Italian
    if (isBusiness) {
      if (outgoing) {
        return <String>[
          'Ricevuto, procedo su $topic.',
          'Perfetto, aggiorno $person $when.',
          'Chiaro, prendo in carico e ti allineo.',
          'Ok, mi attivo ora e chiudo appena pronto.',
          'Confermato, tengo traccia e condivido update.',
        ];
      }
      return <String>[
        'Ok, ricevuto su $topic.',
        'Perfetto, resto allineato.',
        'Chiaro, grazie per l’update.',
        'Confermato, procediamo così.',
      ];
    }

    if (outgoing) {
      return <String>[
        'Ok, ci penso io $when.',
        'Perfetto, poi aggiorno $person.',
        'Va bene, facciamo così su $topic.',
        'Ricevuto, ti scrivo appena riesco.',
      ];
    }

    return <String>[
      'Ok, perfetto.',
      'Va bene, grazie.',
      'Chiaro, ricevuto.',
      'Tutto ok, ci sentiamo $when.',
    ];
  }

  bool _isRecentDuplicate(String candidate, List<String> recentCovers) {
    final c = _normalizeCover(candidate);
    final tail = recentCovers.reversed.take(8);
    for (final r in tail) {
      if (_normalizeCover(r) == c) return true;
    }
    return false;
  }

  String _normalizeCover(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), ' ');
  }

  int _hash(String s) {
    var h = 0;
    for (final code in s.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }
}
