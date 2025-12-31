import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String? validationToken;
  final String? conversationId;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final int encryptionVersion;

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
    this.validationToken,
    this.conversationId,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.encryptionVersion = 2,
  });

  factory EchoModel.fromJson(String id, Map<String, dynamic> json) {
    return EchoModel(
      id: id,
      senderId: json['senderId'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      type: json['type'] != null
          ? EchoType.fromString(json['type'] as String)
          : EchoType.text,
      status: json['status'] != null
          ? EchoStatus.fromString(json['status'] as String)
          : EchoStatus.sent,
      metadata: json['metadata'] != null
          ? EchoMetadata.fromJson(Map<String, dynamic>.from(json['metadata'] as Map))
          : EchoMetadata.empty(),
      senderKeyVersion: (json['senderKeyVersion'] as num?)?.toInt() ?? 0,
      recipientKeyVersion: (json['recipientKeyVersion'] as num?)?.toInt() ?? 0,
      sequenceNumber: (json['sequenceNumber'] as num?)?.toInt() ?? 0,
      validationToken: json['validationToken'] as String?,
      conversationId: json['conversationId'] as String?,
      isEdited: json['isEdited'] as bool? ?? false,
      editedAt: json['editedAt'] != null
          ? (json['editedAt'] as Timestamp).toDate()
          : null,
      isDeleted: json['isDeleted'] as bool? ?? false,
      deletedAt: json['deletedAt'] != null
          ? (json['deletedAt'] as Timestamp).toDate()
          : null,
      encryptionVersion: (json['encryptionVersion'] as num?)?.toInt() ?? 2,
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
      if (validationToken != null) 'validationToken': validationToken,
      if (conversationId != null) 'conversationId': conversationId,
      'isEdited': isEdited,
      if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
      'isDeleted': isDeleted,
      if (deletedAt != null) 'deletedAt': Timestamp.fromDate(deletedAt!),
      'encryptionVersion': encryptionVersion,
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
    String? validationToken,
    String? conversationId,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    int? encryptionVersion,
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
      validationToken: validationToken ?? this.validationToken,
      conversationId: conversationId ?? this.conversationId,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    );
  }

  EchoModel markAsDelivered() {
    return copyWith(status: EchoStatus.delivered);
  }

  EchoModel markAsRead() {
    return copyWith(status: EchoStatus.read);
  }
}

enum EchoType {
  text('text'),
  image('image'),
  video('video'),
  voice('voice'),
  link('link'),
  gif('gif');

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
  pending('pending'),
  failed('failed'),
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

  bool get isPending => this == EchoStatus.pending;
  bool get isFailed => this == EchoStatus.failed;
}

class EchoMetadata {
  final String? senderName;
  final String? fileName;
  final String? fileUrl;
  final String? thumbnailUrl;
  final String? mediaId;
  final String? thumbMediaId;
  final LinkPreview? linkPreview;
  final bool isEncrypted;

  EchoMetadata({
    this.senderName,
    this.fileName,
    this.fileUrl,
    this.thumbnailUrl,
    this.mediaId,
    this.thumbMediaId,
    this.linkPreview,
    this.isEncrypted = false,
  });

  factory EchoMetadata.fromJson(Map<String, dynamic> json) {
    return EchoMetadata(
      senderName: json['senderName'] as String?,
      fileName: json['fileName'] as String?,
      fileUrl: json['fileUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      mediaId: json['mediaId'] as String?,
      thumbMediaId: json['thumbMediaId'] as String?,
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
      if (mediaId != null) 'mediaId': mediaId,
      if (thumbMediaId != null) 'thumbMediaId': thumbMediaId,
      if (linkPreview != null) 'linkPreview': linkPreview!.toJson(),
      'isEncrypted': isEncrypted,
    };
  }

  EchoMetadata copyWith({
    String? senderName,
    String? fileName,
    String? fileUrl,
    String? thumbnailUrl,
    String? mediaId,
    String? thumbMediaId,
    LinkPreview? linkPreview,
    bool? isEncrypted,
  }) {
    return EchoMetadata(
      senderName: senderName ?? this.senderName,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaId: mediaId ?? this.mediaId,
      thumbMediaId: thumbMediaId ?? this.thumbMediaId,
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
