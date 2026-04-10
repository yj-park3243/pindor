import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/local/daos/pins_dao.dart';
import '../data/local/cache_ttl_helper.dart';
import '../data/local/database_provider.dart';
import '../models/pin.dart';
import '../models/post.dart';

class PinRepository {
  final ApiClient _api;
  final PinsDao _dao;
  final CacheTtlHelper _cache;

  static const _cacheKey = 'pins_all';

  const PinRepository(this._api, this._dao, this._cache);

  // ─── 핀 목록 (버전 기반 동기화) ───────────────────────

  /// 전체 핀 Stream (drift DB 변경 시 자동 emit)
  Stream<List<Pin>> watchAllPins() => _dao.watchAllPins();

  /// 로컬 핀 목록 1회 조회
  Future<List<Pin>> getAllPinsLocal() => _dao.getAllPins();

  /// 핀 데이터가 로컬에 있는지 확인
  Future<bool> hasPinsCache() async {
    final count = await _dao.getPinCount();
    return count > 0;
  }

  /// 로컬에 저장된 핀 버전 조회
  Future<String?> _getLocalVersion() => _cache.getEtag(_cacheKey);

  /// 서버에 버전 보내서 변경분만 받아오기
  /// - 버전 같으면 → API가 data: null 반환 → 로컬 데이터 그대로 사용
  /// - 버전 다르면 → 새 핀 데이터 받아서 로컬 DB 갱신
  Future<List<Pin>> fetchAndCachePins() async {
    final localVersion = await _getLocalVersion();

    final response = await _api.get(
      '/pins/all',
      queryParameters: {
        if (localVersion != null) 'version': localVersion,
      },
    );

    final meta = response['meta'] as Map<String, dynamic>?;
    final serverVersion = meta?['version'] as String?;
    final changed = meta?['changed'] as bool? ?? true;

    if (!changed) {
      debugPrint('[PinRepo] 핀 버전 동일 ($localVersion) — 로컬 데이터 사용');
      return getAllPinsLocal();
    }

    // 새 데이터 수신
    final data = response['data'] as List<dynamic>;
    final pins = data.map((e) => Pin.fromJson(e as Map<String, dynamic>)).toList();
    await _dao.upsertAllPins(pins);
    await _cache.update(_cacheKey, etag: serverVersion);
    debugPrint('[PinRepo] 핀 데이터 갱신 완료 (v$serverVersion, ${pins.length}개)');
    return pins;
  }

  /// 서버에 버전 체크 (앱 포그라운드 복귀, 앱 시작 시)
  Future<void> refreshIfStale() async {
    final hasCache = await hasPinsCache();
    if (!hasCache) {
      await fetchAndCachePins();
      return;
    }

    try {
      await fetchAndCachePins();
    } catch (e) {
      debugPrint('[PinRepo] 핀 버전 체크 실패 (로컬 유지): $e');
    }
  }

  // ─── 기존 API (게시판 등) ─────────────────────────────

  Future<List<Pin>> getNearbyPins({
    required double latitude,
    required double longitude,
    double radius = 10.0,
  }) async {
    final response = await _api.get(
      '/pins/nearby',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
      },
    );
    final data = response['data'] as List<dynamic>;
    return data.map((e) => Pin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Pin> getPinDetail(String pinId) async {
    final response = await _api.get('/pins/$pinId');
    final pin = Pin.fromJson(response['data'] as Map<String, dynamic>);
    await _dao.upsertPin(pin);
    return pin;
  }

  Future<Map<String, dynamic>> getPosts(
    String pinId, {
    String? category,
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/pins/$pinId/posts',
      queryParameters: {
        if (category != null) 'category': category,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    return response as Map<String, dynamic>;
  }

  Future<PinPost> createPost(
    String pinId, {
    required String title,
    required String content,
    required String category,
    List<String> imageUrls = const [],
  }) async {
    final response = await _api.post(
      '/pins/$pinId/posts',
      body: {
        'title': title,
        'content': content,
        'category': category,
        'imageUrls': imageUrls,
      },
    );
    return PinPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<PinPost> getPostDetail(String pinId, String postId) async {
    final response = await _api.get('/pins/$pinId/posts/$postId');
    return PinPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<PinPost> updatePost(
    String pinId,
    String postId, {
    String? title,
    String? content,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;

    final response = await _api.patch('/pins/$pinId/posts/$postId', body: body);
    return PinPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String pinId, String postId) async {
    await _api.delete('/pins/$pinId/posts/$postId');
  }

  Future<List<Comment>> getComments(String pinId, String postId) async {
    final response = await _api.get(
      '/pins/$pinId/posts/$postId/comments',
    );
    final data = response['data'] as List<dynamic>?;
    return data
            ?.map((e) => Comment.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
  }

  Future<Comment> createComment(
    String pinId,
    String postId, {
    required String content,
    String? parentId,
  }) async {
    final response = await _api.post(
      '/pins/$pinId/posts/$postId/comments',
      body: {
        'content': content,
        if (parentId != null) 'parentId': parentId,
      },
    );
    return Comment.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> toggleLike(String pinId, String postId) async {
    await _api.post('/pins/$pinId/posts/$postId/like', body: {});
  }
}

final pinRepositoryProvider = Provider<PinRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final cache = ref.watch(cacheTtlHelperProvider);
  return PinRepository(ApiClient.instance, PinsDao(db), cache);
});
