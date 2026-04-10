import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/message.dart';
import '../../screens/chat/location_view_screen.dart';

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
      if (message.extraData?['type'] == 'GAME_RESULT') {
        return _GameResultSystemBubble(message: message);
      }
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 내 메시지: 안 읽음 → "1", 읽음 → 표시 없음
                      if (isMine && message.readAt == null) ...[
                        const Text(
                          '1',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFFF6B35),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textDisabled,
                        ),
                      ),
                    ],
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
      backgroundColor: const Color(0xFF2A2A2A),
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

    if (message.isLocation) {
      return _LocationBubble(
        message: message,
        isMine: isMine,
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? AppTheme.primaryColor : const Color(0xFF1E1E1E),
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
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
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
          memCacheWidth: 400,
          memCacheHeight: 400,
          placeholder: (context, url) => Container(
            width: 200,
            height: 200,
            color: const Color(0xFF2A2A2A),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 200,
            height: 200,
            color: const Color(0xFF2A2A2A),
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageView(imageUrl: imageUrl),
      ),
    );
  }
}

/// 전체화면 이미지 뷰어
class _FullScreenImageView extends StatelessWidget {
  final String imageUrl;
  const _FullScreenImageView({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.broken_image, color: Colors.grey, size: 48,
            ),
          ),
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
          color: const Color(0xFF2A2A2A),
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

/// 경기 결과 시스템 메시지
class _GameResultSystemBubble extends StatelessWidget {
  final Message message;

  const _GameResultSystemBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final extra = message.extraData ?? {};
    final claimedResult = extra['claimedResult'] as String? ?? '';
    final winnerNickname = extra['winnerNickname'] as String?;
    final winnerProfileImage = extra['winnerProfileImage'] as String?;
    final isDraw = claimedResult == 'DRAW';

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '상대방이 경기 결과를 입력했습니다',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 10),
            if (isDraw)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '무승부',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF)),
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 프로필 사진
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2A2A2A),
                      image: winnerProfileImage != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(winnerProfileImage),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: winnerProfileImage == null
                        ? const Icon(Icons.person, size: 18, color: Color(0xFF9CA3AF))
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${winnerNickname ?? '?'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '승',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 위치 메시지 버블 (220px 고정 너비 카드)
class _LocationBubble extends StatelessWidget {
  final Message message;
  final bool isMine;

  const _LocationBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final locData = message.locationData;

    String addressText;
    if (locData != null) {
      if (locData.placeName != null && locData.placeName!.isNotEmpty) {
        addressText = locData.placeName!;
      } else if (locData.address != null && locData.address!.isNotEmpty) {
        addressText = locData.address!;
      } else {
        addressText =
            '위도 ${locData.latitude.toStringAsFixed(4)}, '
            '경도 ${locData.longitude.toStringAsFixed(4)}';
      }
    } else {
      addressText = '위치 정보 없음';
    }

    return GestureDetector(
      onTap: locData == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocationViewScreen(locationData: locData),
                ),
              );
            },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isMine
              ? AppTheme.primaryColor.withOpacity(0.9)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: Border.all(
            color: isMine
                ? Colors.transparent
                : const Color(0xFF2A2A2A),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 지도 프리뷰 영역
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 120,
                child: locData != null
                    ? IgnorePointer(
                        child: NaverMap(
                          options: NaverMapViewOptions(
                            initialCameraPosition: NCameraPosition(
                              target: NLatLng(locData.latitude, locData.longitude),
                              zoom: 15,
                            ),
                            mapType: NMapType.basic,
                            nightModeEnable: true,
                            liteModeEnable: true,
                            logoClickEnable: false,
                            scrollGesturesEnable: false,
                            zoomGesturesEnable: false,
                            rotationGesturesEnable: false,
                            tiltGesturesEnable: false,
                            locationButtonEnable: false,
                            scaleBarEnable: false,
                            logoAlign: NLogoAlign.leftTop,
                          ),
                          onMapReady: (controller) {
                            controller.addOverlay(
                              NMarker(
                                id: 'loc_${message.id}',
                                position: NLatLng(locData.latitude, locData.longitude),
                              ),
                            );
                          },
                        ),
                      )
                    : Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Center(
                          child: Icon(Icons.location_off_rounded, size: 32, color: Color(0xFF9CA3AF)),
                        ),
                      ),
              ),
            ),

            // 주소 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    addressText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isMine ? Colors.white : AppTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (locData?.address != null &&
                      locData?.placeName != null &&
                      locData!.placeName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      locData.address!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isMine
                            ? Colors.white.withOpacity(0.7)
                            : const Color(0xFF9CA3AF),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
