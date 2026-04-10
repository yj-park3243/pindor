import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pin.dart';
import '../models/post.dart';
import '../repositories/pin_repository.dart';

/// 전체 핀 목록 프로바이더 (버전 기반 동기화)
///
/// 항상 서버 버전 체크 후 반환 — 버전 동일하면 로컬 데이터 즉시 반환,
/// 변경 시 갱신 후 반환. 네트워크 에러 시만 로컬 캐시 폴백.
final allPinsProvider = FutureProvider.autoDispose<List<Pin>>((ref) async {
  ref.keepAlive();
  final repo = ref.read(pinRepositoryProvider);

  try {
    return await repo.fetchAndCachePins();
  } catch (e) {
    debugPrint('[PinProvider] 서버 버전 체크 실패 — 로컬 폴백: $e');
    final hasCache = await repo.hasPinsCache();
    if (hasCache) return repo.getAllPinsLocal();
    rethrow;
  }
});

/// 주변 핀 목록 프로바이더
final nearbyPinsListProvider = FutureProvider.autoDispose
    .family<List<Pin>, ({double lat, double lng, double radius})>(
  (ref, params) async {
    final repo = ref.read(pinRepositoryProvider);
    return repo.getNearbyPins(
      latitude: params.lat,
      longitude: params.lng,
      radius: params.radius,
    );
  },
);

/// 핀 상세 프로바이더
final pinDetailProvider =
    FutureProvider.autoDispose.family<Pin, String>((ref, pinId) async {
  final repo = ref.read(pinRepositoryProvider);
  return repo.getPinDetail(pinId);
});

/// 핀 게시판 목록 Notifier
class PinBoardNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<PinPost>, String> {
  String? _cursor;
  bool _hasMore = true;
  late String _pinId;

  @override
  Future<List<PinPost>> build(String pinId) async {
    _pinId = pinId;
    return _fetchPosts(pinId);
  }

  Future<List<PinPost>> _fetchPosts(String pinId) async {
    final repo = ref.read(pinRepositoryProvider);
    final result = await repo.getPosts(pinId);
    _cursor = result['meta']?['cursor'] as String?;
    _hasMore = result['meta']?['hasMore'] as bool? ?? false;

    return (result['data'] as List<dynamic>)
        .map((e) => PinPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;

    try {
      final repo = ref.read(pinRepositoryProvider);
      final result = await repo.getPosts(_pinId, cursor: _cursor);
      _cursor = result['meta']?['cursor'] as String?;
      _hasMore = result['meta']?['hasMore'] as bool? ?? false;

      final newPosts = (result['data'] as List<dynamic>)
          .map((e) => PinPost.fromJson(e as Map<String, dynamic>))
          .toList();

      final current = state.valueOrNull ?? [];
      state = AsyncData([...current, ...newPosts]);
    } catch (_) {}
  }

  Future<PinPost> createPost({
    required String title,
    required String content,
    required String category,
    List<String> imageUrls = const [],
  }) async {
    final repo = ref.read(pinRepositoryProvider);
    final post = await repo.createPost(
      _pinId,
      title: title,
      content: content,
      category: category,
      imageUrls: imageUrls,
    );

    final current = state.valueOrNull ?? [];
    state = AsyncData([post, ...current]);
    return post;
  }

  Future<void> toggleLike(String postId) async {
    final repo = ref.read(pinRepositoryProvider);
    await repo.toggleLike(_pinId, postId);

    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((p) {
      if (p.id == postId) {
        return p.copyWith(
          isLiked: !p.isLiked,
          likeCount: p.isLiked ? p.likeCount - 1 : p.likeCount + 1,
        );
      }
      return p;
    }).toList());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _fetchPosts(_pinId));
  }
}

final pinBoardProvider = AsyncNotifierProvider.autoDispose
    .family<PinBoardNotifier, List<PinPost>, String>(
  PinBoardNotifier.new,
);

/// 게시글 상세 프로바이더
final postDetailProvider = FutureProvider.autoDispose
    .family<PinPost, ({String pinId, String postId})>(
  (ref, params) async {
    final repo = ref.read(pinRepositoryProvider);
    return repo.getPostDetail(params.pinId, params.postId);
  },
);

/// 댓글 목록 프로바이더
final postCommentsProvider = FutureProvider.autoDispose
    .family<List<Comment>, ({String pinId, String postId})>(
  (ref, params) async {
    final repo = ref.read(pinRepositoryProvider);
    return repo.getComments(params.pinId, params.postId);
  },
);
