import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/theme.dart';
import '../../models/chat_room.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/user_avatar.dart';

/// 채팅방 목록 화면 (PRD SCREEN-031)
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatRoomsAsync = ref.watch(chatRoomListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/matches');
            }
          },
        ),
      ),
      body: chatRoomsAsync.when(
        loading: () => const FullScreenLoading(),
        error: (e, _) => ErrorView(
          message: '채팅방 목록을 불러올 수 없습니다.',
          onRetry: () => ref.invalidate(chatRoomListProvider),
        ),
        data: (rooms) {
          if (rooms.isEmpty) {
            return _EmptyChatState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(chatRoomListProvider);
            },
            child: ListView.separated(
              itemCount: rooms.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 80, endIndent: 16),
              itemBuilder: (context, index) {
                return _ChatRoomTile(
                  room: rooms[index],
                  onTap: () => context.go('/chats/${rooms[index].id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 빈 채팅 상태 위젯
class _EmptyChatState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 일러스트 영역
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: AppTheme.primaryColor,
                  ),
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '아직 채팅이 없습니다',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '매칭이 성사되면 자동으로\n채팅방이 열립니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withOpacity(0.8),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;

  const _ChatRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lastMessage = room.lastMessage;
    final hasUnread = room.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: const Color(0xFF1E1E1E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 프로필 아바타
            UserAvatar(
              imageUrl: room.opponent.profileImageUrl,
              size: 52,
              nickname: room.opponent.nickname,
            ),
            const SizedBox(width: 12),
            // 텍스트 영역
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 닉네임 + 시간
                  Row(
                    children: [
                      Text(
                        room.opponent.nickname,
                        style: TextStyle(
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (lastMessage != null)
                        Text(
                          timeago.format(lastMessage.createdAt,
                              locale: 'ko'),
                          style: TextStyle(
                            fontSize: 11,
                            color: hasUnread
                                ? AppTheme.primaryColor
                                : AppTheme.textDisabled,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // 최근 메시지 + 안읽은 수
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage?.messageType == 'IMAGE'
                              ? '[사진]'
                              : lastMessage?.content ?? '아직 메시지가 없습니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(
                              minWidth: 22, maxWidth: 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${room.unreadCount > 99 ? '99+' : room.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
