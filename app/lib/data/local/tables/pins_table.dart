import 'package:drift/drift.dart';

/// 핀 테이블 (실제 Pin 모델과 1:1 매핑)
class Pins extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get slug => text().nullable()();
  RealColumn get centerLatitude => real()();
  RealColumn get centerLongitude => real()();
  TextColumn get level => text()(); // DONG | GU | CITY | PROVINCE
  TextColumn get parentPinId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get userCount => integer().withDefault(const Constant(0))();
  IntColumn get activeMatchRequests => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
