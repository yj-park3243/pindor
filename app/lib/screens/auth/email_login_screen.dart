import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';

/// 이메일 로그인 화면 (Firebase Auth 기반)
class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return '이메일을 입력해주세요.';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
    return null;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authStateProvider.notifier).loginWithFirebase(
            email: _emailCtrl.text.trim(),
            password: _pwCtrl.text,
          );
      // 명시적 navigate — isVerified 상태에 따라 분기
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      final auth = ref.read(authStateProvider).valueOrNull;
      final next = (auth?.isVerified ?? false)
          ? (auth?.isNewUser ?? false ? AppRoutes.profileSetup : AppRoutes.home)
          : AppRoutes.phoneVerification;
      GoRouter.of(context).go(next);
      return;
    } catch (e) {
      if (mounted) {
        AppToast.error(_parseError(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _parseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('user-not-found') || msg.contains('미가입')) {
      return '가입되지 않은 이메일입니다.';
    }
    if (msg.contains('wrong-password') ||
        msg.contains('invalid-credential') ||
        msg.contains('올바르지')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (msg.contains('user-disabled') || msg.contains('정지')) {
      return '사용이 정지된 계정입니다.';
    }
    if (msg.contains('too-many-requests')) {
      return '로그인 시도가 너무 많습니다. 잠시 후 다시 시도해주세요.';
    }
    if (msg.contains('network')) return '네트워크 오류가 발생했습니다.';
    return extractErrorMessage(e, '로그인에 실패했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.login);
            }
          },
        ),
        title: const Text(
          '이메일 로그인',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // 이메일
                const Text('이메일', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  validator: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _inputDeco('example@email.com'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),

                // 비밀번호
                const Text('비밀번호', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pwCtrl,
                  validator: _validatePassword,
                  obscureText: _obscurePw,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _inputDeco('비밀번호').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePw ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textDisabled,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 12),

                // 비밀번호 찾기
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => context.push(AppRoutes.emailPasswordReset),
                    child: const Text(
                      '비밀번호를 잊으셨나요?',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryColor,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 로그인 버튼
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
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
                        : const Text(
                            '로그인',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // 회원가입 이동
                Center(
                  child: GestureDetector(
                    onTap: () => context.go(AppRoutes.emailSignup),
                    child: const Text(
                      '아직 계정이 없으신가요? 가입하기',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryColor,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textDisabled, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppTheme.primaryColor),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}
