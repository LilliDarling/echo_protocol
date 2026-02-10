class LocalBlockedUser {
  final String userId;
  final DateTime blockedAt;
  final String? reason;

  LocalBlockedUser({
    required this.userId,
    required this.blockedAt,
    this.reason,
  });

  factory LocalBlockedUser.fromMap(Map<String, dynamic> map) {
    return LocalBlockedUser(
      userId: map['user_id'] as String,
      blockedAt: DateTime.fromMillisecondsSinceEpoch(map['blocked_at'] as int),
      reason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'blocked_at': blockedAt.millisecondsSinceEpoch,
      'reason': reason,
    };
  }

  LocalBlockedUser copyWith({
    String? userId,
    DateTime? blockedAt,
    String? reason,
  }) {
    return LocalBlockedUser(
      userId: userId ?? this.userId,
      blockedAt: blockedAt ?? this.blockedAt,
      reason: reason ?? this.reason,
    );
  }
}
