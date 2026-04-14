import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';

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
      await ref.read(authStateProvider.notifier).loginWithApple();
      if (mounted) {
        final authState = ref.read(authStateProvider).valueOrNull;
        if (authState?.isNewUser == true) {
          context.go(AppRoutes.profileSetup);
        } else {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('Apple 로그인 실패: ${e.toString()}');
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
        if (authState?.isNewUser == true) {
          context.go(AppRoutes.profileSetup);
        } else {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error('로그인 실패: ${e.toString()}');
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

                  // Apple 로그인 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _loginWithApple,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF000000),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.apple, size: 22, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Apple로 시작하기',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

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
