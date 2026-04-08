import 'package:drift/drift.dart';

/// 유저 테이블
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get email => text().nullable()();
  TextColumn get nickname => text()();
  TextColumn get profileImageUrl => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ACTIVE'))();
  TextColumn get gender => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  // sportsProfiles는 JSON 문자열로 저장 (관계가 복잡하므로)
  TextColumn get sportsProfilesJson => text().withDefault(const Constant('[]'))();
  // location은 JSON 문자열로 저장
  TextColumn get locationJson => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
