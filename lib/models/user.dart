import 'package:cloud_firestore/cloud_firestore.dart';

/// User model for partner accounts
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
  final String theme; // "dark" or "light"
  final bool notifications;
  final int autoDeleteDays;

  UserPreferences({
    required this.theme,
    required this.notifications,
    required this.autoDeleteDays,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] as String,
      notifications: json['notifications'] as bool,
      autoDeleteDays: json['autoDeleteDays'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'notifications': notifications,
      'autoDeleteDays': autoDeleteDays,
    };
  }

  UserPreferences copyWith({
    String? theme,
    bool? notifications,
    int? autoDeleteDays,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      notifications: notifications ?? this.notifications,
      autoDeleteDays: autoDeleteDays ?? this.autoDeleteDays,
    );
  }

  static UserPreferences get defaultPreferences {
    return UserPreferences(
      theme: 'light',
      notifications: true,
      autoDeleteDays: 30,
    );
  }
}
