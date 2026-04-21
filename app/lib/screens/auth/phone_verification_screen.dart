import 'dart:async';

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
  Timer? _timeoutTimer;

  static const _kcpReturnScheme = 'spots';
  static const _kcpReturnHost = 'kcp-cert';
  static const _authTimeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _loadKcpForm();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_authTimeout, () {
      if (mounted && !_isVerifying && _errorMessage == null) {
        _showError('인증 시간이 초과되었습니다.\n다시 시도해주세요.');
      }
    });
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
              // spots://kcp-cert?status=success&accessToken=...&nextRoute=...
              final status = uri.queryParameters['status'];
              if (status == 'success') {
                _handleKcpSuccess(uri.queryParameters);
              } else {
                final message = uri.queryParameters['message'] ?? '인증에 실패했습니다.';
                _showError(Uri.decodeComponent(message));
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            final errorUrl = error.url ?? '';
            // spots:// 딥링크 에러는 무시
            if (errorUrl.startsWith('$_kcpReturnScheme://')) return;
            // 메인 프레임 아닌 리소스(이미지/폰트)는 무시
            if (error.isForMainFrame != true) return;
            // 메인 페이지 로드 실패 시 에러 표시
            if (mounted && !_isVerifying && _errorMessage == null) {
              _showError('인증 페이지를 불러올 수 없습니다.\n네트워크를 확인하고 다시 시도해주세요.');
            }
          },
          onHttpError: (error) {
            final url = error.request?.uri.toString() ?? '';
            if (url.startsWith('$_kcpReturnScheme://')) return;
            // 5xx 응답 시 에러 표시
            final code = error.response?.statusCode ?? 0;
            if (code >= 500 && mounted && !_isVerifying && _errorMessage == null) {
              _showError('본인인증 서버 오류입니다. (HTTP $code)\n잠시 후 다시 시도해주세요.');
            }
          },
        ),
      );
      await controller.loadHtmlString(html);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
        _startTimeout();
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

  Future<void> _handleKcpSuccess(Map<String, String> params) async {
    if (_isVerifying) return;
    _timeoutTimer?.cancel();
    setState(() => _isVerifying = true);

    try {
      final accessToken = params['accessToken'] ?? '';
      final refreshToken = params['refreshToken'] ?? '';
      final userId = params['userId'] ?? '';
      final nickname = params['nickname'] ?? '';
      final nextRoute = params['nextRoute'] ?? 'profile-setup';
      final isNewUser = params['isNewUser'] == 'true';

      if (accessToken.isEmpty || userId.isEmpty) {
        _showError('인증 결과를 받지 못했습니다.');
        return;
      }

      ref.read(authStateProvider.notifier).completeVerification(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userData: {
              'id': userId,
              'nickname': nickname,
              'isNewUser': isNewUser,
              'isVerified': true,
            },
            isNewUser: isNewUser,
          );

      if (!mounted) return;

      if (nextRoute == 'home') {
        AppToast.info('기존 계정으로 로그인되었습니다.');
        context.go(AppRoutes.home);
      } else {
        context.go(AppRoutes.profileSetup);
      }
    } catch (e, st) {
      debugPrint('[KCP] 인증 처리 실패: $e\n$st');
      if (!mounted) return;
      _showError('인증 처리 중 오류가 발생했습니다.\n(${e.toString()})');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
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
    _timeoutTimer?.cancel();
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

