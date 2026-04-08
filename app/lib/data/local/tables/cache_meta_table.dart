import 'package:drift/drift.dart';

/// 각 데이터 타입의 마지막 fetch 시각과 ETag를 저장
class CacheMeta extends Table {
  // key 예시: 'pins_all', 'chat_rooms', 'user_me', 'pin_posts_<pinId>'
  TextColumn get cacheKey => text()();
  DateTimeColumn get lastFetchedAt => dateTime()();
  TextColumn get etag => text().nullable()();
  TextColumn get cursor => text().nullable()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}
