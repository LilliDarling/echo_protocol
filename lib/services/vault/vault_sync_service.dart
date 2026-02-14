import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/local/conversation.dart';
import '../../repositories/message_dao.dart';
import '../../repositories/conversation_dao.dart';
import '../database/app_database.dart';
import '../../utils/logger.dart';
import 'vault_chunk_builder.dart';
import 'vault_storage_service.dart';

enum VaultSyncState { idle, uploading, downloading, error }

class VaultSyncService {
  final FirebaseAuth _auth;
  final VaultStorageService _storageService;
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
        _storageService = VaultStorageService();

  VaultSyncService.forTesting({
    required FirebaseAuth auth,
    required VaultStorageService storageService,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
  })  : _auth = auth,
        _storageService = storageService,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _initialized = true;

  Stream<VaultSyncState> get stateStream => _stateController.stream;
  VaultSyncState get state => _state;
  String? get error => _error;
  bool get isSyncing => _isSyncing;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final db = await AppDatabase.instance();
      _messageDao = db.messageDao;
      _conversationDao = db.conversationDao;
      _initialized = true;
      LoggerService.info('VaultSyncService initialized');
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
      final messageDao = _messageDao!;
      final conversationDao = _conversationDao!;

      final chunkMetadataList =
          await _storageService.listChunks(userId: userId);

      if (chunkMetadataList.isEmpty) {
        _setState(VaultSyncState.idle);
        return 0;
      }

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

          await messageDao.insertBatch(vaultConv.messages);
          totalMerged += vaultConv.messages.length;
        }
      }

      LoggerService.info('Vault download complete: $totalMerged messages');
      _setState(VaultSyncState.idle);
      return totalMerged;
    } catch (e) {
      _error = e.toString();
      _setState(VaultSyncState.error);
      LoggerService.error('Vault download failed', e);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> shouldUpload() async {
    if (!_initialized) return false;
    final messages = await _messageDao!.getUnsyncedMessages(limit: 1);
    return messages.isNotEmpty;
  }

  void _setState(VaultSyncState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
  }
}
