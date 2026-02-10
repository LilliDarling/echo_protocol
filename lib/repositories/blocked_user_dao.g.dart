// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blocked_user_dao.dart';

// ignore_for_file: type=lint
mixin _$BlockedUserDaoMixin on DatabaseAccessor<AppDatabase> {
  $BlockedUsersTable get blockedUsers => attachedDatabase.blockedUsers;
  BlockedUserDaoManager get managers => BlockedUserDaoManager(this);
}

class BlockedUserDaoManager {
  final _$BlockedUserDaoMixin _db;
  BlockedUserDaoManager(this._db);
  $$BlockedUsersTableTableManager get blockedUsers =>
      $$BlockedUsersTableTableManager(_db.attachedDatabase, _db.blockedUsers);
}
