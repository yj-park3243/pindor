import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/community_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';

import '../../widgets/report/report_bottom_sheet.dart';
import '../../widgets/common/fullscreen_image_viewer.dart';
import '../../widgets/common/app_toast.dart';

/// 게시글 상세 + 댓글 화면 (PRD SCREEN-051)
class PostDetailScreen extends ConsumerStatefulWidget {
  final String pinId;
  final String postId;
  final String? sportType;

  const PostDetailScreen({super.key, required this.pinId, required this.postId, this.sportType});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  Comment? _replyTarget;
  bool _isSending = false;
  bool? _localIsLiked;
  int? _localLikeCount;

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike(PinPost post) async {
    final prevLiked = _localIsLiked ?? post.isLiked;
    final prevCount = _localLikeCount ?? post.likeCount;
    // Optimistic UI 업데이트
    setState(() {
      _localIsLiked = !prevLiked;
      _localLikeCount = prevLiked ? prevCount - 1 : prevCount + 1;
    });
    try {
      await ref.read(communityRepositoryProvider).toggleLike(widget.pinId, widget.postId);
      // 서버 성공 후 local state 초기화 + postDetailProvider invalidate하여 최신 likeCount 동기화
      if (mounted) {
        setState(() {
          _localIsLiked = null;
          _localLikeCount = null;
        });
      }
      final key = PostDetailKey(pinId: widget.pinId, postId: widget.postId);
      ref.invalidate(postDetailProvider(key));
    } catch (e) {
      // 실패 시 롤백
      if (mounted) {
        setState(() {
          _localIsLiked = prevLiked;
          _localLikeCount = prevCount;
        });
        AppToast.error('좋아요 처리에 실패했습니다.');
      }
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final key = PostDetailKey(pinId: widget.pinId, postId: widget.postId);
      await ref
          .read(commentsProvider(key).notifier)
          .addComment(text, parentId: _replyTarget?.id);
      _commentController.clear();
      setState(() => _replyTarget = null);

      // 스크롤 맨 아래로
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        AppToast.error('댓글 작성에 실패했습니다: $e');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = PostDetailKey(pinId: widget.pinId, postId: widget.postId);
    final postAsync = ref.watch(postDetailProvider(key));
    final commentsAsync = ref.watch(commentsProvider(key));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          postAsync.whenOrNull(
            data: (post) {
              final isAuthor = post.authorId == currentUser?.id;

              if (isAuthor) {
                // 작성자: 삭제 메뉴
                return PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      final confirmed = await _showDeleteDialog();
                      if (confirmed == true && mounted) {
                        try {
                          await ref
                              .read(communityRepositoryProvider)
                              .deletePost(widget.pinId, widget.postId);
                          if (mounted) context.pop(true);
                        } catch (e) {
                          if (mounted) {
                            AppToast.error('삭제에 실패했습니다.');
                          }
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              color: AppTheme.errorColor, size: 18),
                          SizedBox(width: 8),
                          Text('삭제',
                              style: TextStyle(color: AppTheme.errorColor)),
                        ],
                      ),
                    ),
                  ],
                );
              } else {
                // 타인 게시글: 신고 버튼
                return IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: '신고',
                  onPressed: () => showReportBottomSheet(
                    context,
                    targetType: 'POST',
                    targetId: widget.postId,
                  ),
                );
              }
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: postAsync.when(
              loading: () => const FullScreenLoading(),
              error: (e, _) => ErrorView(
                message: '게시글을 불러올 수 없습니다.',
                onRetry: () => ref.invalidate(postDetailProvider(key)),
              ),
              data: (post) => SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 게시글 본문
                    _PostContent(
                      post: _localIsLiked != null || _localLikeCount != null
                          ? post.copyWith(
                              isLiked: _localIsLiked,
                              likeCount: _localLikeCount,
                            )
                          : post,
                      onLikeTap: () => _toggleLike(post),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),

                    // 댓글 목록
                    Row(
                      children: [
                        const Text(
                          '댓글',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        commentsAsync.when(
                          data: (comments) => Text(
                            '${comments.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    commentsAsync.when(
                      loading: () => const LoadingIndicator(),
                      error: (_, __) => const Text(
                        '댓글을 불러올 수 없습니다.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      data: (comments) {
                        if (comments.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                '첫 번째 댓글을 남겨보세요!',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: comments.map((comment) {
                            return _CommentTile(
                              comment: comment,
                              currentUserId: currentUser?.id,
                              onReply: () {
                                setState(() => _replyTarget = comment);
                              },
                              onDelete: () async {
                                final confirmed = await _showCommentDeleteDialog();
                                if (confirmed == true && mounted) {
                                  final cKey = PostDetailKey(pinId: widget.pinId, postId: widget.postId);
                                  await ref
                                      .read(commentsProvider(cKey).notifier)
                                      .deleteComment(comment.id);
                                }
                              },
                              onDeleteReply: (replyId) async {
                                final confirmed = await _showCommentDeleteDialog();
                                if (confirmed == true && mounted) {
                                  final rKey = PostDetailKey(pinId: widget.pinId, postId: widget.postId);
                                  await ref
                                      .read(commentsProvider(rKey).notifier)
                                      .deleteComment(replyId);
                                }
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),

          // 댓글 입력창
          _CommentInputBar(
            controller: _commentController,
            replyTarget: _replyTarget,
            isSending: _isSending,
            onCancelReply: () => setState(() => _replyTarget = null),
            onSend: _submitComment,
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteDialog() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfirmSheet(
        icon: Icons.delete_outline,
        iconColor: AppTheme.errorColor,
        title: '게시글 삭제',
        subtitle: '게시글을 삭제하면 복구할 수 없습니다.\n삭제하시겠습니까?',
        confirmLabel: '삭제',
      ),
    );
  }

  Future<bool?> _showCommentDeleteDialog() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ConfirmSheet(
        icon: Icons.delete_outline,
        iconColor: AppTheme.errorColor,
        title: '댓글 삭제',
        subtitle: '댓글을 삭제하시겠습니까?',
        confirmLabel: '삭제',
      ),
    );
  }
}

// ─── 게시글 본문 위젯 ─────────────────────────────────────────────────────────

class _PostContent extends StatelessWidget {
  final PinPost post;
  final VoidCallback? onLikeTap;
  const _PostContent({required this.post, this.onLikeTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 카테고리 + 제목
        _buildCategoryChip(post.category),
        const SizedBox(height: 8),
        Text(
          post.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),

        // 작성자 정보
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
              backgroundImage: post.authorProfileImageUrl != null
                  ? CachedNetworkImageProvider(post.authorProfileImageUrl!)
                  : null,
              child: post.authorProfileImageUrl == null
                  ? Text(
                      post.authorNickname.isNotEmpty
                          ? post.authorNickname[0]
                          : '?',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorNickname,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  timeago.format(post.createdAt, locale: 'ko'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 14, color: AppTheme.textDisabled),
                const SizedBox(width: 3),
                Text(
                  '${post.viewCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),

        // 본문
        Text(
          post.content,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
          ),
        ),

        // 이미지
        if (post.imageUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ImageGrid(imageUrls: post.imageUrls),
        ],

        const SizedBox(height: 16),

        // 좋아요 수
        GestureDetector(
          onTap: onLikeTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                post.isLiked ? Icons.favorite : Icons.favorite_border,
                color: post.isLiked ? AppTheme.errorColor : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.likeCount}',
                style: TextStyle(
                  fontSize: 14,
                  color: post.isLiked ? AppTheme.errorColor : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String category) {
    Color color;
    String label;
    switch (category) {
      case 'MATCH_SEEK':
        color = AppTheme.primaryColor;
        label = '상대 구함';
        break;
      case 'REVIEW':
        color = AppTheme.secondaryColor;
        label = '후기';
        break;
      case 'NOTICE':
        color = AppTheme.errorColor;
        label = '공지';
        break;
      default:
        color = AppTheme.textSecondary;
        label = '일반';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> imageUrls;
  const _ImageGrid({required this.imageUrls});

  @override
  Widget build(BuildContext context) {
    if (imageUrls.length == 1) {
      return GestureDetector(
        onTap: () => showFullscreenImage(context, imageUrls, initialIndex: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: imageUrls[0],
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
            memCacheWidth: 400,
            memCacheHeight: 400,
            placeholder: (_, __) => Container(
              height: 200,
              color: Colors.grey.shade100,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, __, ___) => Container(
              height: 200,
              color: Colors.grey.shade100,
              child: const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.grey, size: 40),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: imageUrls.length.clamp(0, 4),
      itemBuilder: (context, index) {
        // 4장 이상이면 마지막 셀에 +N 오버레이 표시
        final isLastAndMore = index == 3 && imageUrls.length > 4;
        return GestureDetector(
          onTap: () =>
              showFullscreenImage(context, imageUrls, initialIndex: index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrls[index],
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  memCacheHeight: 360,
                  placeholder: (_, __) =>
                      Container(color: Colors.grey.shade100),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.shade100,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.grey),
                    ),
                  ),
                ),
              ),
              if (isLastAndMore)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Text(
                        '+${imageUrls.length - 4}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── 댓글 타일 ────────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final String? currentUserId;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final void Function(String replyId) onDeleteReply;

  const _CommentTile({
    required this.comment,
    required this.currentUserId,
    required this.onReply,
    required this.onDelete,
    required this.onDeleteReply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SingleComment(
          comment: comment,
          currentUserId: currentUserId,
          onReply: onReply,
          onDelete: onDelete,
        ),

        // 대댓글
        ...comment.replies.map((reply) {
          return Padding(
            padding: const EdgeInsets.only(left: 32),
            child: _SingleComment(
              comment: reply,
              currentUserId: currentUserId,
              isReply: true,
              onReply: onReply,
              onDelete: () => onDeleteReply(reply.id),
            ),
          );
        }),
      ],
    );
  }
}

class _SingleComment extends StatelessWidget {
  final Comment comment;
  final String? currentUserId;
  final bool isReply;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  const _SingleComment({
    required this.comment,
    required this.currentUserId,
    this.isReply = false,
    required this.onReply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (comment.isDeleted) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '삭제된 댓글입니다.',
          style: TextStyle(
            color: AppTheme.textDisabled,
            fontStyle: FontStyle.italic,
            fontSize: 13,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isReply)
            const Icon(Icons.subdirectory_arrow_right, size: 16, color: AppTheme.textDisabled),
          CircleAvatar(
            radius: 15,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
            backgroundImage: comment.authorProfileImageUrl != null
                ? CachedNetworkImageProvider(comment.authorProfileImageUrl!)
                : null,
            child: comment.authorProfileImageUrl == null
                ? Text(
                    comment.authorNickname.isNotEmpty
                        ? comment.authorNickname[0]
                        : '?',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primaryColor,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorNickname,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeago.format(comment.createdAt, locale: 'ko'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (!isReply)
                      GestureDetector(
                        onTap: onReply,
                        child: const Text(
                          '답글',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (comment.authorId == currentUserId) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Text(
                          '삭제',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 댓글 입력창 ─────────────────────────────────────────────────────────────

class _CommentInputBar extends StatelessWidget {
  final TextEditingController controller;
  final Comment? replyTarget;
  final bool isSending;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  const _CommentInputBar({
    required this.controller,
    required this.replyTarget,
    required this.isSending,
    required this.onCancelReply,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTarget != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppTheme.primaryColor.withOpacity(0.18),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    '${replyTarget!.authorNickname}에게 답글 작성 중',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onCancelReply,
                    child: const Icon(Icons.close, size: 16, color: AppTheme.primaryColor),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: '댓글을 작성하세요...',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                isSending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: onSend,
                        icon: const Icon(Icons.send),
                        color: AppTheme.primaryColor,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 공통 확인 바텀시트 (파괴적 액션용)
class _ConfirmSheet extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String confirmLabel;

  const _ConfirmSheet({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF2A2A2A)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('취소',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(confirmLabel,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
