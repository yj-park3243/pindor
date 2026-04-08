import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../providers/auth_provider.dart';

/// 스플래시 화면
/// 핀돌 브랜드 이미지 → 페이드+스케일 전환 애니메이션
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeOut;
  late Animation<double> _scaleUp;

  bool _navigating = false;

  @override
  void initState() {
    super.initState();

    // 퇴장 애니메이션 (페이드아웃 + 살짝 확대)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInCubic),
    );

    _scaleUp = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _doNavigate();
      }
    });

    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // 스플래시 최소 표시 시간
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    authState.when(
      data: (_) => _startExitAnimation(),
      loading: () => _waitForAuthState(),
      error: (_, __) => _startExitAnimation(),
    );
  }

  void _waitForAuthState() {
    ref.listenManual<AsyncValue<AuthState>>(
      authStateProvider,
      (previous, next) {
        if (!mounted) return;
        next.when(
          data: (_) => _startExitAnimation(),
          loading: () {},
          error: (_, __) => _startExitAnimation(),
        );
      },
      fireImmediately: false,
    );
  }

  void _startExitAnimation() {
    if (_navigating || !mounted) return;
    _navigating = true;
    _controller.forward();
  }

  void _doNavigate() {
    if (!mounted) return;
    final authState = ref.read(authStateProvider).valueOrNull;
    if (authState != null && authState.isAuthenticated) {
      // 초기 설정 미완료 (종목 프로필 없음) → 설정 플로우로
      final user = authState.user;
      if (user != null && user.sportsProfiles.isEmpty) {
        context.go(AppRoutes.profileSetup);
      } else {
        context.go(AppRoutes.home);
      }
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeOut,
            child: ScaleTransition(
              scale: _scaleUp,
              child: child,
            ),
          );
        },
        child: SizedBox.expand(
          child: Image.asset(
            'assets/images/splash.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
