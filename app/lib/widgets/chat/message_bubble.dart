import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/message.dart';

/// 채팅 메시지 버블 위젯
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSenderInfo;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSenderInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _SystemMessageBubble(content: message.content);
    }

    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 48 : 0,
        right: isMine ? 0 : 48,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine && showSenderInfo)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                message.senderNickname,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                _buildAvatar(),
                const SizedBox(width: 8),
              ],
              Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  _buildBubble(context),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('HH:mm').format(message.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textDisabled,
                    ),
                  ),
                ],
              ),
              if (isMine) const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final initial = message.senderNickname.isNotEmpty
        ? message.senderNickname[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: message.senderProfileImageUrl != null
          ? CachedNetworkImageProvider(message.senderProfileImageUrl!)
          : null,
      child: message.senderProfileImageUrl == null
          ? Text(
              initial,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            )
          : null,
    );
  }

  Widget _buildBubble(BuildContext context) {
    if (message.isImage) {
      return _ImageBubble(
        imageUrl: message.imageUrl ?? message.content,
        isMine: isMine,
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? AppTheme.primaryColor : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: isMine ? Colors.white : AppTheme.textPrimary,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMine;

  const _ImageBubble({required this.imageUrl, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(14),
        topRight: const Radius.circular(14),
        bottomLeft: Radius.circular(isMine ? 14 : 4),
        bottomRight: Radius.circular(isMine ? 4 : 14),
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 200,
          height: 200,
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 200,
          height: 200,
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}

class _SystemMessageBubble extends StatelessWidget {
  final String content;

  const _SystemMessageBubble({required this.content});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
