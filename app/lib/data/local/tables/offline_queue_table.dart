import 'package:drift/drift.dart';

/// 오프라인 쓰기 큐 테이블
/// 네트워크 없을 때 쓰기 작업을 저장하고, 복귀 시 순서대로 전송
class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  // 작업 종류: SEND_MESSAGE | CREATE_POST | CREATE_COMMENT
  TextColumn get action => text()();
  // 작업 파라미터 (JSON)
  TextColumn get payloadJson => text()();
  // 상태: PENDING | PROCESSING | FAILED
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
