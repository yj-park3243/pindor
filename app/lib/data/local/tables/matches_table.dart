import 'package:drift/drift.dart';

/// 매칭 테이블
class Matches extends Table {
  TextColumn get id => text()();
  TextColumn get status => text()(); // PENDING | ACCEPTED | REJECTED | CANCELLED | COMPLETED
  TextColumn get sportType => text()();
  TextColumn get pinId => text().nullable()();
  TextColumn get requesterId => text()();
  TextColumn get responderId => text().nullable()();
  // 상세 정보는 JSON으로 저장 (requester/responder 프로필 등)
  TextColumn get detailJson => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
