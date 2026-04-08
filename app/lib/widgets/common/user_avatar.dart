import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';

/// 프로필 이미지 + 온라인 상태 점
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? tier; // 서버 호환용으로 파라미터는 유지하나 UI에는 사용하지 않음
  final double size;
  final String? nickname; // 이미지 없을 때 이니셜 표시
  final bool showOnlineIndicator; // 온라인 상태 표시
  final bool isOnline;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.tier,
    this.size = 48,
    this.nickname,
    this.showOnlineIndicator = false,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 프로필 이미지
        _buildAvatar(),

        // 온라인 상태 점 (좌하단)
        if (showOnlineIndicator)
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: BoxDecoration(
                color: isOnline
                    ? AppTheme.secondaryColor
                    : AppTheme.textDisabled,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.shade200,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildPlaceholder(),
                errorWidget: (context, url, error) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final initial =
        nickname?.isNotEmpty == true ? nickname![0].toUpperCase() : '?';

    return Container(
      color: AppTheme.primaryColor.withOpacity(0.1),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor.withOpacity(0.8),
          ),
        ),
      ),
    );
  }
}
