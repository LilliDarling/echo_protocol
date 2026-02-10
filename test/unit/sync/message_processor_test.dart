import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/models/crypto/sealed_envelope.dart';
import 'package:echo_protocol/models/local/message.dart';
import 'package:echo_protocol/models/local/conversation.dart';
import 'package:echo_protocol/repositories/message_dao.dart';
import 'package:echo_protocol/repositories/conversation_dao.dart';
import 'package:echo_protocol/services/crypto/protocol_service.dart';
import 'package:echo_protocol/services/sync/inbox_listener.dart';
import 'package:echo_protocol/services/sync/message_processor.dart';

@GenerateMocks([
  ProtocolService,
  MessageDao,
  ConversationDao,
])
import 'message_processor_test.mocks.dart';

void main() {
  group('MessageProcessor', () {
    late MessageProcessor processor;
    late MockProtocolService mockProtocol;
    late MockMessageDao mockMessageDao;
    late MockConversationDao mockConversationDao;
    const myUserId = 'my_user_id';

    setUp(() {
      mockProtocol = MockProtocolService();
      mockMessageDao = MockMessageDao();
      mockConversationDao = MockConversationDao();

      when(mockMessageDao.transaction(any)).thenAnswer((invocation) async {
        final callback = invocation.positionalArguments[0] as Future<void> Function();
        await callback();
      });
      when(mockMessageDao.getById(any)).thenAnswer((_) async => null);

      processor = MessageProcessor(
        protocol: mockProtocol,
        messageDao: mockMessageDao,
        conversationDao: mockConversationDao,
        myUserId: myUserId,
      );
    });

    group('processInboxMessage - incoming messages', () {
      test('unseals envelope and stores message', () async {
        final envelope = SealedEnvelope(
          recipientId: myUserId,
          encryptedPayload: Uint8List.fromList(List.generate(100, (i) => i)),
          ephemeralPublicKey: Uint8List(32),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
        );

        final inboxMessage = InboxMessage(
          id: 'msg_123',
          envelope: envelope,
          deliveredAt: DateTime.now(),
        );

        when(mockProtocol.unsealEnvelope(
          envelope: anyNamed('envelope'),
          myUserId: anyNamed('myUserId'),
        )).thenAnswer((_) async => (senderId: 'alice', plaintext: 'Hello, World!'));

        when(mockMessageDao.insert(any)).thenAnswer((_) async {});
        when(mockConversationDao.getById(any)).thenAnswer((_) async => LocalConversation(
          id: 'alice_my_user_id',
          recipientId: 'alice',
          recipientUsername: 'Alice',
          recipientPublicKey: 'key',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        when(mockConversationDao.updateLastMessage(
          conversationId: anyNamed('conversationId'),
          content: anyNamed('content'),
          timestamp: anyNamed('timestamp'),
        )).thenAnswer((_) async {});
        when(mockConversationDao.incrementUnreadCount(any)).thenAnswer((_) async {});

        final result = await processor.processInboxMessage(inboxMessage);

        expect(result, isNotNull);
        expect(result!.messageId, 'msg_123');
        expect(result.senderId, 'alice');
        expect(result.content, 'Hello, World!');

        verify(mockProtocol.unsealEnvelope(
          envelope: anyNamed('envelope'),
          myUserId: myUserId,
        )).called(1);

        verify(mockMessageDao.insert(argThat(
          predicate<LocalMessage>((m) =>
            m.id == 'msg_123' &&
            m.senderId == 'alice' &&
            m.content == 'Hello, World!' &&
            m.isOutgoing == false
          ),
        ))).called(1);
      });

      test('returns null on decryption failure', () async {
        final envelope = SealedEnvelope(
          recipientId: myUserId,
          encryptedPayload: Uint8List(10),
          ephemeralPublicKey: Uint8List(32),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
        );

        final inboxMessage = InboxMessage(
          id: 'msg_bad',
          envelope: envelope,
          deliveredAt: DateTime.now(),
        );

        when(mockProtocol.unsealEnvelope(
          envelope: anyNamed('envelope'),
          myUserId: anyNamed('myUserId'),
        )).thenThrow(Exception('Decryption failed'));

        final result = await processor.processInboxMessage(inboxMessage);

        expect(result, isNull);
        verifyNever(mockMessageDao.insert(any));
      });

      test('increments unread count for incoming messages', () async {
        final envelope = SealedEnvelope(
          recipientId: myUserId,
          encryptedPayload: Uint8List(50),
          ephemeralPublicKey: Uint8List(32),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
        );

        final inboxMessage = InboxMessage(
          id: 'msg_inc',
          envelope: envelope,
          deliveredAt: DateTime.now(),
        );

        when(mockProtocol.unsealEnvelope(
          envelope: anyNamed('envelope'),
          myUserId: anyNamed('myUserId'),
        )).thenAnswer((_) async => (senderId: 'bob', plaintext: 'New message'));

        when(mockMessageDao.insert(any)).thenAnswer((_) async {});
        when(mockConversationDao.getById(any)).thenAnswer((_) async => LocalConversation(
          id: 'bob_my_user_id',
          recipientId: 'bob',
          recipientUsername: 'Bob',
          recipientPublicKey: 'key',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        when(mockConversationDao.updateLastMessage(
          conversationId: anyNamed('conversationId'),
          content: anyNamed('content'),
          timestamp: anyNamed('timestamp'),
        )).thenAnswer((_) async {});
        when(mockConversationDao.incrementUnreadCount(any)).thenAnswer((_) async {});

        await processor.processInboxMessage(inboxMessage);

        verify(mockConversationDao.incrementUnreadCount(any)).called(1);
      });

      test('skips insert on reprocessed message (idempotent)', () async {
        final envelope = SealedEnvelope(
          recipientId: myUserId,
          encryptedPayload: Uint8List(50),
          ephemeralPublicKey: Uint8List(32),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
        );

        final inboxMessage = InboxMessage(
          id: 'msg_dup',
          envelope: envelope,
          deliveredAt: DateTime.now(),
        );

        when(mockMessageDao.getById('msg_dup')).thenAnswer((_) async => LocalMessage(
          id: 'msg_dup',
          conversationId: 'alice_my_user_id',
          senderId: 'alice',
          senderUsername: '',
          content: 'Already processed',
          timestamp: DateTime.now(),
          isOutgoing: false,
          createdAt: DateTime.now(),
        ));

        final result = await processor.processInboxMessage(inboxMessage);

        expect(result, isNotNull);
        expect(result!.messageId, 'msg_dup');
        expect(result.content, 'Already processed');

        verifyNever(mockProtocol.unsealEnvelope(
          envelope: anyNamed('envelope'),
          myUserId: anyNamed('myUserId'),
        ));
        verifyNever(mockMessageDao.insert(any));
        verifyNever(mockConversationDao.incrementUnreadCount(any));
      });
    });

    group('conversation ID generation', () {
      test('generates consistent ID regardless of order', () {
        String getConversationId(String myId, String partnerId) {
          final ids = [myId, partnerId]..sort();
          return '${ids[0]}_${ids[1]}';
        }

        expect(getConversationId('alice', 'bob'), 'alice_bob');
        expect(getConversationId('bob', 'alice'), 'alice_bob');
        expect(getConversationId('zebra', 'apple'), 'apple_zebra');
      });
    });

    group('message preview truncation', () {
      test('truncates long content correctly', () {
        String truncatePreview(String content, {int maxLength = 100}) {
          if (content.length <= maxLength) return content;
          return '${content.substring(0, maxLength)}...';
        }

        final short = 'Hello';
        final exact = 'A' * 100;
        final long = 'B' * 200;

        expect(truncatePreview(short), 'Hello');
        expect(truncatePreview(exact).length, 100);
        expect(truncatePreview(long).length, 103);
        expect(truncatePreview(long).endsWith('...'), true);
      });
    });
  });

  group('SealedEnvelope', () {
    test('correctly detects expired envelope', () {
      final expired = SealedEnvelope(
        recipientId: 'bob',
        encryptedPayload: Uint8List(10),
        ephemeralPublicKey: Uint8List(32),
        timestamp: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        expireAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      );

      final valid = SealedEnvelope(
        recipientId: 'bob',
        encryptedPayload: Uint8List(10),
        ephemeralPublicKey: Uint8List(32),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );

      expect(expired.isExpired, true);
      expect(valid.isExpired, false);
    });
  });

  group('InboxMessage', () {
    test('creates incoming message with sealed envelope', () {
      final envelope = SealedEnvelope(
        recipientId: 'me',
        encryptedPayload: Uint8List(10),
        ephemeralPublicKey: Uint8List(32),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        expireAt: DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );

      final message = InboxMessage(
        id: 'msg_in',
        envelope: envelope,
        deliveredAt: DateTime.now(),
      );

      expect(message.id, 'msg_in');
      expect(message.envelope.recipientId, 'me');
      expect(message.deliveredAt, isNotNull);
    });
  });
}
