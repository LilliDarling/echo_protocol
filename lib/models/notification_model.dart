import 'package:cloud_firestore/cloud_firestore.dart';

/// Notification model for user notifications
/// Firestore path: /notification/{notificationId}
class NotificationModel {
  final String id;
  final String userId;
  final String echoId;
  final String title;
  final String body;
  final bool read;
  final DateTime timestamp;
  final NotificationType type;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.echoId,
    required this.title,
    required this.body,
    required this.read,
    required this.timestamp,
    required this.type,
  });

  factory NotificationModel.fromJson(String id, Map<String, dynamic> json) {
    return NotificationModel(
      id: id,
      userId: json['userId'] as String,
      echoId: json['echoId'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      read: json['read'] as bool,
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      type: NotificationType.fromString(json['type'] as String),
    );
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'echoId': echoId,
      'title': title,
      'body': body,
      'read': read,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type.value,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? echoId,
    String? title,
    String? body,
    bool? read,
    DateTime? timestamp,
    NotificationType? type,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      echoId: echoId ?? this.echoId,
      title: title ?? this.title,
      body: body ?? this.body,
      read: read ?? this.read,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
    );
  }

  /// Mark notification as read
  NotificationModel markAsRead() {
    return copyWith(read: true);
  }

  /// Mark notification as unread
  NotificationModel markAsUnread() {
    return copyWith(read: false);
  }
}

enum NotificationType {
  message('message'),
  media('media'),
  link('link');

  final String value;
  const NotificationType(this.value);

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => NotificationType.message,
    );
  }
}
