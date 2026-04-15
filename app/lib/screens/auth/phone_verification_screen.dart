import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/router.dart';
import '../../core/network/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/kcp_repository.dart';
import '../../widgets/common/app_toast.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _isVerifying = false;
  String? _errorMessage;

  static const _kcpReturnScheme = 'spots';
  static const _kcpReturnHost = 'kcp-cert';

  @override
  void initState() {
    super.initState();
    _loadKcpForm();
  }

  Future<void> _loadKcpForm() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final kcpRepo = ref.read(kcpRepositoryProvider);
      final html = await kcpRepo.getForm();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.scheme == _kcpReturnScheme &&
                uri.host == _kcpReturnHost) {
              // spots://kcp-cert?key=XXXXX 딥링크 수신
              final key = uri.queryParameters['key'];
              if (key != null && key.isNotEmpty) {
                _handleKcpCallback(key);
              } else {
                _showError('인증 결과를 받지 못했습니다. 다시 시도해주세요.');
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // spots:// 딥링크 URL로 인한 에러는 무시
            final errorUrl = error.url ?? '';
            if (errorUrl.startsWith('$_kcpReturnScheme://')) return;
            // KCP 인증 서버 접속 에러도 무시 (form submit 후 KCP 페이지로 전환되는 과정)
            // 실제 에러는 사용자가 인증을 진행하지 못하는 상황에서만 표시
          },
        ),
      );
      await controller.loadHtmlString(html);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '본인인증 서비스를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.';
        });
      }
    }
  }

  Future<void> _handleKcpCallback(String key) async {
    if (_isVerifying) return;

    setState(() => _isVerifying = true);

    try {
      final kcpRepo = ref.read(kcpRepositoryProvider);
      final result = await kcpRepo.verify(key);

      final accessToken = result['accessToken'] as String;
      final refreshToken = result['refreshToken'] as String;
      final userData = result['user'] as Map<String, dynamic>;
      final isNewUser = userData['isNewUser'] as bool? ?? true;
      final nextRoute = result['nextRoute'] as String? ?? 'profile-setup';

      // AuthProvider 상태 업데이트
      ref.read(authStateProvider.notifier).completeVerification(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userData: userData,
            isNewUser: isNewUser,
          );

      if (!mounted) return;

      if (nextRoute == 'home') {
        // 기존 계정으로 자동 로그인
        AppToast.info('기존 계정으로 로그인되었습니다.');
        context.go(AppRoutes.home);
      } else {
        // 정상 신규 가입 → 프로필 설정
        context.go(AppRoutes.profileSetup);
      }
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 403 && e.code == 'KCP_001') {
        // PHONE_NUMBER_BANNED
        await _showBannedDialog();
      } else if (e.statusCode == 409 && e.code == 'KCP_003') {
        // KCP_KEY_ALREADY_USED
        AppToast.info('이미 처리된 인증입니다.');
        context.go(AppRoutes.home);
      } else {
        _showError(e.message);
      }
    } catch (e) {
      if (!mounted) return;
      _showError('인증 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _showBannedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('가입 불가'),
        content: const Text('해당 전화번호로는 가입이 불가합니다.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go(AppRoutes.login);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '본인인증',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // WebView
          if (_controller != null && _errorMessage == null)
            WebViewWidget(controller: _controller!),

          // 에러 화면
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadKcpForm,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),

          // 로딩 인디케이터 (form 로딩 중 또는 verify 처리 중)
          if (_isLoading || _isVerifying)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '처리 중입니다...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

