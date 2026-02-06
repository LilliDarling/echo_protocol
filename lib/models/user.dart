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
  final String username;
  final String name;
  final String avatar;
  final DateTime createdAt;
  final UserPreferences preferences;

  UserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.avatar,
    required this.createdAt,
    required this.preferences,
  });

  factory UserModel.fromJson(String id, Map<String, dynamic> json) {
    return UserModel(
      id: id,
      username: json['username'] as String? ?? '',
      name: json['name'] as String,
      avatar: json['avatar'] as String,
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      preferences: UserPreferences.fromJson(json['preferences'] as Map<String, dynamic>),
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'name': name,
      'avatar': avatar,
      'createdAt': Timestamp.fromDate(createdAt),
      'preferences': preferences.toJson(),
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? name,
    String? avatar,
    DateTime? createdAt,
    UserPreferences? preferences,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      preferences: preferences ?? this.preferences,
    );
  }
}

class UserPreferences {
  final String theme;
  final bool notifications;
  final NotificationPreview notificationPreview;
  final bool showTypingIndicator;
  final int autoDeleteDays;

  UserPreferences({
    required this.theme,
    required this.notifications,
    required this.notificationPreview,
    required this.showTypingIndicator,
    required this.autoDeleteDays,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] as String,
      notifications: json['notifications'] as bool,
      notificationPreview: NotificationPreview.fromString(
        json['notificationPreview'] as String? ?? 'senderOnly',
      ),
      showTypingIndicator: json['showTypingIndicator'] as bool? ?? false,
      autoDeleteDays: json['autoDeleteDays'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'notifications': notifications,
      'notificationPreview': notificationPreview.value,
      'showTypingIndicator': showTypingIndicator,
      'autoDeleteDays': autoDeleteDays,
    };
  }

  UserPreferences copyWith({
    String? theme,
    bool? notifications,
    NotificationPreview? notificationPreview,
    bool? showTypingIndicator,
    int? autoDeleteDays,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      notifications: notifications ?? this.notifications,
      notificationPreview: notificationPreview ?? this.notificationPreview,
      showTypingIndicator: showTypingIndicator ?? this.showTypingIndicator,
      autoDeleteDays: autoDeleteDays ?? this.autoDeleteDays,
    );
  }

  static UserPreferences get defaultPreferences {
    return UserPreferences(
      theme: 'dark',
      notifications: true,
      notificationPreview: NotificationPreview.senderOnly,
      showTypingIndicator: false,
      autoDeleteDays: 0,
    );
  }
}
