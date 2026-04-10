import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/theme.dart';
import '../../models/notification.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/empty_state.dart';

/// 알림 목록 화면 (PRD SCREEN-063)
class NotificationListScreen extends ConsumerWidget {
  const NotificationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          notificationsAsync.whenOrNull(
            data: (notifications) {
              final hasUnread = notifications.any((n) => !n.isRead);
              if (!hasUnread) return null;
              return TextButton(
                onPressed: () => ref
                    .read(notificationListProvider.notifier)
                    .markAllAsRead(),
                child: const Text('모두 읽음'),
              );
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('알림을 불러올 수 없습니다.'),
              TextButton(
                onPressed: () =>
                    ref.read(notificationListProvider.notifier).refresh(),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: '알림이 없습니다',
              subtitle: '새로운 알림이 오면 여기에 표시됩니다.',
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(notificationListProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                return _NotificationTile(
                  notification: notifications[index],
                  onTap: () => _handleNotificationTap(
                      context, ref, notifications[index]),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _handleNotificationTap(
      BuildContext context, WidgetRef ref, AppNotification notification) {
    // 읽음 처리
    if (!notification.isRead) {
      ref.read(notificationListProvider.notifier).markAsRead(notification.id);
    }

    // 딥링크 처리
    final deepLink = notification.deepLink;
    if (deepLink != null && context.mounted) {
      context.push(deepLink);
    }
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return Material(
      color: isUnread
          ? AppTheme.primaryColor.withOpacity(0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 알림 타입 아이콘
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _getIconColor(notification.type).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIcon(notification.type),
                  color: _getIconColor(notification.type),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      timeago.format(notification.createdAt, locale: 'ko'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'MATCH_FOUND':
      case 'MATCH_REQUEST_RECEIVED':
      case 'MATCH_ACCEPTED':
      case 'MATCH_REJECTED':
      case 'MATCH_EXPIRED':
        return Icons.sports;
      case 'CHAT_MESSAGE':
      case 'CHAT_IMAGE':
        return Icons.chat_bubble_outline;
      case 'GAME_RESULT_SUBMITTED':
      case 'GAME_RESULT_CONFIRMED':
        return Icons.check_circle_outline;
      case 'SCORE_UPDATED':
        return Icons.trending_up;
      case 'TIER_CHANGED':
        return Icons.diamond_outlined;
      case 'COMMUNITY_REPLY':
        return Icons.forum_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'MATCH_FOUND':
      case 'MATCH_REQUEST_RECEIVED':
      case 'MATCH_ACCEPTED':
        return AppTheme.primaryColor;
      case 'MATCH_REJECTED':
      case 'MATCH_EXPIRED':
        return AppTheme.errorColor;
      case 'CHAT_MESSAGE':
      case 'CHAT_IMAGE':
        return AppTheme.secondaryColor;
      case 'GAME_RESULT_SUBMITTED':
      case 'GAME_RESULT_CONFIRMED':
        return AppTheme.secondaryColor;
      case 'SCORE_UPDATED':
      case 'TIER_CHANGED':
        return AppTheme.warningColor;
      case 'COMMUNITY_REPLY':
        return AppTheme.primaryColor;
      default:
        return AppTheme.textSecondary;
    }
  }
}
