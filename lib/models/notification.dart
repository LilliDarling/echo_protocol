import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String echoId;
  final String senderName;
  final bool read;
  final DateTime timestamp;
  final NotificationType type;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.echoId,
    required this.senderName,
    required this.read,
    required this.timestamp,
    required this.type,
  });

  String getDisplayBody(NotificationPreview preference) {
    switch (preference) {
      case NotificationPreview.full:
      case NotificationPreview.senderOnly:
        return 'New message from $senderName';
      case NotificationPreview.hidden:
        return 'New message';
    }
  }

  factory NotificationModel.fromJson(String id, Map<String, dynamic> json) {
    return NotificationModel(
      id: id,
      userId: json['userId'] as String,
      echoId: json['echoId'] as String,
      senderName: json['senderName'] as String,
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
      'senderName': senderName,
      'read': read,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type.value,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? echoId,
    String? senderName,
    bool? read,
    DateTime? timestamp,
    NotificationType? type,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      echoId: echoId ?? this.echoId,
      senderName: senderName ?? this.senderName,
      read: read ?? this.read,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
    );
  }

  NotificationModel markAsRead() {
    return copyWith(read: true);
  }

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
