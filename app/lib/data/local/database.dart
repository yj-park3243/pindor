import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/cache_meta_table.dart';
import 'tables/pins_table.dart';
import 'tables/users_table.dart';
import 'tables/chat_rooms_table.dart';
import 'tables/messages_table.dart';
import 'tables/matches_table.dart';
import 'tables/offline_queue_table.dart';
import 'daos/users_dao.dart';
import 'daos/pins_dao.dart';
import 'daos/chat_dao.dart';
import 'daos/matches_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    CacheMeta,
    Pins,
    Users,
    ChatRooms,
    Messages,
    Matches,
    OfflineQueue,
  ],
  daos: [UsersDao, PinsDao, ChatDao, MatchesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // 메시지 조회 최적화 인덱스
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_room_created '
            'ON messages (chat_room_id, created_at DESC)',
          );
        },
        onUpgrade: (m, from, to) async {
          // 향후 스키마 버전업 시 마이그레이션 로직 추가
        },
      );

  /// 전체 캐시 삭제 (로그아웃 시 호출)
  Future<void> clearAll() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'spots_local_db');
}
