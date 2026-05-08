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
import '../../core/utils/location_utils.dart';
import '../../repositories/matching_repository.dart';
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
  bool _didInitialScroll = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    // 소켓 매칭 상태 변경 이벤트 구독
    _statusSub = SocketService.instance.onMatchStatusChanged.listen((data) {
      final status = data['status'] as String?;
      final eventMatchId = data['matchId'] as String?;

      // 현재 채팅방의 matchId를 동적으로 확인
      // 캐시 누락 시 매칭 목록에서도 fallback 조회
      final chatRooms = ref.read(chatRoomListProvider).valueOrNull;
      final room = chatRooms?.where((r) => r.id == widget.roomId).firstOrNull;
      String? matchId = room?.matchId;
      if (matchId == null || matchId.isEmpty) {
        final matches = ref.read(matchListProvider(null)).valueOrNull;
        matchId = matches
            ?.where((m) => m.chatRoomId == widget.roomId)
            .firstOrNull
            ?.id;
      }

      if (matchId == null || eventMatchId != matchId) return;

      if (status == 'COMPLETED' && mounted) {
        ref.read(matchListForceRefreshProvider.notifier).state = true;
        ref.invalidate(matchListProvider(null));
        ref.invalidate(matchDetailProvider(matchId));
        AppToast.success('매칭이 완료되었습니다!');
        // 다음 프레임에 이동 (Navigator dispose 잠금 충돌 방지)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/matches', extra: {'initialTab': 1});
        });
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

  /// 바닥 근처(120px 이내)면 true
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= 120;
  }

  /// 메시지 변화 시 자동 스크롤 결정.
  /// - 최초 로드: 무조건 바닥으로
  /// - 이후: 새 메시지가 추가됐고 사용자가 바닥 근처에 있을 때만
  void _maybeAutoScroll(int messageCount) {
    final isInitial = !_didInitialScroll;
    final hasNew = messageCount > _lastMessageCount;
    final wasAtBottom = _isNearBottom();
    _lastMessageCount = messageCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (isInitial) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        _didInitialScroll = true;
      } else if (hasNew && wasAtBottom) {
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
          // 우리 만났어요 배너 (CHAT/CONFIRMED 상태에서만 표시)
          _MetConfirmBanner(roomId: widget.roomId),

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

                _maybeAutoScroll(messages.length);

                return ListView.builder(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
    // 키보드 닫기
    FocusScope.of(context).unfocus();
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

    showGameResultSheet(
      context,
      ref: ref,
      matchId: matchId,
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
    final iconColor = color ?? AppTheme.primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor.withOpacity(0.5), width: 1.5),
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

/// 우리 만났어요 배너 (채팅방 상단) — CHAT/CONFIRMED 상태에서만 노출
class _MetConfirmBanner extends ConsumerStatefulWidget {
  final String roomId;

  const _MetConfirmBanner({required this.roomId});

  @override
  ConsumerState<_MetConfirmBanner> createState() => _MetConfirmBannerState();
}

class _MetConfirmBannerState extends ConsumerState<_MetConfirmBanner> {
  bool _submitting = false;
  StreamSubscription<Map<String, dynamic>>? _metSub;
  String? _subscribedMatchId;

  @override
  void dispose() {
    _metSub?.cancel();
    if (_subscribedMatchId != null) {
      SocketService.instance.leaveMatch(_subscribedMatchId!);
    }
    super.dispose();
  }

  void _ensureSubscribed(String matchId) {
    if (_subscribedMatchId == matchId) return;
    if (_subscribedMatchId != null) {
      _metSub?.cancel();
      SocketService.instance.leaveMatch(_subscribedMatchId!);
    }
    _subscribedMatchId = matchId;
    SocketService.instance.joinMatch(matchId);
    _metSub = SocketService.instance.onMatchMetUpdated
        .where((d) => d['matchId'] == matchId)
        .listen((_) {
      if (mounted) ref.invalidate(matchDetailProvider(matchId));
    });
  }

  Future<void> _confirmMet(String matchId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('우리 만났어요', style: TextStyle(color: Colors.white)),
        content: const Text(
          '한 번 누르면 취소할 수 없습니다. 정말 상대를 만나셨나요?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('만났어요'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      // 만남 확인 시점의 위치를 함께 전송 (실패 시 위치 없이 진행)
      double? lat;
      double? lng;
      try {
        final pos = await LocationUtils.getCurrentPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}

      await ref.read(matchingRepositoryProvider).confirmMet(
            matchId,
            latitude: lat,
            longitude: lng,
          );
      ref.invalidate(matchDetailProvider(matchId));
    } catch (_) {
      if (mounted) AppToast.error('만남 확인에 실패했습니다');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? matchId;
    final chatRooms = ref.watch(chatRoomListProvider).valueOrNull;
    final room = chatRooms?.where((r) => r.id == widget.roomId).firstOrNull;
    matchId = room?.matchId;

    if (matchId == null || matchId.isEmpty) {
      final matches = ref.watch(matchListProvider(null)).valueOrNull;
      final match = matches?.where((m) => m.chatRoomId == widget.roomId).firstOrNull;
      matchId = match?.id;
    }

    if (matchId == null || matchId.isEmpty) return const SizedBox.shrink();
    _ensureSubscribed(matchId);

    final matchAsync = ref.watch(matchDetailProvider(matchId));
    final match = matchAsync.valueOrNull;
    if (match == null) return const SizedBox.shrink();
    if (match.isCompleted || match.isCancelled) return const SizedBox.shrink();
    if (!match.isChat && !match.isConfirmed) return const SizedBox.shrink();

    Widget content;
    if (match.bothMetConfirmed) {
      content = Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '양쪽 모두 만남을 확인했습니다. 게임 후 결과를 입력해주세요.',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    } else if (match.myMetConfirmed) {
      content = Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '상대 응답 기다리는 중…',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          Expanded(
            child: Text(
              match.opponentMetConfirmed
                  ? '상대가 만남 확인을 했어요. 만나셨으면 눌러주세요.'
                  : '상대를 만나면 "우리 만났어요"를 눌러주세요.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _submitting ? null : () => _confirmMet(matchId!),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('우리 만났어요',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A3E), width: 1),
        ),
      ),
      child: content,
    );
  }
}
