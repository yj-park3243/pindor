import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../models/post.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

class CommunityRepository {
  final ApiClient _api;

  const CommunityRepository(this._api);

  Future<List<PinPost>> getPosts({
    required String pinId,
    String? category,
    String? sportType,
    String? cursor,
    String? search,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (category != null) params['category'] = category;
    if (sportType != null) params['sportType'] = sportType;
    if (cursor != null) params['cursor'] = cursor;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final response = await _api.get('/pins/$pinId/posts', queryParameters: params);
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => PinPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PinPost> getPost(String pinId, String postId) async {
    final response = await _api.get('/pins/$pinId/posts/$postId');
    return PinPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  /// 최신 게시글 목록 (홈 화면 미리보기용)
  /// NOTE: /posts/latest 서버 라우트 없음 — 대신 핀 게시글 목록에서 최신순 가져옴
  Future<List<PinPost>> getLatestPosts({required String pinId, int limit = 3}) async {
    final response = await _api.get(
      '/pins/$pinId/posts',
      queryParameters: {'limit': limit},
    );
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => PinPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PinPost> createPost({
    required String pinId,
    required String title,
    required String content,
    String category = 'GENERAL',
    String? sportType,
    List<String>? imageUrls,
  }) async {
    final response = await _api.post('/pins/$pinId/posts', body: {
      'title': title,
      'content': content,
      'category': category,
      if (sportType != null) 'sportType': sportType,
      if (imageUrls != null && imageUrls.isNotEmpty) 'imageUrls': imageUrls,
    });
    return PinPost.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String pinId, String postId) async {
    await _api.delete('/pins/$pinId/posts/$postId');
  }

  Future<void> toggleLike(String pinId, String postId) async {
    await _api.post('/pins/$pinId/posts/$postId/like');
  }

  Future<List<Comment>> getComments(String pinId, String postId) async {
    final response = await _api.get('/pins/$pinId/posts/$postId/comments');
    final data = response['data'] as List<dynamic>;
    return data
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteComment(String pinId, String postId, String commentId) async {
    await _api.delete('/pins/$pinId/posts/$postId/comments/$commentId');
  }

  Future<Comment> createComment({
    required String pinId,
    required String postId,
    required String content,
    String? parentId,
  }) async {
    final response = await _api.post('/pins/$pinId/posts/$postId/comments', body: {
      'content': content,
      if (parentId != null) 'parentId': parentId,
    });
    return Comment.fromJson(response['data'] as Map<String, dynamic>);
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return CommunityRepository(ApiClient.instance);
});

/// 홈 화면용 최신 게시글 프로바이더 (최대 3개)
/// pinId를 파라미터로 받아서 해당 핀의 최신 게시글을 조회
final latestPostsProvider =
    FutureProvider.autoDispose.family<List<PinPost>, String>((ref, pinId) async {
  final repo = ref.read(communityRepositoryProvider);
  return repo.getLatestPosts(pinId: pinId, limit: 3);
});

// ─── State: PostList ──────────────────────────────────────────────────────────

class PostListState {
  final List<PinPost> posts;
  final bool isLoading;
  final bool hasMore;
  final String? cursor;
  final String? error;

  const PostListState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.cursor,
    this.error,
  });

  PostListState copyWith({
    List<PinPost>? posts,
    bool? isLoading,
    bool? hasMore,
    String? cursor,
    String? error,
  }) {
    return PostListState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor ?? this.cursor,
      error: error,
    );
  }
}

// ─── PostList 파라미터 키 ─────────────────────────────────────────────────────

class PostListKey {
  final String pinId;
  final String? category;
  final String? sportType;
  final String? search;

  const PostListKey({
    required this.pinId,
    this.category,
    this.sportType,
    this.search,
  });

  @override
  bool operator ==(Object other) =>
      other is PostListKey &&
      other.pinId == pinId &&
      other.category == category &&
      other.sportType == sportType &&
      other.search == search;

  @override
  int get hashCode => Object.hash(pinId, category, sportType, search);
}

// ─── Notifier: PostList ───────────────────────────────────────────────────────

class PostListNotifier
    extends AutoDisposeFamilyNotifier<PostListState, PostListKey> {
  late CommunityRepository _repo;

  @override
  PostListState build(PostListKey arg) {
    _repo = ref.read(communityRepositoryProvider);
    Future.microtask(() => _load(refresh: true));
    return const PostListState(isLoading: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(
      isLoading: true,
      cursor: refresh ? null : state.cursor,
      posts: refresh ? [] : state.posts,
      hasMore: refresh ? true : state.hasMore,
    );

    try {
      final posts = await _repo.getPosts(
        pinId: arg.pinId,
        category: arg.category,
        sportType: arg.sportType,
        cursor: refresh ? null : state.cursor,
        search: arg.search,
        limit: 20,
      );

      final newCursor = posts.isNotEmpty ? posts.last.id : null;

      state = state.copyWith(
        posts: refresh ? posts : [...state.posts, ...posts],
        isLoading: false,
        hasMore: posts.length == 20,
        cursor: newCursor,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() => _load(refresh: true);
  Future<void> loadMore() {
    if (!state.hasMore || state.isLoading) return Future.value();
    return _load();
  }

  void toggleLikeOptimistic(String postId) {
    // pinId는 PostListKey.arg에서 가져옴
    final pinId = arg.pinId;
    final posts = state.posts.map((p) {
      if (p.id != postId) return p;
      return p.copyWith(
        isLiked: !p.isLiked,
        likeCount: p.isLiked ? p.likeCount - 1 : p.likeCount + 1,
      );
    }).toList();
    state = state.copyWith(posts: posts);

    _repo.toggleLike(pinId, postId).catchError((_) {
      // 실패시 롤백
      final rolled = state.posts.map((p) {
        if (p.id != postId) return p;
        return p.copyWith(
          isLiked: !p.isLiked,
          likeCount: p.isLiked ? p.likeCount - 1 : p.likeCount + 1,
        );
      }).toList();
      state = state.copyWith(posts: rolled);
    });
  }

  void removePost(String postId) {
    state = state.copyWith(
      posts: state.posts.where((p) => p.id != postId).toList(),
    );
  }
}

final postListProvider = NotifierProvider.autoDispose
    .family<PostListNotifier, PostListState, PostListKey>(PostListNotifier.new);

// ─── PostDetail 파라미터 키 ──────────────────────────────────────────────────

class PostDetailKey {
  final String pinId;
  final String postId;

  const PostDetailKey({required this.pinId, required this.postId});

  @override
  bool operator ==(Object other) =>
      other is PostDetailKey &&
      other.pinId == pinId &&
      other.postId == postId;

  @override
  int get hashCode => Object.hash(pinId, postId);
}

// ─── Provider: PostDetail ─────────────────────────────────────────────────────

final postDetailProvider =
    FutureProvider.autoDispose.family<PinPost, PostDetailKey>((ref, key) {
  return ref.read(communityRepositoryProvider).getPost(key.pinId, key.postId);
});

// ─── Notifier: Comments ───────────────────────────────────────────────────────

class CommentsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<Comment>, PostDetailKey> {
  late CommunityRepository _repo;
  late PostDetailKey _key;

  @override
  Future<List<Comment>> build(PostDetailKey key) async {
    _key = key;
    _repo = ref.read(communityRepositoryProvider);
    return _repo.getComments(key.pinId, key.postId);
  }

  Future<void> addComment(String content, {String? parentId}) async {
    final comment = await _repo.createComment(
      pinId: _key.pinId,
      postId: _key.postId,
      content: content,
      parentId: parentId,
    );

    state = await AsyncValue.guard(() async {
      final current = state.value ?? [];
      if (parentId == null) {
        return [...current, comment];
      } else {
        // 대댓글: 부모 댓글에 추가
        return current.map((c) {
          if (c.id != parentId) return c;
          return Comment(
            id: c.id,
            postId: c.postId,
            authorId: c.authorId,
            authorNickname: c.authorNickname,
            authorProfileImageUrl: c.authorProfileImageUrl,
            authorTier: c.authorTier,
            parentId: c.parentId,
            content: c.content,
            isDeleted: c.isDeleted,
            replies: [...c.replies, comment],
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
          );
        }).toList();
      }
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _repo.deleteComment(_key.pinId, _key.postId, commentId);
    // 서버 soft delete 후 목록 재조회 (삭제된 댓글은 "삭제된 댓글입니다"로 표시됨)
    state = await AsyncValue.guard(
      () => _repo.getComments(_key.pinId, _key.postId),
    );
  }
}

final commentsProvider = AsyncNotifierProvider.autoDispose
    .family<CommentsNotifier, List<Comment>, PostDetailKey>(CommentsNotifier.new);
