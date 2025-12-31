import 'package:cloud_firestore/cloud_firestore.dart';

class SessionModel {
  final String id;
  final String userId;
  final String key;
  final DateTime expiresAt;
  final DateTime createdAt;

  SessionModel({
    required this.id,
    required this.userId,
    required this.key,
    required this.expiresAt,
    required this.createdAt,
  });

  factory SessionModel.fromJson(String id, Map<String, dynamic> json) {
    return SessionModel(
      id: id,
      userId: json['userId'] as String,
      key: json['key'] as String,
      expiresAt: (json['expiresAt'] as Timestamp).toDate(),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  factory SessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SessionModel.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'key': key,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  SessionModel copyWith({
    String? id,
    String? userId,
    String? key,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return SessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      key: key ?? this.key,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isExpired {
    return DateTime.now().isAfter(expiresAt);
  }

  bool get isValid {
    return !isExpired;
  }
}
