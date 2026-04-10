import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/sports.dart';
import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/community_provider.dart';
import '../../providers/sport_preference_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';


/// 핀 게시판 화면
/// - 스포츠별 탭 (종목당 1개 게시판)
/// - 유저가 선택한 기본 스포츠가 초기 탭
class PinBoardScreen extends ConsumerStatefulWidget {
  final String pinId;
  final String? pinName;

  const PinBoardScreen({
    super.key,
    required this.pinId,
    this.pinName,
  });

  @override
  ConsumerState<PinBoardScreen> createState() => _PinBoardScreenState();
}

class _PinBoardScreenState extends ConsumerState<PinBoardScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  int _tabIndex = 0;
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    // 유저 기본 스포츠로 초기 탭 설정
    final preferred = ref.read(sportPreferenceProvider);
    final initialIndex = allSports.indexWhere((t) => t.value == preferred);
    _tabIndex = initialIndex >= 0 ? initialIndex : 0;

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  PostListKey get _currentKey => PostListKey(
        pinId: widget.pinId,
        sportType: allSports[_tabIndex].value,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(postListProvider(_currentKey).notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = value.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = _currentKey;
    final postState = ref.watch(postListProvider(key));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/map');
            }
          },
        ),
        title: Text(widget.pinName ?? '게시판'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '글쓰기',
            onPressed: () async {
              final created = await context.push<bool>(
                '/pins/${widget.pinId}/board/posts/create',
              );
              if (created == true && mounted) {
                ref.read(postListProvider(_currentKey).notifier).refresh();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(allSports.length, (index) {
                final isSelected = _tabIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _tabIndex = index;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    ref
                        .read(sportPreferenceProvider.notifier)
                        .select(allSports[index].value);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      allSports[index].label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '제목, 내용, 작성자 검색',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textDisabled,
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _debounceTimer?.cancel();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(postState, key)),
        ],
      ),
    );
  }

  Widget _buildBody(PostListState state, PostListKey key) {
    if (state.isLoading && state.posts.isEmpty) {
      return const FullScreenLoading();
    }
    if (state.error != null && state.posts.isEmpty) {
      return ErrorView(
        message: '게시글을 불러올 수 없습니다.',
        onRetry: () => ref.read(postListProvider(key).notifier).refresh(),
      );
    }
    if (state.posts.isEmpty) {
      return _EmptyBoard(
        sport: allSports[_tabIndex].label,
        isSearching: _searchQuery.isNotEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(postListProvider(key).notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.posts.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: LoadingIndicator()),
            );
          }
          final post = state.posts[index];
          return _PostListTile(
            post: post,
            onTap: () async {
              await context
                  .push('/pins/${widget.pinId}/board/posts/${post.id}');
              ref.read(postListProvider(key).notifier).refresh();
            },
            onLike: () => ref
                .read(postListProvider(key).notifier)
                .toggleLikeOptimistic(post.id),
          );
        },
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  final String sport;
  final bool isSearching;

  const _EmptyBoard({required this.sport, this.isSearching = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.article_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            isSearching ? '검색 결과가 없습니다' : '$sport 게시글이 없습니다',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching ? '다른 검색어를 입력해보세요' : '첫 번째 게시글을 작성해보세요!',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PostListTile extends StatelessWidget {
  final PinPost post;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _PostListTile({
    required this.post,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CategoryChip(category: post.category),
                const Spacer(),
                Text(
                  timeago.format(post.createdAt, locale: 'ko'),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textDisabled),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              post.title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              post.content,
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 작성자 프로필 사진
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.12),
                  backgroundImage: post.authorProfileImageUrl != null
                      ? CachedNetworkImageProvider(post.authorProfileImageUrl!)
                      : null,
                  child: post.authorProfileImageUrl == null
                      ? Text(
                          post.authorNickname.isNotEmpty
                              ? post.authorNickname[0]
                              : '?',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Text(
                  post.authorNickname,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                _StatIcon(
                    icon: Icons.visibility_outlined, value: post.viewCount),
                const SizedBox(width: 10),
                _StatIcon(
                    icon: Icons.chat_bubble_outline, value: post.commentCount),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onLike,
                  child: _StatIcon(
                    icon: post.isLiked
                        ? Icons.favorite
                        : Icons.favorite_border,
                    value: post.likeCount,
                    color: post.isLiked ? AppTheme.errorColor : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (category) {
      case 'MATCH_SEEK':
        color = AppTheme.primaryColor;
        label = '상대 구함';
      case 'REVIEW':
        color = AppTheme.secondaryColor;
        label = '후기';
      case 'NOTICE':
        color = AppTheme.errorColor;
        label = '공지';
      default:
        color = AppTheme.textSecondary;
        label = '일반';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatIcon extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color? color;

  const _StatIcon({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppTheme.textDisabled),
        const SizedBox(width: 3),
        Text(
          '$value',
          style:
              TextStyle(fontSize: 12, color: color ?? AppTheme.textDisabled),
        ),
      ],
    );
  }
}
