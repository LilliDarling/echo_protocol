import 'package:cloud_firestore/cloud_firestore.dart';

/// Echo model for messages between partners
class EchoModel {
  final String id;
  final String senderId;
  final String recipientId;
  final String content; // encrypted
  final DateTime timestamp;
  final EchoType type;
  final EchoStatus status;
  final EchoMetadata metadata;

  EchoModel({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.metadata,
  });

  factory EchoModel.fromJson(String id, Map<String, dynamic> json) {
    return EchoModel(
      id: id,
      senderId: json['senderId'] as String,
      recipientId: json['recipientId'] as String,
      content: json['content'] as String,
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      type: EchoType.fromString(json['type'] as String),
      status: EchoStatus.fromString(json['status'] as String),
      metadata: EchoMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
    );
  }

  factory EchoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EchoModel.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'recipientId': recipientId,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type.value,
      'status': status.value,
      'metadata': metadata.toJson(),
    };
  }

  EchoModel copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? content,
    DateTime? timestamp,
    EchoType? type,
    EchoStatus? status,
    EchoMetadata? metadata,
  }) {
    return EchoModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Mark echo as delivered
  EchoModel markAsDelivered() {
    return copyWith(status: EchoStatus.delivered);
  }

  /// Mark echo as read
  EchoModel markAsRead() {
    return copyWith(status: EchoStatus.read);
  }
}

enum EchoType {
  text('text'),
  image('image'),
  video('video'),
  voice('voice'),
  link('link');

  final String value;
  const EchoType(this.value);

  static EchoType fromString(String value) {
    return EchoType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => EchoType.text,
    );
  }
}

enum EchoStatus {
  sent('sent'),
  delivered('delivered'),
  read('read');

  final String value;
  const EchoStatus(this.value);

  static EchoStatus fromString(String value) {
    return EchoStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => EchoStatus.sent,
    );
  }
}

class EchoMetadata {
  final String? senderName;
  final String? fileName;
  final String? fileUrl;
  final String? thumbnailUrl;
  final LinkPreview? linkPreview;

  EchoMetadata({
    this.senderName,
    this.fileName,
    this.fileUrl,
    this.thumbnailUrl,
    this.linkPreview,
  });

  factory EchoMetadata.fromJson(Map<String, dynamic> json) {
    return EchoMetadata(
      senderName: json['senderName'] as String?,
      fileName: json['fileName'] as String?,
      fileUrl: json['fileUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      linkPreview: json['linkPreview'] != null
          ? LinkPreview.fromJson(json['linkPreview'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (senderName != null) 'senderName': senderName,
      if (fileName != null) 'fileName': fileName,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (linkPreview != null) 'linkPreview': linkPreview!.toJson(),
    };
  }

  EchoMetadata copyWith({
    String? senderName,
    String? fileName,
    String? fileUrl,
    String? thumbnailUrl,
    LinkPreview? linkPreview,
  }) {
    return EchoMetadata(
      senderName: senderName ?? this.senderName,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      linkPreview: linkPreview ?? this.linkPreview,
    );
  }

  static EchoMetadata empty() {
    return EchoMetadata();
  }
}

class LinkPreview {
  final String title;
  final String description;
  final String imageUrl;

  LinkPreview({
    required this.title,
    required this.description,
    required this.imageUrl,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      title: json['title'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  LinkPreview copyWith({
    String? title,
    String? description,
    String? imageUrl,
  }) {
    return LinkPreview(
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
