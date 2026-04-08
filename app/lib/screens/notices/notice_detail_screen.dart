import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../providers/notice_provider.dart';
import '../../widgets/common/loading_indicator.dart';

/// 공지사항 상세 화면
class NoticeDetailScreen extends ConsumerWidget {
  final String noticeId;

  const NoticeDetailScreen({super.key, required this.noticeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticeAsync = ref.watch(noticeDetailProvider(noticeId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: noticeAsync.when(
        loading: () => const FullScreenLoading(),
        error: (error, _) => Center(
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
                onPressed: () => ref.invalidate(noticeDetailProvider(noticeId)),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (notice) {
          final dateStr = DateFormat('yyyy년 M월 d일').format(notice.createdAt);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 고정 공지 배지
                if (notice.isPinned) ...[
                  const Row(
                    children: [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: AppTheme.primaryColor,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '중요 공지',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // 제목
                Text(
                  notice.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 8),

                // 날짜
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // 본문
                SelectableText(
                  notice.content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                    height: 1.7,
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}
