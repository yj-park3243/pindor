import 'package:flutter/material.dart';

/// 매칭 카드 스타일 토스트 (상단 표시, 탭하면 사라짐)
class AppToast {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static void error(String message, {bool bottom = false}) {
    _show(message,
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEF4444),
        bottom: bottom);
  }

  static void success(String message, {bool bottom = false}) {
    _show(message,
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF22C55E),
        bottom: bottom);
  }

  static void info(String message, {bool bottom = false}) {
    _show(message,
        icon: Icons.info_outline_rounded,
        color: const Color(0xFF3B82F6),
        bottom: bottom);
  }

  static void warning(String message, {bool bottom = false}) {
    _show(message,
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF59E0B),
        bottom: bottom);
  }

  static OverlayEntry? _currentEntry;

  static void _show(
    String message, {
    required IconData icon,
    required Color color,
    Duration duration = const Duration(seconds: 3),
    bool bottom = false,
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        duration: duration,
        bottom: bottom,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
        child: _ToastCard(message: message, icon: icon, color: color),
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  const _ToastCard(
      {required this.message, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 상단 컬러 바
          Container(
            height: 3,
            color: color,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToastOverlay extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback onDismissed;
  final bool bottom;
  const _ToastOverlay(
      {required this.child, required this.duration, required this.onDismissed, this.bottom = false});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slideAnimation =
        Tween<Offset>(begin: Offset(0, widget.bottom ? 1.0 : -1.0), end: Offset.zero).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _showAndHide();
  }

  Future<void> _showAndHide() async {
    await _controller.forward();
    await Future.delayed(widget.duration);
    if (mounted && !_dismissed) {
      await _controller.reverse();
      _dismiss();
    }
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onDismissed();
  }

  Future<void> _onTap() async {
    if (_dismissed) return;
    await _controller.reverse();
    _dismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 8;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 16;
    return Positioned(
      top: widget.bottom ? null : topPadding,
      bottom: widget.bottom ? bottomPadding : null,
      left: 16,
      right: 16,
      child: Dismissible(
        key: UniqueKey(),
        direction: widget.bottom ? DismissDirection.down : DismissDirection.up,
        onDismissed: (_) => _dismiss(),
        child: GestureDetector(
          onTap: _onTap,
          child: Material(
            color: Colors.transparent,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                  position: _slideAnimation, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
