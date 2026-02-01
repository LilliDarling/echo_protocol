import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled by system notification tray
}

class NotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  void Function(String conversationId, String partnerId)? onNotificationTap;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  Future<void> initialize(String userId) async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _updateToken(userId);

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _saveToken(userId, token);
    });

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  Future<void> _updateToken(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(userId, token);
      }
    } catch (_) {}
  }

  Future<void> _saveToken(String userId, String token) async {
    final deviceId = _getDeviceId();
    try {
      await _db.collection('users').doc(userId).set({
        'fcmTokens': {deviceId: token},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> removeToken(String userId) async {
    final deviceId = _getDeviceId();
    try {
      await _db.collection('users').doc(userId).update({
        'fcmTokens.$deviceId': FieldValue.delete(),
      });
    } catch (_) {}
  }

  String _getDeviceId() {
    return defaultTargetPlatform.toString().split('.').last.toLowerCase();
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Foreground messages shown by system with presentation options above
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final conversationId = data['conversationId'] as String?;
    final partnerId = data['senderId'] as String?;

    if (conversationId != null && partnerId != null && onNotificationTap != null) {
      onNotificationTap!(conversationId, partnerId);
    }
  }

  void dispose() {
    _foregroundSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
  }
}
