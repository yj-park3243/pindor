import 'package:drift/drift.dart';

/// 채팅 메시지 테이블
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get chatRoomId => text()();
  TextColumn get senderId => text()();
  TextColumn get senderNickname => text()();
  TextColumn get senderProfileImageUrl => text().nullable()();
  TextColumn get messageType => text().withDefault(const Constant('TEXT'))();
  TextColumn get content => text()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
