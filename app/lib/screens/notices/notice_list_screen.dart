import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../models/notice.dart';
import '../../providers/notice_provider.dart';
import '../../widgets/common/loading_indicator.dart';

/// 공지사항 목록 화면
class NoticeListScreen extends ConsumerWidget {
  const NoticeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticesAsync = ref.watch(noticeListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
      ),
      body: noticesAsync.when(
        loading: () => const FullScreenLoading(),
        error: (error, _) => _ErrorBody(
          onRetry: () => ref.invalidate(noticeListProvider),
        ),
        data: (notices) {
          if (notices.isEmpty) {
            return const _EmptyBody();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notices.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) {
              return _NoticeListTile(notice: notices[index]);
            },
          );
        },
      ),
    );
  }
}

class _NoticeListTile extends StatelessWidget {
  final Notice notice;

  const _NoticeListTile({required this.notice});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/notices/${notice.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핀 아이콘 (고정 공지)
            if (notice.isPinned) ...[
              const Icon(
                Icons.push_pin_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: notice.isPinned
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notice.createdAt, locale: 'ko'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppTheme.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 52,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          const Text('공지사항을 불러올 수 없습니다.'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 52,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            '등록된 공지사항이 없습니다.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
