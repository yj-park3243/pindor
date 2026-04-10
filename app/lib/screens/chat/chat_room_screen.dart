import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/game_result_sheet.dart';
import '../../core/network/socket_service.dart';
import 'location_picker_screen.dart';

/// 채팅방 화면 (PRD SCREEN-032)
/// - 메시지 목록
/// - 텍스트/이미지 입력
/// - 경기 확정 버튼
/// - 신고 기능
class ChatRoomScreen extends ConsumerStatefulWidget {
  final String roomId;

  const ChatRoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _scrollController = ScrollController();
  Timer? _typingThrottle;

  @override
  void dispose() {
    _typingThrottle?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 2초 throttle로 타이핑 이벤트 전송
  void _onTyping() {
    if (_typingThrottle?.isActive ?? false) return;
    SocketService.instance.sendTyping(widget.roomId);
    _typingThrottle = Timer(const Duration(seconds: 2), () {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null) return;

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final url = await uploadRepo.uploadChatImage(image.path);
      await ref
          .read(chatMessagesProvider(widget.roomId).notifier)
          .sendImageMessage(url);
    } catch (e) {
      if (mounted) {
        AppToast.error('이미지 전송 실패');
      }
    }
  }

  /// "+" 버튼 클릭 시 첨부 옵션 바텀시트 표시
  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // 옵션 버튼들 (가로 나열)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 사진
                _AttachmentOption(
                  icon: Icons.photo_library_rounded,
                  label: '사진',
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendImage();
                  },
                ),
                // 위치 전송
                _AttachmentOption(
                  icon: Icons.location_on_rounded,
                  label: '위치 전송',
                  color: AppTheme.primaryColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendLocation();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 위치 선택 화면으로 이동 후 결과 받아 위치 메시지 전송
  Future<void> _sendLocation() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );

    if (result == null) return;
    if (!mounted) return;

    final lat = (result['latitude'] as num?)?.toDouble();
    final lng = (result['longitude'] as num?)?.toDouble();
    final address = result['address'] as String?;

    if (lat == null || lng == null) return;

    try {
      await ref
          .read(chatMessagesProvider(widget.roomId).notifier)
          .sendLocationMessage(
            latitude: lat,
            longitude: lng,
            address: address,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        AppToast.error('위치 전송 실패. 네트워크를 확인해주세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.roomId));
    final currentUser = ref.watch(currentUserProvider);
    final isOpponentTyping = ref.watch(socketTypingProvider(widget.roomId));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') {
                _showReportDialog();
              } else if (value == 'confirm') {
                _showConfirmMatchDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'confirm',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text('경기 확정'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('신고', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 메시지 목록
          Expanded(
            child: messagesAsync.when(
              loading: () => const FullScreenLoading(),
              error: (e, _) => ErrorView(
                message: '메시지를 불러올 수 없습니다.',
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      '첫 메시지를 보내보세요!',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMine = msg.senderId == currentUser?.id;
                    final showSenderInfo = !isMine &&
                        (index == 0 ||
                            messages[index - 1].senderId != msg.senderId);

                    return MessageBubble(
                      message: msg,
                      isMine: isMine,
                      showSenderInfo: showSenderInfo,
                    );
                  },
                );
              },
            ),
          ),

          // 타이핑 표시
          if (isOpponentTyping)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              color: const Color(0xFF0A0A0A),
              child: const Text(
                '상대방이 입력 중...',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // 승부 결과 입력 버튼
          _GameResultButton(
            roomId: widget.roomId,
          ),

          // 입력바
          ChatInputBar(
            onSendText: (text) async {
              try {
                await ref
                    .read(chatMessagesProvider(widget.roomId).notifier)
                    .sendTextMessage(text);
                _scrollToBottom();
              } catch (e) {
                if (mounted) {
                  AppToast.error('메시지 전송 실패. 네트워크를 확인해주세요.');
                }
              }
            },
            onPlusPressed: _showAttachmentSheet,
            onTyping: _onTyping,
          ),
        ],
      ),
    );
  }

  void _showConfirmMatchDialog() {
    // ChatRoom의 matchId를 가져와서 확정 화면으로 이동
    final chatRooms = ref.read(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == widget.roomId).firstOrNull;
    final matchId = room?.matchId;

    if (matchId == null || matchId.isEmpty) {
      AppToast.info('매칭 상세에서 확정해주세요');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
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
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sports_score_outlined,
                  color: Color(0xFF4F46E5), size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              '경기 확정',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '날짜, 시간, 장소를 정하고\n경기를 확정하시겠습니까?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
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
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/matches/$matchId/confirm');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('확정하기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
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
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.report_outlined,
                  color: Colors.red, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              '신고',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '신고 유형을 선택해주세요.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 20),
            _ReportOption(
              label: '욕설/혐오 발언',
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
            _ReportOption(
              label: '사기/허위 정보',
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
            _ReportOption(
              label: '스팸/광고',
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
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
          ],
        ),
      ),
    );
  }
}

/// 승부 결과 버튼 (ChatInputBar 위)
class _GameResultButton extends ConsumerWidget {
  final String roomId;

  const _GameResultButton({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatMessagesProvider(roomId)).valueOrNull ?? [];
    final currentUser = ref.watch(currentUserProvider);
    final myId = currentUser?.id;

    // SYSTEM 메시지 제외, 양쪽 유저가 각각 3개 이상 보내야 활성화
    final userMessages = messages.where((m) => m.messageType != 'SYSTEM').toList();
    final myCount = userMessages.where((m) => m.senderId == myId).length;
    final otherCount = userMessages.where((m) => m.senderId != myId).length;
    final enabled = myCount >= 3 && otherCount >= 3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0A0A0A),
      child: SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          onPressed: enabled ? () => _onGameResult(context, ref) : null,
          icon: const Icon(Icons.emoji_events_rounded, size: 18),
          label: const Text('승부 결과', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.secondaryColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF2A2A2A),
            disabledForegroundColor: const Color(0xFF6B7280),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _onGameResult(BuildContext context, WidgetRef ref) {
    final chatRooms = ref.read(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == roomId).firstOrNull;
    final matchId = room?.matchId;

    if (matchId == null || matchId.isEmpty) {
      AppToast.info('매칭 정보를 찾을 수 없습니다.');
      return;
    }

    showGameResultSheet(
      context,
      ref: ref,
      matchId: matchId,
    );
  }
}

class _ReportOption extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ReportOption({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 첨부 옵션 버튼 (아이콘 + 텍스트 세로 배치)
class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AppTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
