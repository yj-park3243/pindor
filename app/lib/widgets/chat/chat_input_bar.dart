import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 채팅 입력바 위젯
class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSendText;
  final VoidCallback? onSendImage;
  final bool enabled;

  const ChatInputBar({
    super.key,
    required this.onSendText,
    this.onSendImage,
    this.enabled = true,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 10 : 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 이미지 첨부 버튼
          IconButton(
            onPressed: widget.enabled ? widget.onSendImage : null,
            icon: const Icon(Icons.image_outlined),
            color: AppTheme.textSecondary,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: const EdgeInsets.all(4),
          ),

          // 텍스트 입력
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                maxLines: null,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '메시지를 입력하세요...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  counterText: '',
                  filled: false,
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 전송 버튼
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hasText && widget.enabled
                  ? AppTheme.primaryColor
                  : const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _hasText && widget.enabled ? _send : null,
              icon: const Icon(Icons.send_rounded, size: 20),
              color: _hasText ? Colors.white : AppTheme.textDisabled,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
