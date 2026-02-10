import 'package:drift/drift.dart';
import '../../models/local/message.dart';

class EpochDateTimeConverter extends TypeConverter<DateTime, int> {
  const EpochDateTimeConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

class MessageTypeConverter extends TypeConverter<LocalMessageType, String> {
  const MessageTypeConverter();

  @override
  LocalMessageType fromSql(String fromDb) =>
      LocalMessageType.fromString(fromDb);

  @override
  String toSql(LocalMessageType value) => value.name;
}

class MessageStatusConverter extends TypeConverter<LocalMessageStatus, String> {
  const MessageStatusConverter();

  @override
  LocalMessageStatus fromSql(String fromDb) =>
      LocalMessageStatus.fromString(fromDb);

  @override
  String toSql(LocalMessageStatus value) => value.name;
}
