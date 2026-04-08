import 'package:drift/drift.dart';

/// 채팅방 테이블
class ChatRooms extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();
  // opponent 정보 (JSON 문자열)
  TextColumn get opponentJson => text()();
  // lastMessage 정보 (JSON 문자열, nullable)
  TextColumn get lastMessageJson => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
