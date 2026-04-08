import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

/// 팀 게시판 화면 (독립 화면 + 인라인 버전 모두 지원)
class TeamBoardScreen extends ConsumerWidget {
  final String teamId;

  const TeamBoardScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('팀 게시판'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/teams/$teamId/board/write'),
          ),
        ],
      ),
      body: _BoardContent(teamId: teamId),
    );
  }
}

/// 팀 상세 화면 탭에서 사용하는 인라인 버전
class TeamBoardInlineScreen extends ConsumerWidget {
  final String teamId;

  const TeamBoardInlineScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        _BoardContent(teamId: teamId),
        Positioned(
          bottom: 20,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            onPressed: () => context.push('/teams/$teamId/board/write'),
            backgroundColor: AppTheme.primaryColor,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _BoardContent extends ConsumerStatefulWidget {
  final String teamId;

  const _BoardContent({required this.teamId});

  @override
  ConsumerState<_BoardContent> createState() => _BoardContentState();
}

class _BoardContentState extends ConsumerState<_BoardContent> {
  int _tabIndex = 0;

  static const _tabs = ['공지', '일정', '자유'];
  static const _categories = ['NOTICE', 'SCHEDULE', 'FREE'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AdaptiveSegmentedControl(
            labels: _tabs,
            selectedIndex: _tabIndex,
            onValueChanged: (index) => setState(() => _tabIndex = index),
          ),
        ),
        Expanded(
          child: _PostList(
            teamId: widget.teamId,
            category: _categories[_tabIndex],
          ),
        ),
      ],
    );
  }
}

class _PostList extends ConsumerWidget {
  final String teamId;
  final String category; // notice | schedule | free

  const _PostList({required this.teamId, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsState = ref.watch(teamPostsProvider(teamId));

    if (postsState.isLoading) return const FullScreenLoading();
    if (postsState.error != null) {
      return ErrorView(
        message: '게시글을 불러올 수 없습니다.',
        onRetry: () =>
            ref.read(teamPostsProvider(teamId).notifier).refresh(),
      );
    }

    final List<TeamPost> posts;
    switch (category) {
      case 'NOTICE':
        posts = postsState.notice;
        break;
      case 'SCHEDULE':
        posts = postsState.schedule;
        break;
      default:
        posts = postsState.free;
    }

    // 공지: isPinned 먼저
    final sorted = [...posts]
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    if (sorted.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined,
                size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 12),
            Text(
              '게시글이 없습니다',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(teamPostsProvider(teamId).notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sorted.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final post = sorted[index];
          return _PostTile(
            post: post,
            onTap: () =>
                context.push('/teams/$teamId/board/${post.id}'),
          );
        },
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final TeamPost post;
  final VoidCallback onTap;

  const _PostTile({required this.post, required this.onTap});

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
                if (post.isPinned) ...[
                  const Icon(
                    Icons.push_pin,
                    size: 14,
                    color: AppTheme.errorColor,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    post.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: post.isPinned
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  post.author?.nickname ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MM.dd').format(post.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.remove_red_eye_outlined,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '${post.viewCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (post.commentCount > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble_outline,
                      size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    '${post.commentCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
