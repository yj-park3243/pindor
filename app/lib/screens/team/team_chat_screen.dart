import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 전송 실패')),
        );
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
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder: (context) => [
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
            onSendImage: _sendImage,
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('신고'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('욕설/혐오 발언'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('사기/허위 정보'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('스팸/광고'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }
}
