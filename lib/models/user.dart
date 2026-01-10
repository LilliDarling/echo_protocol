import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationPreview {
  full('full'),
  senderOnly('senderOnly'),
  hidden('hidden');

  final String value;
  const NotificationPreview(this.value);

  static NotificationPreview fromString(String value) {
    return NotificationPreview.values.firstWhere(
      (p) => p.value == value,
      orElse: () => NotificationPreview.senderOnly,
    );
  }
}

class UserModel {
  final String id;
  final String name;
  final String avatar;
  final DateTime createdAt;
  final DateTime lastActive;
  final UserPreferences preferences;

  UserModel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.createdAt,
    required this.lastActive,
    required this.preferences,
  });

  factory UserModel.fromJson(String id, Map<String, dynamic> json) {
    return UserModel(
      id: id,
      name: json['name'] as String,
      avatar: json['avatar'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      lastActive: (json['lastActive'] as Timestamp).toDate(),
      preferences: UserPreferences.fromJson(json['preferences'] as Map<String, dynamic>),
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatar': avatar,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActive': Timestamp.fromDate(lastActive),
      'preferences': preferences.toJson(),
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? avatar,
    DateTime? createdAt,
    DateTime? lastActive,
    UserPreferences? preferences,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
      preferences: preferences ?? this.preferences,
    );
  }
}

class UserPreferences {
  final String theme;
  final bool notifications;
  final NotificationPreview notificationPreview;
  final int autoDeleteDays;

  UserPreferences({
    required this.theme,
    required this.notifications,
    required this.notificationPreview,
    required this.autoDeleteDays,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] as String,
      notifications: json['notifications'] as bool,
      notificationPreview: NotificationPreview.fromString(
        json['notificationPreview'] as String? ?? 'senderOnly',
      ),
      autoDeleteDays: json['autoDeleteDays'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'notifications': notifications,
      'notificationPreview': notificationPreview.value,
      'autoDeleteDays': autoDeleteDays,
    };
  }

  UserPreferences copyWith({
    String? theme,
    bool? notifications,
    NotificationPreview? notificationPreview,
    int? autoDeleteDays,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      notifications: notifications ?? this.notifications,
      notificationPreview: notificationPreview ?? this.notificationPreview,
      autoDeleteDays: autoDeleteDays ?? this.autoDeleteDays,
    );
  }

  static UserPreferences get defaultPreferences {
    return UserPreferences(
      theme: 'light',
      notifications: true,
      notificationPreview: NotificationPreview.senderOnly,
      autoDeleteDays: 30,
    );
  }
}
