import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/vetrina.dart';
import '../models/vetrina_message.dart';
import '../models/vetrina_post.dart';
import '../services/firebase_backend.dart';
import 'vetrina_ranker.dart';
import 'app_logger.dart';
import '../data/local_storage.dart';
import 'vetrina_repository_base.dart';

class VetrinaRepository implements VetrinaRepositoryBase {
  VetrinaRepository._();
  static final VetrinaRepository I = VetrinaRepository._();

  final _db = FirebaseFirestore.instance;

  @override
  Future<List<Vetrina>> fetchVetrine() async {
    try {
      await FirebaseBackend.I.init();
      final snap = await _db.collection('vetrine').limit(50).get();
      final list = snap.docs.map((d) => Vetrina.fromMap(d.id, d.data())).toList();
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      AppLogger.w('Vetrina fetch failed, using mock', error: e, stackTrace: st);
    }
    return _mockVetrine();
  }

  @override
  Future<Vetrina?> getById(String id) async {
    try {
      await FirebaseBackend.I.init();
      final doc = await _db.collection('vetrine').doc(id).get();
      if (!doc.exists) return null;
      return Vetrina.fromMap(doc.id, doc.data() ?? const {});
    } catch (e, st) {
      AppLogger.w('Vetrina get failed', error: e, stackTrace: st);
      return null;
    }
  }

  @override
  Stream<List<VetrinaMessage>> watchMessages(String vetrinaId) {
    return _db
        .collection('vetrine')
        .doc(vetrinaId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) => snap.docs.map((d) => VetrinaMessage.fromMap(d.id, d.data())).toList());
  }

  Future<VetrinaMessage?> fetchLatestMessage(String vetrinaId) async {
    try {
      await FirebaseBackend.I.init();
      final snap = await _db
          .collection('vetrine')
          .doc(vetrinaId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return VetrinaMessage.fromMap(doc.id, doc.data());
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<List<VetrinaPost>> watchPosts(String vetrinaId) {
    return _db
        .collection('vetrine')
        .doc(vetrinaId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => snap.docs.map((d) => VetrinaPost.fromMap(d.id, d.data())).toList());
  }

  Future<VetrinaPost?> fetchLatestPost(String vetrinaId) async {
    try {
      await FirebaseBackend.I.init();
      final snap = await _db
          .collection('vetrine')
          .doc(vetrinaId)
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return VetrinaPost.fromMap(doc.id, doc.data());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> addMessage({
    required String vetrinaId,
    required String text,
  }) async {
    try {
      await FirebaseBackend.I.init();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 'auth';
      final clean = text.trim();
      if (clean.isEmpty) return 'empty';

      final vRef = _db.collection('vetrine').doc(vetrinaId);
      final pRef = vRef.collection('participants').doc(uid);
      final vSnap = await vRef.get();
      if (!vSnap.exists) return 'missing';

      final vData = vSnap.data() ?? const <String, dynamic>{};
      final ruleOptions = (vData['ruleOptions'] is Map)
          ? Map<String, dynamic>.from(vData['ruleOptions'])
          : const <String, dynamic>{};

      final pSnap = await pRef.get();
      final pData = pSnap.data() ?? const <String, dynamic>{};
      final currentStatus = (pData['status'] ?? 'active').toString();
      var warningsCount = (pData['warningsCount'] is int)
          ? pData['warningsCount'] as int
          : int.tryParse(pData['warningsCount']?.toString() ?? '') ?? 0;

      if (currentStatus == 'restricted' || currentStatus == 'excluded') {
        return currentStatus;
      }

      final eval = _evaluateMessage(clean, ruleOptions);
      final flags = eval.flags;
      final score5w = eval.score5w;
      final hasViolation = flags.contains('insult') || flags.contains('discrimination') || flags.contains('spam');

      String nextStatus = currentStatus;
      if (hasViolation) {
        warningsCount += 1;
        nextStatus = warningsCount >= 3
            ? 'excluded'
            : (warningsCount >= 2 ? 'restricted' : 'warned');
        await pRef.set(
          {
            'status': nextStatus,
            'warningsCount': warningsCount,
            'lastWarningAt': DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
        if (nextStatus == 'restricted' || nextStatus == 'excluded') {
          return nextStatus;
        }
      } else if (!pSnap.exists) {
        await pRef.set(
          {
            'status': 'active',
            'warningsCount': warningsCount,
            'joinedAt': DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      }

      await vRef.collection('messages').add({
        'userId': uid,
        'text': clean,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'ai': {
          'score5w': score5w,
          'flags': flags,
          'moderation': hasViolation ? 'warned' : 'ok',
        },
        'meta': {
          'editedAt': null,
        },
      });
      return hasViolation ? 'warned' : 'ok';
    } catch (e, st) {
      AppLogger.w('Add vetrina message failed', error: e, stackTrace: st);
      return 'error';
    }
  }

  Future<void> addDraftPost({
    required String vetrinaId,
    required String type,
    required String label,
    String? text,
    String? url,
    String? localPath,
    String? mimeType,
  }) async {
    try {
      await FirebaseBackend.I.init();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      var finalUrl = url;
      var status = 'pending_upload';
      if (type == 'text' || type == 'link') {
        status = 'published';
      }
      if (localPath != null && localPath.isNotEmpty && _canUpload()) {
        try {
          final file = File(localPath);
          if (await file.exists()) {
            final path = 'vetrine/$vetrinaId/$uid/${now}_${file.uri.pathSegments.last}';
            finalUrl = await _uploadFile(path, file);
            status = 'published';
          }
        } catch (_) {}
      }
      await _db.collection('vetrine').doc(vetrinaId).collection('posts').add({
        'type': type,
        'label': label,
        'status': status,
        'text': text,
        'url': finalUrl,
        'localPath': _canUpload() ? null : localPath,
        'mimeType': mimeType,
        'authorUserId': uid,
        'createdAt': now,
      });
    } catch (e, st) {
      AppLogger.w('Add draft post failed', error: e, stackTrace: st);
    }
  }

  @override
  Future<bool> promote(String vetrinaId) async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final key = 'veil_promote_$vetrinaId';
        final existing = LocalStorage.getString(key);
        if (existing == '1') return false;
        await LocalStorage.setString(key, '1');
        return true;
      }
      await FirebaseBackend.I.init();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final vRef = _db.collection('vetrine').doc(vetrinaId);
      final pRef = vRef.collection('promotes').doc(uid);
      final uRef = _db.collection('users').doc(uid).collection('promoted_vetrine').doc(vetrinaId);

      final res = await _db.runTransaction<bool>((tx) async {
        final existing = await tx.get(pRef);
        if (existing.exists) return false;
        tx.set(pRef, {'uid': uid, 'createdAt': now});
        tx.set(uRef, {'vetrinaId': vetrinaId, 'createdAt': now}, SetOptions(merge: true));
        tx.set(
          vRef,
          {
            'counters': {
              'promotesTotal': FieldValue.increment(1),
              'promotes30d': FieldValue.increment(1),
            }
          },
          SetOptions(merge: true),
        );
        return true;
      });
      return res;
    } catch (e, st) {
      AppLogger.w('Promote failed', error: e, stackTrace: st);
      return false;
    }
  }

  @override
  Future<bool> deleteVetrina(String vetrinaId) async {
    try {
      await FirebaseBackend.I.init();
      final vRef = _db.collection('vetrine').doc(vetrinaId);
      await _deleteSubcollection(vRef.collection('posts'));
      await _deleteSubcollection(vRef.collection('messages'));
      await _deleteSubcollection(vRef.collection('participants'));
      await _deleteSubcollection(vRef.collection('promotes'));
      await vRef.delete();
      return true;
    } catch (e, st) {
      AppLogger.w('Delete vetrina failed', error: e, stackTrace: st);
      return false;
    }
  }

  Future<String?> createVetrina({
    required String title,
    required String theme,
    required List<String> tags,
    String? coverUrl,
    String? coverTone,
    List<String> guidelines = const [],
    Map<String, bool> ruleOptions = const {},
  }) async {
    try {
      await FirebaseBackend.I.init();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'system';
      final now = DateTime.now().millisecondsSinceEpoch;
      final data = {
        'title': title.trim(),
        'theme': theme.trim(),
        'tags': tags,
        'creatorId': uid,
        'createdAt': now,
        'visibility': 'public',
        'status': 'active',
        'coreRules': ['no_insults', 'no_discrimination', 'be_civil'],
        'ruleOptions': ruleOptions.isEmpty
            ? {
                'cite_sources_5w': true,
                'stay_on_topic': true,
                'respect_expertise': false,
                'no_spam': true,
              }
            : ruleOptions,
        'guidelines': guidelines,
        'quizEnabled': false,
        'quizLink': null,
        'rulesCoreVersion': 'v1',
        'rulesCustom': {
          'requirements': guidelines,
          'materialsFree': [],
          'materialsPremium': [],
          'quizOptional': false,
          'notes': '',
        },
        'accessPolicy': {
          'entryMode': 'open',
        },
        'parentVetrinaId': null,
        'counters': {
          'visitors30d': 0,
          'observers30d': 0,
          'participants30d': 0,
          'visitorsTotal': 0,
          'observersTotal': 0,
          'participantsTotal': 0,
        },
        'ranking': {
          'finalScore30d': 0,
          'finalScoreTotal': 0,
          'qualityScore30d': 0,
          'massScore30d': 0,
          'conversionScore30d': 0,
          'explanation': 'New showcase: waiting for activity.',
          'badges': <String>[],
          'components': {
            'quality': 'Initial quality',
            'mass': 'Initial mass',
            'conversion': 'Initial conversion',
          },
          'formulaVersion': 'v1',
        },
        'coverTone': coverTone,
        'coverUrl': coverUrl,
      };
      final doc = await _db.collection('vetrine').add(data);
      return doc.id;
    } catch (e, st) {
      AppLogger.w('Create vetrina failed', error: e, stackTrace: st);
      return null;
    }
  }

  @override
  Future<void> requestAccess(String vetrinaId) async {
    try {
      await FirebaseBackend.I.init();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _db
          .collection('vetrine')
          .doc(vetrinaId)
          .collection('participants')
          .doc(uid)
          .set({
        'status': 'active',
        'warningsCount': 0,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } catch (e, st) {
      AppLogger.w('Vetrina request access failed', error: e, stackTrace: st);
    }
  }

  List<Vetrina> _mockVetrine() {
    final now = DateTime.now();
    return List<Vetrina>.generate(5, (i) {
      final visitors = 150 + i * 42;
      final observers = 60 + i * 21;
      final participants = 12 + i * 6;
      final tones = ['amber', 'blue', 'green', 'red', 'purple'];
      final conversionRate = participants / (observers + 1);
      final breakdown = VetrinaRanker.breakdown30d(
        visitors: visitors,
        observers: observers,
        participants: participants,
        conversionRate: conversionRate,
      );
      return Vetrina(
        id: 'mock_$i',
        title: 'Showcase ${i + 1}',
        theme: i.isEven ? 'Culture' : 'Science',
        tags: i.isEven ? ['libri', 'saggi'] : ['ricerca', 'tecnologia'],
        creatorId: 'system',
        createdAt: now.subtract(Duration(days: i * 2)),
        visibility: 'public',
        status: 'active',
        coreRules: const ['no_insults', 'no_discrimination', 'be_civil'],
        ruleOptions: const {
          'cite_sources_5w': true,
          'stay_on_topic': true,
          'respect_expertise': false,
          'no_spam': true,
        },
        guidelines: const ['Read the brief before joining'],
        quizEnabled: false,
        quizLink: null,
        rulesCoreVersion: 'v1',
        rulesCustom: const {
          'requirements': ['Civility and respect'],
          'materialsFree': [],
          'materialsPremium': [],
          'quizOptional': true,
        },
        accessPolicy: const {
          'entryMode': 'open',
        },
        parentVetrinaId: null,
        counters: {
          'visitors30d': visitors,
          'observers30d': observers,
          'participants30d': participants,
          'promotes30d': (i + 1) * 3,
          'visitorsTotal': visitors + 200,
          'observersTotal': observers + 80,
          'participantsTotal': participants + 20,
          'promotesTotal': (i + 1) * 9,
        },
        ranking: {
          ...breakdown,
          'finalScoreTotal': (breakdown['finalScore30d'] as double) + 0.5,
        },
        coverTone: tones[i % tones.length],
        coverUrl: null,
      );
    });
  }
}

bool _canUpload() {
  if (kIsWeb) return true;
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;
}

Future<String?> _uploadFile(String path, File file) async {
  final ref = FirebaseStorage.instance.ref(path);
  await ref.putFile(file);
  return await ref.getDownloadURL();
}

Future<void> _deleteSubcollection(CollectionReference<Map<String, dynamic>> col) async {
  final snap = await col.get();
  if (snap.docs.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final doc in snap.docs) {
    batch.delete(doc.reference);
  }
  await batch.commit();
}

class _MessageEval {
  _MessageEval({required this.flags, required this.score5w});

  final List<String> flags;
  final int score5w;
}

_MessageEval _evaluateMessage(String text, Map<String, dynamic> ruleOptions) {
  final lower = text.toLowerCase();
  final flags = <String>[];

  final insultWords = [
    'idiot',
    'stupid',
    'dumb',
    'moron',
    'trash',
    'cretino',
    'idiota',
    'stupido',
    'imbecille',
    'scemo',
  ];
  final hasInsult = insultWords.any((w) => lower.contains(RegExp(r'\\b' + RegExp.escape(w) + r'\\b'))) ||
      insultWords.any((w) => lower.contains(w));
  if (hasInsult) {
    flags.add('insult');
  }

  final discrimWords = ['racist', 'racism', 'sexist', 'homophobic', 'xenophobic'];
  final hasDiscrim = discrimWords.any((w) => lower.contains(RegExp(r'\\b' + RegExp.escape(w) + r'\\b'))) ||
      discrimWords.any((w) => lower.contains(w));
  if (hasDiscrim) {
    flags.add('discrimination');
  }

  if (ruleOptions['no_spam'] == true && text.trim().length < 3) {
    flags.add('spam');
  }

  int score5w = 0;
  final who = ['who', 'chi'];
  final what = ['what', 'cosa'];
  final when = ['when', 'quando'];
  final where = ['where', 'dove'];
  final why = ['why', 'perché', 'perche'];
  if (who.any((w) => lower.contains(w))) score5w += 1;
  if (what.any((w) => lower.contains(w))) score5w += 1;
  if (when.any((w) => lower.contains(w))) score5w += 1;
  if (where.any((w) => lower.contains(w))) score5w += 1;
  if (why.any((w) => lower.contains(w))) score5w += 1;

  if (ruleOptions['cite_sources_5w'] == true && score5w < 2) {
    flags.add('missing_5w');
  }

  if (ruleOptions['stay_on_topic'] == true && text.trim().length < 6) {
    flags.add('off_topic');
  }

  return _MessageEval(flags: flags, score5w: score5w);
}
