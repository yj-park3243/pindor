import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/local/daos/users_dao.dart';
import '../data/local/cache_ttl_helper.dart';
import '../data/local/database_provider.dart';
import '../models/user.dart';

class UserRepository {
  final ApiClient _api;
  final UsersDao _dao;
  final CacheTtlHelper _cache;

  const UserRepository(this._api, this._dao, this._cache);

  // ─── 내 프로필 (SWR) ─────────────────────────────────

  /// 내 프로필 Stream (drift DB 변경 시 자동 emit)
  Stream<User?> watchMe(String userId) => _dao.watchUser(userId);

  /// 내 프로필 1회 조회 (로컬 우선, 없으면 API)
  Future<User?> getMe() async {
    final remote = await _api.get('/users/me');
    final user = User.fromJson(remote['data'] as Map<String, dynamic>);
    await _dao.upsertUser(user);
    await _cache.update('user_me');
    return user;
  }

  /// 로컬 DB에서 내 프로필 조회
  Future<User?> getMeLocal(String userId) => _dao.getUser(userId);

  /// 백그라운드 갱신 (TTL 만료 시만 API 호출)
  Future<void> refreshMeIfStale(String userId) async {
    final expired = await _cache.isExpired(
      'user_me',
      CacheTtlHelper.myProfileTtl,
    );
    if (!expired) return;

    try {
      final remote = await _api.get('/users/me');
      final user = User.fromJson(remote['data'] as Map<String, dynamic>);
      await _dao.upsertUser(user);
      await _cache.update('user_me');
    } catch (e) {
      debugPrint('[UserRepo] refreshMe failed: $e');
    }
  }

  // ─── 프로필 수정 ─────────────────────────────────────

  Future<User> updateProfile({
    String? nickname,
    String? profileImageUrl,
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (profileImageUrl != null) body['profileImageUrl'] = profileImageUrl;

    final response = await _api.patch('/users/me', body: body);
    final user = User.fromJson(response['data'] as Map<String, dynamic>);
    // 로컬 DB에도 반영 → Stream 자동 emit
    await _dao.upsertUser(user);
    await _cache.update('user_me');
    return user;
  }

  // ─── 위치 설정 ───────────────────────────────────────

  Future<void> setLocation({
    required double latitude,
    required double longitude,
    required String address,
    int matchRadiusKm = 10,
  }) async {
    await _api.post('/users/me/location', body: {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'matchRadiusKm': matchRadiusKm,
    });
  }

  // ─── 타 사용자 프로필 ────────────────────────────────

  Future<UserProfile> getUserProfile(String userId) async {
    final response = await _api.get('/users/$userId/profile');
    return UserProfile.fromJson(response['data'] as Map<String, dynamic>);
  }

  // ─── 계정 삭제 ───────────────────────────────────────

  Future<void> deleteAccount({String? reason}) async {
    await _api.delete('/users/me', body: {
      if (reason != null) 'reason': reason,
    });
  }

  // ─── 로그아웃 시 로컬 데이터 정리 ────────────────────

  Future<void> clearLocal(String userId) async {
    await _dao.deleteUser(userId);
    await _cache.invalidate('user_me');
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final cache = ref.watch(cacheTtlHelperProvider);
  return UserRepository(ApiClient.instance, UsersDao(db), cache);
});
