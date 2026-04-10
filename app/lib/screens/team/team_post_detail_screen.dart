import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/team.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../repositories/team_repository.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';

/// 팀 게시글 상세 + 댓글 화면
class TeamPostDetailScreen extends ConsumerWidget {
  final String teamId;
  final String postId;

  const TeamPostDetailScreen({
    super.key,
    required this.teamId,
    required this.postId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(
      teamPostDetailProvider((teamId: teamId, postId: postId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('게시글')),
      body: postAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '게시글을 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(
            teamPostDetailProvider((teamId: teamId, postId: postId)),
          ),
        ),
        data: (post) => _PostDetailContent(
          post: post,
          teamId: teamId,
          postId: postId,
        ),
      ),
    );
  }
}

class _PostDetailContent extends ConsumerStatefulWidget {
  final TeamPost post;
  final String teamId;
  final String postId;

  const _PostDetailContent({
    required this.post,
    required this.teamId,
    required this.postId,
  });

  @override
  ConsumerState<_PostDetailContent> createState() => _PostDetailContentState();
}

class _PostDetailContentState extends ConsumerState<_PostDetailContent> {
  final _commentController = TextEditingController();
  String? _replyToId;
  String? _replyToNickname;
  bool _isSendingComment = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSendingComment = true);
    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.createTeamPostComment(
        widget.teamId,
        widget.postId,
        {
          'content': content,
          if (_replyToId != null) 'parentId': _replyToId,
        },
      );

      _commentController.clear();
      setState(() {
        _replyToId = null;
        _replyToNickname = null;
      });

      ref.invalidate(
        teamPostCommentsProvider(
          (teamId: widget.teamId, postId: widget.postId),
        ),
      );
    } catch (e) {
      if (mounted) {
        AppToast.error('댓글 전송 실패: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(
      teamPostCommentsProvider(
        (teamId: widget.teamId, postId: widget.postId),
      ),
    );
    final currentUser = ref.watch(currentUserProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 게시글 헤더 ───
                Row(
                  children: [
                    _CategoryBadge(category: widget.post.category),
                    if (widget.post.isPinned) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.push_pin,
                          size: 14, color: AppTheme.errorColor),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.post.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF2A2A2A),
                      child: Text(
                        widget.post.author?.nickname.isNotEmpty == true
                            ? widget.post.author!.nickname[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.post.author?.nickname ?? '알 수 없음',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('yyyy.MM.dd HH:mm')
                          .format(widget.post.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // ─── 본문 ───
                Text(
                  widget.post.content,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.post.viewCount}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),

                const Divider(height: 32),

                // ─── 댓글 ───
                Text(
                  '댓글 ${widget.post.commentCount}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                commentsAsync.when(
                  loading: () => const LoadingIndicator(),
                  error: (e, _) => const Text('댓글을 불러올 수 없습니다.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  data: (comments) => Column(
                    children: comments
                        .map((c) => _CommentItem(
                              comment: c,
                              currentUserId: currentUser?.id,
                              onReply: (id, nickname) {
                                setState(() {
                                  _replyToId = id;
                                  _replyToNickname = nickname;
                                });
                                FocusScope.of(context).requestFocus(FocusNode());
                              },
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── 댓글 입력 ───
        _CommentInputBar(
          controller: _commentController,
          replyToNickname: _replyToNickname,
          onCancelReply: () => setState(() {
            _replyToId = null;
            _replyToNickname = null;
          }),
          onSend: _submitComment,
          isSending: _isSendingComment,
        ),
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (category) {
      case 'NOTICE':
        color = AppTheme.errorColor;
        label = '공지';
        break;
      case 'SCHEDULE':
        color = AppTheme.secondaryColor;
        label = '일정';
        break;
      default:
        color = AppTheme.primaryColor;
        label = '자유';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  final TeamPostComment comment;
  final String? currentUserId;
  final void Function(String id, String nickname) onReply;

  const _CommentItem({
    required this.comment,
    this.currentUserId,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = comment.author?.nickname ?? '알 수 없음';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF2A2A2A),
                child: Text(
                  nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          nickname,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MM.dd HH:mm')
                              .format(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comment.content,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => onReply(comment.id, nickname),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '답글',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 답글
        if (comment.replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              children: comment.replies
                  .map((reply) => _ReplyItem(reply: reply))
                  .toList(),
            ),
          ),

        const Divider(height: 1),
      ],
    );
  }
}

class _ReplyItem extends StatelessWidget {
  final TeamPostComment reply;

  const _ReplyItem({required this.reply});

  @override
  Widget build(BuildContext context) {
    final nickname = reply.author?.nickname ?? '알 수 없음';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.subdirectory_arrow_right,
              size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF2A2A2A),
            child: Text(
              nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      nickname,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MM.dd HH:mm').format(reply.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(reply.content,
                    style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentInputBar extends StatelessWidget {
  final TextEditingController controller;
  final String? replyToNickname;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final bool isSending;

  const _CommentInputBar({
    required this.controller,
    this.replyToNickname,
    required this.onCancelReply,
    required this.onSend,
    required this.isSending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: const Border(
          top: BorderSide(color: Color(0xFF2A2A2A)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyToNickname != null)
              Container(
                color: const Color(0xFF2A2A2A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '$replyToNickname 에게 답글',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onCancelReply,
                      child: const Icon(Icons.close,
                          size: 16, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: '댓글을 입력하세요...',
                        hintStyle: const TextStyle(fontSize: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: isSending ? null : onSend,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: isSending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
