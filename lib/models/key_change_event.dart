import 'package:cloud_firestore/cloud_firestore.dart';

class KeyChangeEvent {
  final String id;
  final String visibleId;
  final DateTime detectedAt;
  final String previousFingerprint;
  final String newFingerprint;
  final bool acknowledged;
  final DateTime? acknowledgedAt;

  KeyChangeEvent({
    required this.id,
    required this.visibleId,
    required this.detectedAt,
    required this.previousFingerprint,
    required this.newFingerprint,
    this.acknowledged = false,
    this.acknowledgedAt,
  });

  factory KeyChangeEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return KeyChangeEvent(
      id: doc.id,
      visibleId: data['visibleId'] as String? ?? doc.id.substring(0, 8),
      detectedAt: (data['detectedAt'] as Timestamp).toDate(),
      previousFingerprint: data['previousFingerprint'] as String,
      newFingerprint: data['newFingerprint'] as String,
      acknowledged: data['acknowledged'] as bool? ?? false,
      acknowledgedAt: (data['acknowledgedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'visibleId': visibleId,
      'detectedAt': Timestamp.fromDate(detectedAt),
      'previousFingerprint': previousFingerprint,
      'newFingerprint': newFingerprint,
      'acknowledged': acknowledged,
      if (acknowledgedAt != null)
        'acknowledgedAt': Timestamp.fromDate(acknowledgedAt!),
    };
  }

  KeyChangeEvent copyWith({bool? acknowledged, DateTime? acknowledgedAt}) {
    return KeyChangeEvent(
      id: id,
      visibleId: visibleId,
      detectedAt: detectedAt,
      previousFingerprint: previousFingerprint,
      newFingerprint: newFingerprint,
      acknowledged: acknowledged ?? this.acknowledged,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }
}

enum KeyChangeStatus {
  noChange,
  changed,
  firstKey,
}

class KeyChangeResult {
  final KeyChangeStatus status;
  final String? previousFingerprint;
  final String currentFingerprint;
  final KeyChangeEvent? event;

  KeyChangeResult({
    required this.status,
    this.previousFingerprint,
    required this.currentFingerprint,
    this.event,
  });
}
