import '../repositories/message_dao.dart';

class AutoDeleteService {
  final MessageDao _messageDao;

  AutoDeleteService({required MessageDao messageDao})
      : _messageDao = messageDao;

  Future<int> deleteOldMessages({
    required String conversationId,
    required int autoDeleteDays,
  }) async {
    if (autoDeleteDays <= 0) return 0;

    final cutoff = DateTime.now().subtract(Duration(days: autoDeleteDays));
    return _messageDao.deleteOlderThanInConversation(conversationId, cutoff);
  }
}
