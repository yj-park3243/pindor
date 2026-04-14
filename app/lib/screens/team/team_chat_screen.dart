import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../../config/theme.dart';
import '../../core/utils/permission_helper.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../repositories/upload_repository.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/app_toast.dart';

/// 팀 단체 채팅 화면
/// chat_room_screen.dart 스타일과 동일하게 구현
class TeamChatScreen extends ConsumerStatefulWidget {
  final String roomId;

  const TeamChatScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends ConsumerState<TeamChatScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      imageQuality: 80,
    );
    if (image == null) return;

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final url = await uploadRepo.uploadProfileImage(image.path);
      await ref
          .read(chatMessagesProvider(widget.roomId).notifier)
          .sendImageMessage(url);
    } catch (e) {
      if (mounted) {
        AppToast.error('이미지 전송 실패');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.roomId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('팀 채팅'),
        actions: [
          PullDownButton(
            itemBuilder: (context) => [
              PullDownMenuItem(
                title: '신고',
                icon: Icons.flag_outlined,
                isDestructive: true,
                onTap: _showReportDialog,
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
          // ─── 메시지 목록 ───
          Expanded(
            child: messagesAsync.when(
              loading: () => const FullScreenLoading(),
              error: (e, _) => const ErrorView(
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

          // ─── 입력바 ───
          ChatInputBar(
            onSendText: (text) async {
              await ref
                  .read(chatMessagesProvider(widget.roomId).notifier)
                  .sendTextMessage(text);
              _scrollToBottom();
            },
            onPlusPressed: _sendImage,
          ),
        ],
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
            _buildReportOption(ctx, '욕설/혐오 발언'),
            const SizedBox(height: 8),
            _buildReportOption(ctx, '사기/허위 정보'),
            const SizedBox(height: 8),
            _buildReportOption(ctx, '스팸/광고'),
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

  Widget _buildReportOption(BuildContext ctx, String label) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx),
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
