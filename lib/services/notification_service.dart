import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/local_storage.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService I = NotificationService._();

  static const String _channelId = 'veil_messages';
  static const String _channelName = 'Veil messages';
  static const String _channelDesc = 'Message notifications';
  static const String _kFcmToken = 'veil_fcm_token_v1';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await Firebase.initializeApp();
      } catch (_) {}
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _local.initialize(settings);

    if (Platform.isAndroid) {
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
    }

    await _requestPermissions();

    FirebaseMessaging.onMessage.listen((message) async {
      await _showLocalForMessage(message);
    });

    try {
      await refreshToken();
    } catch (_) {}

    _initialized = true;
  }

  Future<String?> refreshToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await LocalStorage.setString(_kFcmToken, token.trim());
        debugPrint('FCM token: $token');
        return token.trim();
      }
    } catch (_) {}
    return null;
  }

  String? getCachedToken() {
    final token = LocalStorage.getString(_kFcmToken);
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }

  Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  Future<void> _showLocalForMessage(RemoteMessage message) async {
    await init();
    final title = _buildTitle(message);
    final body = _buildBody(message);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> showTestNotification({
    String? sender,
    bool hidden = false,
  }) async {
    await init();
    final msg = RemoteMessage(
      data: <String, dynamic>{
        if (sender != null && sender.trim().isNotEmpty) 'sender': sender.trim(),
        if (hidden) 'hidden': '1',
      },
    );
    await _showLocalForMessage(msg);
  }

  String _buildTitle(RemoteMessage message) {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final lang = locale.languageCode.toLowerCase();
    final sender = (message.data['sender'] ?? '').toString().trim();
    final hidden = _isHiddenMessage(message);

    if (lang == 'it') {
      if (hidden) return 'Nuovo messaggio Veil';
      return sender.isEmpty ? 'Nuovo messaggio Veil' : 'Veil • $sender';
    }
    if (hidden) return 'New Veil message';
    return sender.isEmpty ? 'New Veil message' : 'Veil • $sender';
  }

  String _buildBody(RemoteMessage message) {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final lang = locale.languageCode.toLowerCase();
    final sender = (message.data['sender'] ?? '').toString().trim();
    final hidden = _isHiddenMessage(message);

    if (lang == 'it') {
      if (hidden) return 'Hai ricevuto un Veil chat.';
      return sender.isEmpty
          ? 'Hai ricevuto un Veil chat.'
          : 'Hai ricevuto un Veil chat da $sender.';
    }
    if (hidden) return 'You received a Veil chat.';
    return sender.isEmpty
        ? 'You received a Veil chat.'
        : 'You received a Veil chat from $sender.';
  }

  bool _isHiddenMessage(RemoteMessage message) {
    final raw = message.data['hidden'];
    if (raw == null) return false;
    return raw.toString().trim() == '1';
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Firebase.initializeApp();
    } catch (_) {}
  }
  await NotificationService.I._showLocalForMessage(message);
}
