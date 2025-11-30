import 'package:cloud_firestore/cloud_firestore.dart';

/// Echo model for messages between partners
class EchoModel {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final DateTime timestamp;
  final EchoType type;
  final EchoStatus status;
  final EchoMetadata metadata;
  final int senderKeyVersion;
  final int recipientKeyVersion;
  final int sequenceNumber;

  EchoModel({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.metadata,
    required this.senderKeyVersion,
    required this.recipientKeyVersion,
    required this.sequenceNumber,
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
      senderKeyVersion: json['senderKeyVersion'] as int? ?? 0,
      recipientKeyVersion: json['recipientKeyVersion'] as int? ?? 0,
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
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
      'senderKeyVersion': senderKeyVersion,
      'recipientKeyVersion': recipientKeyVersion,
      'sequenceNumber': sequenceNumber,
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
    int? senderKeyVersion,
    int? recipientKeyVersion,
    int? sequenceNumber,
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
      senderKeyVersion: senderKeyVersion ?? this.senderKeyVersion,
      recipientKeyVersion: recipientKeyVersion ?? this.recipientKeyVersion,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
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
  final bool isEncrypted;

  EchoMetadata({
    this.senderName,
    this.fileName,
    this.fileUrl,
    this.thumbnailUrl,
    this.linkPreview,
    this.isEncrypted = false,
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
      isEncrypted: json['isEncrypted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (senderName != null) 'senderName': senderName,
      if (fileName != null) 'fileName': fileName,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (linkPreview != null) 'linkPreview': linkPreview!.toJson(),
      'isEncrypted': isEncrypted,
    };
  }

  EchoMetadata copyWith({
    String? senderName,
    String? fileName,
    String? fileUrl,
    String? thumbnailUrl,
    LinkPreview? linkPreview,
    bool? isEncrypted,
  }) {
    return EchoMetadata(
      senderName: senderName ?? this.senderName,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      linkPreview: linkPreview ?? this.linkPreview,
      isEncrypted: isEncrypted ?? this.isEncrypted,
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
