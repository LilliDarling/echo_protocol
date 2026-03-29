import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../models/local/conversation.dart';
import '../../models/local/message.dart';
import '../../models/vault/vault_chunk.dart';
import '../../models/vault/retention_settings.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/conversation_dao.dart';
import '../database/app_database.dart';
import '../secure_storage.dart';
import '../../utils/logger.dart';
import 'vault_chunk_builder.dart';
import 'vault_media_service.dart';
import 'vault_storage_service.dart';

enum VaultSyncState { idle, uploading, downloading, error }

class VaultSyncService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseStorage _firebaseStorage;
  final VaultStorageService _storageService;
  final VaultMediaService _mediaService;
  final SecureStorageService _secureStorage;
  MessageDao? _messageDao;
  ConversationDao? _conversationDao;

  bool _initialized = false;
  bool _isSyncing = false;

  final _stateController = StreamController<VaultSyncState>.broadcast();
  VaultSyncState _state = VaultSyncState.idle;
  String? _error;

  static final VaultSyncService _instance = VaultSyncService._internal();
  factory VaultSyncService() => _instance;

  VaultSyncService._internal()
      : _auth = FirebaseAuth.instance,
        _db = FirebaseFirestore.instance,
        _firebaseStorage = FirebaseStorage.instance,
        _storageService = VaultStorageService(),
        _mediaService = VaultMediaService(),
        _secureStorage = SecureStorageService();

  VaultSyncService.forTesting({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseStorage firebaseStorage,
    required VaultStorageService storageService,
    required VaultMediaService mediaService,
    required SecureStorageService secureStorage,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
  })  : _auth = auth,
        _db = firestore,
        _firebaseStorage = firebaseStorage,
        _storageService = storageService,
        _mediaService = mediaService,
        _secureStorage = secureStorage,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _initialized = true,
        _vaultKeyAvailable = true;

  Stream<VaultSyncState> get stateStream => _stateController.stream;
  VaultSyncState get state => _state;
  String? get error => _error;
  bool get isSyncing => _isSyncing;
  bool get isVaultReady => _initialized && _vaultKeyAvailable;

  bool _vaultKeyAvailable = false;
  RetentionPolicy? _cachedRetentionPolicy;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final db = await AppDatabase.instance();
      _messageDao = db.messageDao;
      _conversationDao = db.conversationDao;

      final vaultKey = await _secureStorage.getVaultKey();
      _vaultKeyAvailable = vaultKey != null;

      _initialized = true;
      if (!_vaultKeyAvailable) {
        LoggerService.info(
            'VaultSyncService initialized without vault key — sync disabled until recovery phrase is entered');
      } else {
        LoggerService.info('VaultSyncService initialized');
      }
    } catch (e) {
      LoggerService.error('VaultSyncService initialization failed', e);
      rethrow;
    }
  }

  Future<int> uploadUnsyncedMessages() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Not authenticated');
    if (!_initialized) throw Exception('VaultSyncService not initialized');
    if (_isSyncing) return 0;

    _isSyncing = true;
    _setState(VaultSyncState.uploading);

    try {
      final messageDao = _messageDao!;
      final conversationDao = _conversationDao!;

      // Check for newer chunks from other devices before uploading
      final lastSyncTimestamp = await _secureStorage.getLastVaultSyncTimestamp();
      final newerChunks = await _storageService.listChunks(
        userId: userId,
        afterTimestamp: lastSyncTimestamp,
      );

      if (newerChunks.isNotEmpty) {
        LoggerService.info(
            'Newer vault chunks detected (${newerChunks.length} new), downloading first');
        try {
          await _downloadAndMergeInternal(userId: userId);
        } catch (e) {
          LoggerService.error(
              'Failed to download newer chunks before upload', e);
        }
        _setState(VaultSyncState.uploading);
      }

      final unsyncedMessages =
          await messageDao.getUnsyncedMessages(limit: 2000);

      if (unsyncedMessages.isEmpty) {
        _setState(VaultSyncState.idle);
        return 0;
      }

      final conversationIds =
          unsyncedMessages.map((m) => m.conversationId).toSet();
      final conversationMap = <String, LocalConversation>{};
      for (final convId in conversationIds) {
        final conv = await conversationDao.getById(convId);
        if (conv != null) {
          conversationMap[convId] = conv;
        }
      }

      final latestIndex =
          await _storageService.getLatestChunkIndex(userId);
      final startingIndex = latestIndex + 1;

      final chunks = VaultChunkBuilder.buildChunks(
        messages: unsyncedMessages,
        conversationMap: conversationMap,
        startingIndex: startingIndex,
      );

      var totalSynced = 0;
      for (final chunk in chunks) {
        await _storageService.uploadChunk(
          userId: userId,
          chunk: chunk,
        );

        final messageIds = chunk.conversations
            .expand((c) => c.messages.map((m) => m.id))
            .toList();
        await messageDao.markBatchAsSynced(messageIds);
        totalSynced += messageIds.length;
      }

      // Upload media for synced messages based on retention policy
      final retentionPolicy = await _getRetentionPolicy(userId);
      if (retentionPolicy != RetentionPolicy.messagesOnly) {
        await _uploadMediaForChunks(
          userId: userId,
          chunks: chunks,
          retentionPolicy: retentionPolicy,
        );
      }

      // Update sync cursor to now — covers all chunks we just uploaded
      if (chunks.isNotEmpty) {
        await _secureStorage.storeLastVaultSyncTimestamp(DateTime.now());
      }

      LoggerService.info('Vault upload complete: $totalSynced messages');
      _setState(VaultSyncState.idle);
      return totalSynced;
    } catch (e) {
      _error = e.toString();
      _setState(VaultSyncState.error);
      LoggerService.error('Vault upload failed', e);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<int> downloadAndMerge() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('Not authenticated');
    if (!_initialized) throw Exception('VaultSyncService not initialized');
    if (_isSyncing) return 0;

    _isSyncing = true;
    _setState(VaultSyncState.downloading);

    try {
      final result = await _downloadAndMergeInternal(userId: userId);
      _setState(VaultSyncState.idle);
      return result;
    } catch (e) {
      _error = e.toString();
      _setState(VaultSyncState.error);
      LoggerService.error('Vault download failed', e);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Inner download logic, callable while [_isSyncing] is already held.
  Future<int> _downloadAndMergeInternal({required String userId}) async {
    final messageDao = _messageDao!;
    final conversationDao = _conversationDao!;

    final lastSyncTimestamp = await _secureStorage.getLastVaultSyncTimestamp();
    final chunkMetadataList = await _storageService.listChunks(
      userId: userId,
      afterTimestamp: lastSyncTimestamp,
    );

    if (chunkMetadataList.isEmpty) return 0;

    var totalMerged = 0;

    for (final metadata in chunkMetadataList) {
      final chunk = await _storageService.downloadChunk(
        userId: userId,
        metadata: metadata,
      );

      for (final vaultConv in chunk.conversations) {
        final existing =
            await conversationDao.getById(vaultConv.conversationId);
        if (existing == null) {
          final now = DateTime.now();
          await conversationDao.insert(LocalConversation(
            id: vaultConv.conversationId,
            recipientId: vaultConv.recipientId,
            recipientUsername: vaultConv.recipientUsername,
            recipientPublicKey: vaultConv.recipientPublicKey,
            createdAt: now,
            updatedAt: now,
          ));
        }

        // Reconcile conversation metadata with current Firestore data
        await _reconcileConversationMetadata(
          conversationDao: conversationDao,
          conversationId: vaultConv.conversationId,
          recipientId: vaultConv.recipientId,
        );

        await messageDao.insertIfAbsent(vaultConv.messages);
        totalMerged += vaultConv.messages.length;
      }

      // Download media for recovered messages (best-effort)
      await _downloadMediaForChunk(userId: userId, chunk: chunk);
    }

    // Update sync cursor to the latest uploadedAt from downloaded chunks
    final maxUploadedAt = chunkMetadataList
        .map((m) => m.uploadedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    await _secureStorage.storeLastVaultSyncTimestamp(maxUploadedAt);

    LoggerService.info('Vault download complete: $totalMerged messages');
    return totalMerged;
  }

  Future<bool> shouldUpload() async {
    if (!_initialized) return false;
    final messages = await _messageDao!.getUnsyncedMessages(limit: 1);
    return messages.isNotEmpty;
  }

  Future<RetentionPolicy> _getRetentionPolicy(String userId) async {
    if (_cachedRetentionPolicy != null) return _cachedRetentionPolicy!;

    try {
      final doc = await _db.collection('users').doc(userId).get();
      final prefs = doc.data()?['preferences'] as Map<String, dynamic>?;
      final value = prefs?['vaultRetention'] as String?;
      _cachedRetentionPolicy = value != null
          ? RetentionPolicy.fromString(value)
          : RetentionPolicy.smart;
    } catch (_) {
      _cachedRetentionPolicy = RetentionPolicy.smart;
    }
    return _cachedRetentionPolicy!;
  }

  void updateRetentionPolicy(RetentionPolicy policy) {
    _cachedRetentionPolicy = policy;
  }

  Future<void> _uploadMediaForChunks({
    required String userId,
    required List<VaultChunk> chunks,
    required RetentionPolicy retentionPolicy,
  }) async {
    final uploadedMediaIds = <String>{};
    final expiry = retentionPolicy.mediaExpiry;
    final expireAt =
        expiry != null && expiry != Duration.zero
            ? DateTime.now().add(expiry)
            : null;

    for (final chunk in chunks) {
      for (final conv in chunk.conversations) {
        for (final msg in conv.messages) {
          if (msg.mediaId != null && !uploadedMediaIds.contains(msg.mediaId)) {
            try {
              // Try to fetch the already-encrypted media from regular storage
              final encryptedBytes = await _tryFetchMedia(userId, msg.mediaId!);
              if (encryptedBytes != null) {
                await _mediaService.uploadMediaToVault(
                  userId: userId,
                  mediaId: msg.mediaId!,
                  encryptedBytes: encryptedBytes,
                  expireAt: expireAt,
                );
                uploadedMediaIds.add(msg.mediaId!);
              }
            } catch (e) {
              LoggerService.error(
                  'Media vault upload failed: ${msg.mediaId}', e);
            }
          }
        }
      }
    }
  }

  Future<Uint8List?> _tryFetchMedia(String userId, String mediaId) async {
    // Try all media storage paths including gifs
    final paths = [
      'media/images/$userId/$mediaId',
      'media/videos/$userId/$mediaId',
      'media/gifs/$userId/$mediaId',
      'media/thumbnails/$userId/$mediaId',
    ];

    for (final path in paths) {
      try {
        final ref = _firebaseStorage.ref().child(path);
        final data = await ref.getData();
        if (data != null) return data;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> _downloadMediaForChunk({
    required String userId,
    required VaultChunk chunk,
  }) async {
    for (final conv in chunk.conversations) {
      for (final msg in conv.messages) {
        if (msg.mediaId != null) {
          try {
            final encryptedBytes = await _mediaService.downloadMediaFromVault(
              userId: userId,
              mediaId: msg.mediaId!,
            );
            if (encryptedBytes != null) {
              final folder = _mediaFolderForType(msg.type);
              final ref = _firebaseStorage
                  .ref()
                  .child('media/$folder/$userId/${msg.mediaId}');
              await ref.putData(
                encryptedBytes,
                SettableMetadata(
                  contentType: 'application/octet-stream',
                  cacheControl: 'private, max-age=0',
                ),
              );
            }
          } catch (e) {
            LoggerService.error(
                'Media vault download failed: ${msg.mediaId}', e);
          }
        }
      }
    }
  }

  // TODO: When voice messages are implemented, add LocalMessageType.voice => 'voice'
  // and a corresponding media/voice/{userId}/ Storage path + storage.rules entry.
  static String _mediaFolderForType(LocalMessageType type) {
    switch (type) {
      case LocalMessageType.video:
        return 'videos';
      case LocalMessageType.gif:
        return 'gifs';
      default:
        return 'images';
    }
  }

  Future<void> _reconcileConversationMetadata({
    required ConversationDao conversationDao,
    required String conversationId,
    required String recipientId,
  }) async {
    try {
      final userDoc = await _db.collection('users').doc(recipientId).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final currentUsername = data['name'] as String?;
      final currentPublicKey = data['publicKey'] as String?;
      if (currentUsername == null && currentPublicKey == null) return;

      final local = await conversationDao.getById(conversationId);
      if (local == null) return;

      final usernameChanged =
          currentUsername != null && currentUsername != local.recipientUsername;
      final keyChanged =
          currentPublicKey != null && currentPublicKey != local.recipientPublicKey;

      if (usernameChanged || keyChanged) {
        await conversationDao.updateConversation(local.copyWith(
          recipientUsername: currentUsername ?? local.recipientUsername,
          recipientPublicKey: currentPublicKey ?? local.recipientPublicKey,
          updatedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      LoggerService.error(
          'Failed to reconcile conversation metadata for $recipientId', e);
    }
  }

  void _setState(VaultSyncState newState) {
    _state = newState;
    if (newState != VaultSyncState.error) {
      _error = null;
    }
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
  }
}
