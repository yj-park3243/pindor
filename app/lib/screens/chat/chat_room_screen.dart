import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../core/utils/permission_helper.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/matching_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/game_result_sheet.dart';
import '../../widgets/report/report_bottom_sheet.dart';
import '../../core/network/socket_service.dart';
import 'package:pull_down_button/pull_down_button.dart';
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
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  @override
  void initState() {
    super.initState();
    // 소켓 매칭 상태 변경 이벤트 구독
    _statusSub = SocketService.instance.onMatchStatusChanged.listen((data) {
      final status = data['status'] as String?;
      final eventMatchId = data['matchId'] as String?;

      // 현재 채팅방의 matchId를 동적으로 확인
      final chatRooms = ref.read(chatRoomListProvider).valueOrNull;
      final room = chatRooms?.where((r) => r.id == widget.roomId).firstOrNull;
      final matchId = room?.matchId;

      if (matchId == null || eventMatchId != matchId) return;

      if (status == 'COMPLETED' && mounted) {
        ref.invalidate(matchListProvider(null));
        AppToast.info('매칭이 완료되었습니다.');
        context.go('/matches/$matchId');
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
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
    if (!mounted) return;

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
          PullDownButton(
            itemBuilder: (context) => [
              PullDownMenuItem(
                title: '신고',
                icon: Icons.flag_outlined,
                isDestructive: true,
                onTap: () => showReportBottomSheet(
                  context,
                  targetType: 'CHAT',
                  targetId: widget.roomId,
                ),
              ),
            ],
            buttonBuilder: (context, showMenu) => IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: showMenu,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 인증번호 고정 배너
          _VerificationCodeBanner(roomId: widget.roomId),

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
                            messages[index - 1].senderId != msg.senderId ||
                            messages[index - 1].isSystem);

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

}

/// 승부 결과 버튼 (ChatInputBar 위)
class _GameResultButton extends ConsumerWidget {
  final String roomId;

  const _GameResultButton({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // matchId 조회 (채팅방 목록 → 매칭 목록 fallback)
    String? matchId;
    final chatRooms = ref.watch(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == roomId).firstOrNull;
    matchId = room?.matchId;

    if (matchId == null || matchId.isEmpty) {
      final matches = ref.watch(matchListProvider(null)).valueOrNull;
      final match = matches?.where((m) => m.chatRoomId == roomId).firstOrNull;
      matchId = match?.id;
    }

    // 이미 결과 제출했거나 매칭 완료 시 버튼 숨김
    if (matchId != null && matchId.isNotEmpty) {
      final matchAsync = ref.watch(matchDetailProvider(matchId));
      final match = matchAsync.valueOrNull;
      if (match != null && (match.myResultSubmitted || match.isCompleted)) {
        return const SizedBox.shrink();
      }
      // 아직 로드 안 됐으면 fetch 트리거 (최신 상태 반영)
      if (!matchAsync.hasValue && !matchAsync.isLoading) {
        ref.invalidate(matchDetailProvider(matchId));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0A0A0A),
      child: SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          onPressed: () => _onGameResult(context, ref),
          icon: const Icon(Icons.emoji_events_rounded, size: 18),
          label: const Text('승부 결과', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.secondaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Future<void> _onGameResult(BuildContext context, WidgetRef ref) async {
    // 1차: 캐시된 채팅방 목록에서 matchId 조회
    String? matchId;
    final chatRooms = ref.read(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == roomId).firstOrNull;
    matchId = room?.matchId;

    // 2차: 캐시에 없으면 매칭 목록에서 chatRoomId로 역조회
    if (matchId == null || matchId.isEmpty) {
      final matches = ref.read(matchListProvider(null)).valueOrNull;
      final match = matches?.where((m) => m.chatRoomId == roomId).firstOrNull;
      matchId = match?.id;
    }

    // 3차: 서버에서 채팅방 목록 갱신 후 재시도
    if (matchId == null || matchId.isEmpty) {
      final repo = ref.read(chatRepositoryProvider);
      final freshRooms = await repo.fetchAndCacheChatRooms();
      final freshRoom = freshRooms.where((r) => r.id == roomId).firstOrNull;
      matchId = freshRoom?.matchId;
    }

    if (matchId == null || matchId.isEmpty) {
      AppToast.info('매칭 정보를 찾을 수 없습니다.');
      return;
    }

    if (!context.mounted) return;

    // 수신된 인증번호가 있으면 자동 입력
    final receivedCode = ref.read(receivedVerificationCodeProvider(roomId));

    showGameResultSheet(
      context,
      ref: ref,
      matchId: matchId,
      initialVerificationCode: receivedCode,
      onSubmitted: () {
        ref.invalidate(matchDetailProvider(matchId!));
      },
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

/// 인증번호 고정 배너 (채팅방 상단)
class _VerificationCodeBanner extends ConsumerWidget {
  final String roomId;

  const _VerificationCodeBanner({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // matchId 조회
    String? matchId;
    final chatRooms = ref.watch(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == roomId).firstOrNull;
    matchId = room?.matchId;

    if (matchId == null || matchId.isEmpty) {
      final matches = ref.watch(matchListProvider(null)).valueOrNull;
      final match = matches?.where((m) => m.chatRoomId == roomId).firstOrNull;
      matchId = match?.id;
    }

    if (matchId == null || matchId.isEmpty) return const SizedBox.shrink();

    final matchAsync = ref.watch(matchDetailProvider(matchId));
    final match = matchAsync.valueOrNull;
    final code = match?.myVerificationCode;

    if (code == null || code.isEmpty) return const SizedBox.shrink();

    // 완료/취소된 매칭이면 숨김
    if (match!.isCompleted || match.isCancelled) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A3E), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.pin_rounded,
              size: 18,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '매칭 결과 입력 인증번호',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '상대방을 만나면 이 번호를 알려주세요.\n'
                          '상대방이 이 번호를 입력해야 매칭 결과를 제출할 수 있습니다.\n'
                          '전송 버튼으로 채팅을 통해 보낼 수도 있습니다.',
                      triggerMode: TooltipTriggerMode.tap,
                      preferBelow: true,
                      showDuration: const Duration(seconds: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A3E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        height: 1.5,
                      ),
                      child: const Icon(
                        Icons.help_outline_rounded,
                        size: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  code.split('').join(' '),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryColor,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ref
                  .read(chatMessagesProvider(roomId).notifier)
                  .sendVerificationCodeMessage(code);
              AppToast.success('인증번호를 상대방에게 전송했습니다');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    '전송',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
