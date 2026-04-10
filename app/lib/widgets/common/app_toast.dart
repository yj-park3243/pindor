import 'dart:ui';
import 'package:flutter/material.dart';

/// Glass 스타일 토스트 (상단 표시, 탭하면 사라짐)
class AppToast {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void error(String message) {
    _show(message, icon: Icons.error_outline_rounded);
  }

  static void success(String message) {
    _show(message, icon: Icons.check_circle_rounded);
  }

  static void info(String message) {
    _show(message, icon: Icons.info_outline_rounded);
  }

  static void warning(String message) {
    _show(message, icon: Icons.warning_amber_rounded);
  }

  static OverlayEntry? _currentEntry;

  static void _show(
    String message, {
    required IconData icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GlassToastOverlay(
        duration: duration,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
        child: _GlassToast(message: message, icon: icon),
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// SnackBar 대체 — context 기반 (navigatorKey 없이 사용 가능)
  static void showFromContext(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline_rounded,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GlassToastOverlay(
        duration: duration,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) _currentEntry = null;
        },
        child: _GlassToast(message: message, icon: icon),
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _GlassToast extends StatelessWidget {
  final String message;
  final IconData icon;
  const _GlassToast({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.black.withValues(alpha: 0.75),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.20)),
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassToastOverlay extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback onDismissed;
  const _GlassToastOverlay(
      {required this.child, required this.duration, required this.onDismissed});

  @override
  State<_GlassToastOverlay> createState() => _GlassToastOverlayState();
}

class _GlassToastOverlayState extends State<_GlassToastOverlay>
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
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
            .animate(
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
    final topPadding = MediaQuery.of(context).padding.top + 16;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth * 0.06;
    return Positioned(
      top: topPadding,
      left: horizontalPad,
      right: horizontalPad,
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
    );
  }
}
