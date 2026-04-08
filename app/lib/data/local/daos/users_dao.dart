import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/users_table.dart';
import '../../../models/user.dart' as model;
import '../../../models/sports_profile.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  /// 내 프로필 Stream (변경 시 자동 emit)
  Stream<model.User?> watchUser(String userId) {
    return (select(db.users)..where((t) => t.id.equals(userId)))
        .watchSingleOrNull()
        .map((row) => row != null ? _rowToUser(row) : null);
  }

  /// 내 프로필 1회 조회
  Future<model.User?> getUser(String userId) async {
    final row = await (select(db.users)
          ..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    return row != null ? _rowToUser(row) : null;
  }

  /// 유저 upsert (API 응답 → 로컬 DB)
  Future<void> upsertUser(model.User user) async {
    await into(db.users).insertOnConflictUpdate(
      UsersCompanion(
        id: Value(user.id),
        email: Value(user.email),
        nickname: Value(user.nickname),
        profileImageUrl: Value(user.profileImageUrl),
        phone: Value(user.phone),
        status: Value(user.status),
        gender: Value(user.gender),
        birthDate: Value(user.birthDate),
        createdAt: Value(user.createdAt),
        lastLoginAt: Value(user.lastLoginAt),
        sportsProfilesJson: Value(
          jsonEncode(user.sportsProfiles.map((e) => e.toJson()).toList()),
        ),
        locationJson: Value(
          user.location != null ? jsonEncode(user.location!.toJson()) : null,
        ),
        cachedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 특정 유저 삭제
  Future<void> deleteUser(String userId) async {
    await (delete(db.users)..where((t) => t.id.equals(userId))).go();
  }

  /// drift row → User 모델 변환
  model.User _rowToUser(User row) {
    List<SportsProfile> sportsProfiles = [];
    try {
      final list = jsonDecode(row.sportsProfilesJson) as List;
      sportsProfiles = list
          .map((e) => SportsProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    model.UserLocation? location;
    if (row.locationJson != null) {
      try {
        location = model.UserLocation.fromJson(
          jsonDecode(row.locationJson!) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    return model.User(
      id: row.id,
      email: row.email,
      nickname: row.nickname,
      profileImageUrl: row.profileImageUrl,
      phone: row.phone,
      status: row.status,
      gender: row.gender,
      birthDate: row.birthDate,
      createdAt: row.createdAt,
      lastLoginAt: row.lastLoginAt,
      sportsProfiles: sportsProfiles,
      location: location,
    );
  }
}
