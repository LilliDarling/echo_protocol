import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:echo_protocol/repositories/message_dao.dart';
import 'package:echo_protocol/services/auto_delete.dart';

@GenerateMocks([MessageDao])
import 'auto_delete_service_test.mocks.dart';

void main() {
  group('AutoDeleteService', () {
    late AutoDeleteService service;
    late MockMessageDao mockMessageDao;

    setUp(() {
      mockMessageDao = MockMessageDao();
      service = AutoDeleteService(messageDao: mockMessageDao);
    });

    test('returns 0 when autoDeleteDays is 0 (disabled)', () async {
      final result = await service.deleteOldMessages(
        conversationId: 'conv123',
        autoDeleteDays: 0,
      );

      expect(result, equals(0));
      verifyNever(mockMessageDao.deleteOlderThanInConversation(any, any));
    });

    test('returns 0 when autoDeleteDays is negative', () async {
      final result = await service.deleteOldMessages(
        conversationId: 'conv123',
        autoDeleteDays: -1,
      );

      expect(result, equals(0));
      verifyNever(mockMessageDao.deleteOlderThanInConversation(any, any));
    });

    test('deletes messages older than cutoff and returns count', () async {
      when(mockMessageDao.deleteOlderThanInConversation(any, any))
          .thenAnswer((_) async => 5);

      final result = await service.deleteOldMessages(
        conversationId: 'conv123',
        autoDeleteDays: 7,
      );

      expect(result, equals(5));

      final captured = verify(
        mockMessageDao.deleteOlderThanInConversation('conv123', captureAny),
      ).captured;

      final cutoff = captured.first as DateTime;
      final expectedCutoff = DateTime.now().subtract(const Duration(days: 7));
      expect(cutoff.difference(expectedCutoff).inSeconds.abs(), lessThan(2));
    });

    test('passes correct conversationId to DAO', () async {
      when(mockMessageDao.deleteOlderThanInConversation(any, any))
          .thenAnswer((_) async => 0);

      await service.deleteOldMessages(
        conversationId: 'specific-conv-id',
        autoDeleteDays: 30,
      );

      verify(mockMessageDao.deleteOlderThanInConversation(
        'specific-conv-id',
        any,
      )).called(1);
    });

    test('returns 0 when no messages match cutoff', () async {
      when(mockMessageDao.deleteOlderThanInConversation(any, any))
          .thenAnswer((_) async => 0);

      final result = await service.deleteOldMessages(
        conversationId: 'conv123',
        autoDeleteDays: 7,
      );

      expect(result, equals(0));
    });
  });
}
