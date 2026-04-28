import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/router.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../core/network/api_client.dart';

/// 이메일 회원가입 화면 (Firebase Auth 기반)
class EmailSignupScreen extends ConsumerStatefulWidget {
  const EmailSignupScreen({super.key});

  @override
  ConsumerState<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends ConsumerState<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  bool _obscurePw = true;
  bool _obscurePwConfirm = true;
  bool _agreedTerms = false;
  bool _agreedPrivacy = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return '이메일을 입력해주세요.';
    final regex = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d\-.]+$');
    if (!regex.hasMatch(v.trim())) return '올바른 이메일 형식을 입력해주세요.';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
    if (v.length < 8) return '비밀번호는 8자 이상이어야 합니다.';
    if (!RegExp(r'[a-zA-Z]').hasMatch(v)) return '영문자를 포함해야 합니다.';
    if (!RegExp(r'[0-9]').hasMatch(v)) return '숫자를 포함해야 합니다.';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _pwCtrl.text) return '비밀번호가 일치하지 않습니다.';
    return null;
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTerms || !_agreedPrivacy) {
      AppToast.error('이용약관 및 개인정보 처리방침에 동의해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authStateProvider.notifier).signupWithFirebase(
            email: _emailCtrl.text.trim(),
            password: _pwCtrl.text,
          );
      if (mounted) {
        AppToast.info('가입 완료! 본인인증을 진행해주세요.');
        // 라우터 redirect가 isVerified=false → phoneVerification으로 자동 이동
      }
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
    if (msg.contains('email-already-in-use') || msg.contains('duplicate')) {
      return '이미 가입된 이메일입니다.';
    }
    if (msg.contains('invalid-email')) return '올바른 이메일 형식이 아닙니다.';
    if (msg.contains('weak-password')) return '비밀번호가 너무 약합니다. 8자 이상, 영문+숫자를 포함해주세요.';
    if (msg.contains('network')) return '네트워크 오류가 발생했습니다.';
    return extractErrorMessage(e, '회원가입에 실패했습니다.');
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
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '이메일 가입',
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
                  decoration: _inputDeco('8자 이상, 영문+숫자 포함').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePw ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textDisabled,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePw = !_obscurePw),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),

                // 비밀번호 확인
                const Text('비밀번호 확인', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pwConfirmCtrl,
                  validator: _validateConfirm,
                  obscureText: _obscurePwConfirm,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: _inputDeco('비밀번호 재입력').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePwConfirm ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textDisabled,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePwConfirm = !_obscurePwConfirm),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signup(),
                ),
                const SizedBox(height: 28),

                // 약관 동의
                _AgreementRow(
                  checked: _agreedTerms,
                  onChanged: (v) => setState(() => _agreedTerms = v ?? false),
                  label: '이용약관',
                  url: 'https://pins.kr/terms.html',
                ),
                const SizedBox(height: 8),
                _AgreementRow(
                  checked: _agreedPrivacy,
                  onChanged: (v) => setState(() => _agreedPrivacy = v ?? false),
                  label: '개인정보 처리방침',
                  url: 'https://pins.kr/privacy.html',
                ),
                const SizedBox(height: 32),

                // 가입 버튼
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
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
                            '가입하기',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // 이미 계정 있음 → 로그인
                Center(
                  child: GestureDetector(
                    onTap: () => context.go(AppRoutes.emailLogin),
                    child: const Text(
                      '이미 계정이 있으신가요? 로그인',
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

class _AgreementRow extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String url;

  const _AgreementRow({
    required this.checked,
    required this.onChanged,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: onChanged,
          activeColor: AppTheme.primaryColor,
          side: const BorderSide(color: Color(0xFF444444)),
        ),
        const Text('(필수) ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.primaryColor,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primaryColor,
            ),
          ),
        ),
        const Text(' 동의', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ],
    );
  }
}
