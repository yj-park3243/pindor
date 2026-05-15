import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';
import '../../core/version/version_check_service.dart';

/// 로그인 화면
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _loginWithApple() async {
    setState(() => _isLoading = true);
    try {
      final result = await ref.read(authStateProvider.notifier).loginWithApple();
      if (!mounted) return;
      print('[Apple] 라우팅: isNewUser=${result.isNewUser}, isVerified=${result.isVerified}');
      await VersionCheckService.ensureLoaded();
      final effectiveVerified =
          !VersionCheckService.requirePhoneVerification || result.isVerified;
      if (result.isNewUser && !effectiveVerified) {
        context.go(AppRoutes.phoneVerification);
      } else if (result.isNewUser) {
        context.go(AppRoutes.profileSetup);
      } else {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, 'Apple 로그인에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authStateProvider.notifier).loginWithGoogle();
      if (mounted) {
        final authState = ref.read(authStateProvider).valueOrNull;
        await VersionCheckService.ensureLoaded();
        final effectiveVerified = !VersionCheckService.requirePhoneVerification ||
            authState?.isVerified == true;
        if (authState?.isNewUser == true && !effectiveVerified) {
          context.go(AppRoutes.phoneVerification);
        } else if (authState?.isNewUser == true) {
          context.go(AppRoutes.profileSetup);
        } else {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(extractErrorMessage(e, '로그인에 실패했습니다.'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // ─── 로고 영역 (상단 1/3) ───
              Column(
                children: [
                  // "P" 레터마크
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.primaryColor, AppTheme.primaryDark],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.35),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'P',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // 앱 이름
                  const Text(
                    '핀돌',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 서브타이틀
                  const Text(
                    '내 근처 스포츠 대결 매칭',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // ─── 간편하게 시작하기 ───
              Column(
                children: [
                  Text(
                    '간편하게 시작하세요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary.withOpacity(0.8),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Apple 로그인 버튼 — iOS에서만 노출 (Apple HIG 준수)
                  if (Platform.isIOS) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: SignInWithAppleButton(
                        style: SignInWithAppleButtonStyle.white,
                        borderRadius: BorderRadius.circular(14),
                        text: 'Apple로 로그인',
                        onPressed: _isLoading ? () {} : _loginWithApple,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Google 로그인 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _loginWithGoogle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: Color(0xFF2A2A2A), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Google "G" 로고 (텍스트로 대체)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4285F4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Google로 시작하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 구분선 ──
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: const Color(0xFF2A2A2A), thickness: 1)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '또는',
                          style: TextStyle(color: AppTheme.textDisabled, fontSize: 12),
                        ),
                      ),
                      Expanded(child: Divider(color: const Color(0xFF2A2A2A), thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 이메일로 로그인 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push(AppRoutes.emailLogin),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: const BorderSide(color: Color(0xFF333333), width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.email_outlined, size: 18, color: AppTheme.textSecondary),
                          SizedBox(width: 8),
                          Text(
                            '이메일로 로그인',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 이메일 가입 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push(AppRoutes.emailSignup),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textDisabled,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '이메일로 가입',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: AppTheme.textDisabled,
                        ),
                      ),
                    ),
                  ),

                ],
              ),

              const Spacer(),

              // 약관 동의 안내
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, color: AppTheme.textDisabled, height: 1.6),
                    children: [
                      const TextSpan(text: '로그인 시 '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => _openUrl('https://pins.kr/terms.html'),
                          child: const Text(
                            '서비스 이용약관',
                            style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, height: 1.6, decoration: TextDecoration.underline, decorationColor: AppTheme.primaryColor),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' 및 '),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () => _openUrl('https://pins.kr/privacy.html'),
                          child: const Text(
                            '개인정보 처리방침',
                            style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, height: 1.6, decoration: TextDecoration.underline, decorationColor: AppTheme.primaryColor),
                          ),
                        ),
                      ),
                      const TextSpan(text: '에\n동의하는 것으로 간주합니다.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
