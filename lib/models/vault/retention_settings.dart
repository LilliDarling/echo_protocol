enum RetentionPolicy {
  everything('everything'),
  smart('smart'),
  minimal('minimal'),
  messagesOnly('messagesOnly');

  final String value;
  const RetentionPolicy(this.value);

  static RetentionPolicy fromString(String value) {
    return RetentionPolicy.values.firstWhere(
      (p) => p.value == value,
      orElse: () => RetentionPolicy.smart,
    );
  }

  Duration? get mediaExpiry {
    switch (this) {
      case RetentionPolicy.everything:
        return null;
      case RetentionPolicy.smart:
        return const Duration(days: 365);
      case RetentionPolicy.minimal:
        return const Duration(days: 30);
      case RetentionPolicy.messagesOnly:
        return Duration.zero;
    }
  }
}

class RetentionSettings {
  final RetentionPolicy policy;

  const RetentionSettings({this.policy = RetentionPolicy.smart});

  Map<String, dynamic> toJson() => {'policy': policy.value};

  factory RetentionSettings.fromJson(Map<String, dynamic> json) {
    return RetentionSettings(
      policy: RetentionPolicy.fromString(json['policy'] as String? ?? 'smart'),
    );
  }

  bool get includeMedia => policy != RetentionPolicy.messagesOnly;
}
