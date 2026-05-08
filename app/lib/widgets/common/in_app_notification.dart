import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 인앱 알림 상단 슬라이드 배너 (Material Banner 스타일)
class InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const InAppNotificationBanner({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.iconColor,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();

    // 4초 후 자동 닫기
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor =
        widget.iconColor ?? AppTheme.primaryColor;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(16),
              shadowColor: Colors.black.withOpacity(0.25),
              child: InkWell(
                onTap: () {
                  widget.onTap?.call();
                  _dismiss();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: iconColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 아이콘 영역
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon ?? Icons.notifications_rounded,
                          color: iconColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 텍스트 영역
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.72),
                                fontSize: 12,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 닫기 버튼
                      GestureDetector(
                        onTap: _dismiss,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.6),
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 인앱 알림 표시 헬퍼
class InAppNotificationManager {
  static OverlayEntry? _currentEntry;

  /// 알림 배너 표시
  /// [context] - Overlay를 찾을 context
  /// [title] - 알림 제목
  /// [body] - 알림 내용
  /// [icon] - 커스텀 아이콘 (기본: notifications)
  /// [iconColor] - 아이콘 색상 (기본: primaryColor)
  /// [onTap] - 배너 탭 시 콜백
  static void show(
    BuildContext context, {
    required String title,
    required String body,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    // 기존 알림 제거
    _currentEntry?.remove();
    _currentEntry = null;

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: InAppNotificationBanner(
          title: title,
          body: body,
          icon: icon,
          iconColor: iconColor,
          onTap: onTap,
          onDismiss: () {
            _currentEntry?.remove();
            _currentEntry = null;
          },
        ),
      ),
    );

    Overlay.of(context).insert(_currentEntry!);
  }

  /// 현재 표시 중인 알림 제거
  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
