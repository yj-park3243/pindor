import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router.dart';
import '../../core/version/version_check_service.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/matching_repository.dart';

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
  List? _prefetchedMatches;

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
    // 인증 상태 대기 + 스플래시 최소 표시 시간을 병렬 처리
    final minDelay = Future.delayed(const Duration(milliseconds: 1500));

    // /app-version 토글(requirePhoneVerification 등) 로드 — router redirect 평가 전에
    // 끝나야 platform별 본인인증 강제 여부가 정확히 반영된다.
    final versionLoaded = VersionCheckService.ensureLoaded();

    // 인증 상태가 로딩 중이면 완료까지 대기
    var authState = ref.read(authStateProvider);
    if (authState.isLoading) {
      await ref.read(authStateProvider.future).catchError((_) => AuthState.unauthenticated);
      authState = ref.read(authStateProvider);
    }

    await versionLoaded;

    // 인증됨 → 스플래시 대기 중 매칭 데이터 미리 로드
    final authValue = authState.valueOrNull;
    if (authValue != null && authValue.isAuthenticated &&
        authValue.user != null && authValue.user!.sportsProfiles.isNotEmpty) {
      try {
        final repo = ref.read(matchingRepositoryProvider);
        _prefetchedMatches = await repo.getMyMatches();
      } catch (_) {}
    }

    await minDelay;
    if (!mounted) return;
    _startExitAnimation();
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
      // 본인인증 미완료면 우선 phoneVerification 으로.
      // (서버 토글 requirePhoneVerification=false 일 때만 우회 — VersionCheckService 가 그 정보 보유)
      final mustVerify = VersionCheckService.requirePhoneVerification &&
          !authState.isVerified;
      if (mustVerify) {
        context.go(AppRoutes.phoneVerification);
        return;
      }
      final user = authState.user;
      if (user != null && user.sportsProfiles.isEmpty) {
        context.go(AppRoutes.profileSetup);
        return;
      }

      // 스플래시에서 미리 로드한 매칭 데이터로 PENDING_ACCEPT 확인
      if (_prefetchedMatches != null) {
        final pending = _prefetchedMatches!.where((m) => m.isPendingAccept).toList();
        final unaccepted = pending.where((m) =>
          m.acceptances == null || !m.acceptances!.any((a) => a.accepted == true)
        ).toList();
        if (unaccepted.isNotEmpty) {
          context.go('/matches/${unaccepted.first.id}/accept');
          return;
        }
      }

      context.go(AppRoutes.home);
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
      backgroundColor: const Color(0xFF0A0A0A),
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
