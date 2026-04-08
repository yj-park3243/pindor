import 'package:drift/drift.dart';
import 'database.dart';

/// 캐시 TTL 관리 유틸리티
class CacheTtlHelper {
  final AppDatabase _db;

  CacheTtlHelper(this._db);

  static const Duration pinsTtl = Duration(hours: 24);
  static const Duration userProfileTtl = Duration(hours: 6);
  static const Duration myProfileTtl = Duration(days: 365); // 내 프로필은 수동 갱신
  static const Duration chatRoomsTtl = Duration(minutes: 30);
  static const Duration matchesTtl = Duration(minutes: 5);

  /// TTL이 만료되었는지 확인
  Future<bool> isExpired(String cacheKey, Duration ttl) async {
    final meta = await (_db.select(_db.cacheMeta)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .getSingleOrNull();

    if (meta == null) return true;

    return DateTime.now().difference(meta.lastFetchedAt) > ttl;
  }

  /// 캐시 데이터가 존재하는지 확인
  Future<bool> hasCache(String cacheKey) async {
    final meta = await (_db.select(_db.cacheMeta)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .getSingleOrNull();
    return meta != null;
  }

  /// 캐시 타임스탬프 + ETag 갱신
  Future<void> update(String cacheKey, {String? etag, String? cursor}) async {
    await _db.into(_db.cacheMeta).insertOnConflictUpdate(
          CacheMetaCompanion(
            cacheKey: Value(cacheKey),
            lastFetchedAt: Value(DateTime.now()),
            etag: Value(etag),
            cursor: Value(cursor),
          ),
        );
  }

  /// 저장된 ETag 조회
  Future<String?> getEtag(String cacheKey) async {
    final meta = await (_db.select(_db.cacheMeta)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .getSingleOrNull();
    return meta?.etag;
  }

  /// 저장된 커서 조회
  Future<String?> getCursor(String cacheKey) async {
    final meta = await (_db.select(_db.cacheMeta)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .getSingleOrNull();
    return meta?.cursor;
  }

  /// 특정 캐시 키 삭제
  Future<void> invalidate(String cacheKey) async {
    await (_db.delete(_db.cacheMeta)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .go();
  }
}
