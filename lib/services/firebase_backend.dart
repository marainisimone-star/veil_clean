import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import 'remote_backend.dart';

class FirebaseBackend implements RemoteBackend {
  FirebaseBackend._();
  static final FirebaseBackend I = FirebaseBackend._();

  bool _initialized = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Future<void> init() async {
    if (_initialized) return;
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows)) {
      _initialized = true;
      return;
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _initialized = true;
  }

  @override
  Future<String?> signInEmail({
    required String email,
    required String password,
  }) async {
    await init();
    final res = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return res.user?.uid;
  }

  @override
  Future<String?> registerEmail({
    required String email,
    required String password,
  }) async {
    await init();
    final res = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return res.user?.uid;
  }

  @override
  Stream<RemoteMessage> messagesStream({
    required String conversationId,
  }) {
    final ref = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false);

    return ref.snapshots().asyncExpand((snap) async* {
      for (final doc in snap.docs) {
        final data = doc.data();
        yield RemoteMessage.fromMap(data);
      }
    });
  }

  @override
  Future<void> sendMessage(RemoteMessage message) async {
    await init();
    final ref = _db
        .collection('conversations')
        .doc(message.conversationId)
        .collection('messages')
        .doc(message.id);
    await ref.set(message.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> setConversationHiddenForUser({
    required String uid,
    required String conversationId,
    required bool hidden,
  }) async {
    await init();
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId);
    await ref.set({'hidden': hidden, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        SetOptions(merge: true));
  }
}
