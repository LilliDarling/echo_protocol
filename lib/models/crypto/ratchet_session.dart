import 'dart:convert';
import 'dart:typed_data';
import '../../utils/security.dart';
import 'identity_key.dart';

enum SessionState { pending, active, invalidated, closed }

class ChainState {
  Uint8List chainKey;
  int messageIndex;
  Uint8List ratchetPublicKey;

  ChainState({
    required this.chainKey,
    required this.messageIndex,
    required this.ratchetPublicKey,
  });

  ChainState clone() => ChainState(
    chainKey: Uint8List.fromList(chainKey),
    messageIndex: messageIndex,
    ratchetPublicKey: Uint8List.fromList(ratchetPublicKey),
  );

  Map<String, dynamic> toJson() => {
    'chainKey': base64Encode(chainKey),
    'messageIndex': messageIndex,
    'ratchetPublicKey': base64Encode(ratchetPublicKey),
  };

  factory ChainState.fromJson(Map<String, dynamic> json) => ChainState(
    chainKey: base64Decode(json['chainKey'] as String),
    messageIndex: json['messageIndex'] as int,
    ratchetPublicKey: base64Decode(json['ratchetPublicKey'] as String),
  );

  void dispose() {
    SecurityUtils.secureClear(chainKey);
  }
}

class SkippedMessageKey {
  final Uint8List messageKey;
  final int chainIndex;
  final Uint8List ratchetPublicKey;
  final DateTime storedAt;

  SkippedMessageKey({
    required this.messageKey,
    required this.chainIndex,
    required this.ratchetPublicKey,
    required this.storedAt,
  });

  bool isExpired({Duration maxAge = const Duration(days: 7)}) {
    return DateTime.now().difference(storedAt) > maxAge;
  }

  Map<String, dynamic> toJson() => {
    'messageKey': base64Encode(messageKey),
    'chainIndex': chainIndex,
    'ratchetPublicKey': base64Encode(ratchetPublicKey),
    'storedAt': storedAt.millisecondsSinceEpoch,
  };

  factory SkippedMessageKey.fromJson(Map<String, dynamic> json) => SkippedMessageKey(
    messageKey: base64Decode(json['messageKey'] as String),
    chainIndex: json['chainIndex'] as int,
    ratchetPublicKey: base64Decode(json['ratchetPublicKey'] as String),
    storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
  );

  void dispose() {
    SecurityUtils.secureClear(messageKey);
  }
}

class SessionVersionException implements Exception {
  final int foundVersion;
  final int currentVersion;
  final String message;

  SessionVersionException(this.foundVersion, this.currentVersion)
      : message = 'Unsupported session version: $foundVersion '
            '(current: $currentVersion)';

  @override
  String toString() => message;
}

class RatchetSession {
  static const int maxSkippedKeys = 1000;
  static const int maxSkipDistance = 2000;
  static const Duration skippedKeyExpiry = Duration(days: 7);
  static const int currentVersion = 1;

  final String sessionId;
  final String ourUserId;
  final String theirUserId;
  final IdentityPublicKey theirIdentityKey;

  Uint8List rootKey;
  Uint8List? ourRatchetPrivateKey;
  Uint8List? ourRatchetPublicKey;
  Uint8List? theirRatchetPublicKey;

  ChainState? sendingChain;
  ChainState? receivingChain;
  Map<String, ChainState> previousReceivingChains;
  Map<String, SkippedMessageKey> skippedMessageKeys;

  Uint8List? mediaChainKey;
  int mediaKeyIndex;
  Map<String, Uint8List> mediaKeys;

  int skippedKeysCount;
  final DateTime createdAt;
  DateTime lastActivityAt;
  final bool isInitiator;
  SessionState state;

  RatchetSession({
    required this.sessionId,
    required this.ourUserId,
    required this.theirUserId,
    required this.theirIdentityKey,
    required this.rootKey,
    this.ourRatchetPrivateKey,
    this.ourRatchetPublicKey,
    this.theirRatchetPublicKey,
    this.sendingChain,
    this.receivingChain,
    Map<String, ChainState>? previousReceivingChains,
    Map<String, SkippedMessageKey>? skippedMessageKeys,
    this.mediaChainKey,
    this.mediaKeyIndex = 0,
    Map<String, Uint8List>? mediaKeys,
    this.skippedKeysCount = 0,
    required this.createdAt,
    required this.lastActivityAt,
    required this.isInitiator,
    this.state = SessionState.active,
  }) : previousReceivingChains = previousReceivingChains ?? {},
      skippedMessageKeys = skippedMessageKeys ?? {},
      mediaKeys = mediaKeys ?? {};

  static String generateSessionId(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Uint8List get associatedData {
    final sorted = [ourUserId, theirUserId]..sort();
    return Uint8List.fromList([
      ...utf8.encode('EchoAAD-v1'),
      ...utf8.encode(sorted[0]),
      ...utf8.encode(sorted[1]),
    ]);
  }

  void updateActivity() {
    lastActivityAt = DateTime.now();
  }

  bool canSkipMessages(int count) {
    return count <= maxSkipDistance &&
          (skippedKeysCount + count) <= maxSkippedKeys;
  }

  void cleanupExpiredKeys() {
    final keysToRemove = <String>[];
    for (final entry in skippedMessageKeys.entries) {
      if (entry.value.isExpired()) {
        entry.value.dispose();
        keysToRemove.add(entry.key);
        skippedKeysCount--;
      }
    }
    keysToRemove.forEach(skippedMessageKeys.remove);
  }

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'sessionId': sessionId,
    'ourUserId': ourUserId,
    'theirUserId': theirUserId,
    'theirIdentityKey': theirIdentityKey.toJson(),
    'rootKey': base64Encode(rootKey),
    'ourRatchetPrivateKey': ourRatchetPrivateKey != null ? base64Encode(ourRatchetPrivateKey!) : null,
    'ourRatchetPublicKey': ourRatchetPublicKey != null ? base64Encode(ourRatchetPublicKey!) : null,
    'theirRatchetPublicKey': theirRatchetPublicKey != null ? base64Encode(theirRatchetPublicKey!) : null,
    'sendingChain': sendingChain?.toJson(),
    'receivingChain': receivingChain?.toJson(),
    'previousReceivingChains': previousReceivingChains.map((k, v) => MapEntry(k, v.toJson())),
    'skippedMessageKeys': skippedMessageKeys.map((k, v) => MapEntry(k, v.toJson())),
    'mediaChainKey': mediaChainKey != null ? base64Encode(mediaChainKey!) : null,
    'mediaKeyIndex': mediaKeyIndex,
    'mediaKeys': mediaKeys.map((k, v) => MapEntry(k, base64Encode(v))),
    'skippedKeysCount': skippedKeysCount,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'lastActivityAt': lastActivityAt.millisecondsSinceEpoch,
    'isInitiator': isInitiator,
    'state': state.index,
  };

  factory RatchetSession.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version != currentVersion) {
      throw SessionVersionException(version, currentVersion);
    }

    return RatchetSession(
      sessionId: json['sessionId'] as String,
      ourUserId: json['ourUserId'] as String,
      theirUserId: json['theirUserId'] as String,
      theirIdentityKey: IdentityPublicKey.fromJson(json['theirIdentityKey'] as Map<String, dynamic>),
      rootKey: base64Decode(json['rootKey'] as String),
      ourRatchetPrivateKey: json['ourRatchetPrivateKey'] != null
          ? base64Decode(json['ourRatchetPrivateKey'] as String) : null,
      ourRatchetPublicKey: json['ourRatchetPublicKey'] != null
          ? base64Decode(json['ourRatchetPublicKey'] as String) : null,
      theirRatchetPublicKey: json['theirRatchetPublicKey'] != null
          ? base64Decode(json['theirRatchetPublicKey'] as String) : null,
      sendingChain: json['sendingChain'] != null
          ? ChainState.fromJson(json['sendingChain'] as Map<String, dynamic>) : null,
      receivingChain: json['receivingChain'] != null
          ? ChainState.fromJson(json['receivingChain'] as Map<String, dynamic>) : null,
      previousReceivingChains: (json['previousReceivingChains'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, ChainState.fromJson(v as Map<String, dynamic>))) ?? {},
      skippedMessageKeys: (json['skippedMessageKeys'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, SkippedMessageKey.fromJson(v as Map<String, dynamic>))) ?? {},
      mediaChainKey: json['mediaChainKey'] != null
          ? base64Decode(json['mediaChainKey'] as String) : null,
      mediaKeyIndex: json['mediaKeyIndex'] as int? ?? 0,
      mediaKeys: (json['mediaKeys'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, base64Decode(v as String))) ?? {},
      skippedKeysCount: json['skippedKeysCount'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      lastActivityAt: DateTime.fromMillisecondsSinceEpoch(json['lastActivityAt'] as int),
      isInitiator: json['isInitiator'] as bool,
      state: SessionState.values[json['state'] as int? ?? 1],
    );
  }

  Future<Map<String, String>> toSecureStorage() async {
    return {
      'session': jsonEncode(toJson()),
    };
  }

  static RatchetSession fromSecureStorage(Map<String, String> data) {
    return RatchetSession.fromJson(jsonDecode(data['session']!) as Map<String, dynamic>);
  }

  void deleteMediaKey(String mediaId) {
    final key = mediaKeys.remove(mediaId);
    if (key != null) {
      SecurityUtils.secureClear(key);
    }
  }

  void dispose() {
    SecurityUtils.secureClear(rootKey);
    if (ourRatchetPrivateKey != null) SecurityUtils.secureClear(ourRatchetPrivateKey!);
    if (mediaChainKey != null) SecurityUtils.secureClear(mediaChainKey!);
    sendingChain?.dispose();
    receivingChain?.dispose();
    for (final chain in previousReceivingChains.values) {
      chain.dispose();
    }
    for (final key in skippedMessageKeys.values) {
      key.dispose();
    }
    for (final key in mediaKeys.values) {
      SecurityUtils.secureClear(key);
    }
  }
}
