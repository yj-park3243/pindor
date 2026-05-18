import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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
    extends ConsumerState<PhoneVerificationScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _loadKcpForm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // PASS / 통신사 인증 앱으로 빠졌다가 돌아오는 시간은 타임아웃에서 제외.
    // 사용자가 우리 앱 WebView에 떠 있는 시간만 카운트한다.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _timeoutTimer?.cancel();
        break;
      case AppLifecycleState.resumed:
        if (mounted &&
            _controller != null &&
            !_isVerifying &&
            _errorMessage == null) {
          _startTimeout();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
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
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // 우리 앱 콜백 deep link
            if (uri.scheme == _kcpReturnScheme && uri.host == _kcpReturnHost) {
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

            // WebView 내부에서 로드해도 안전한 표준 scheme
            const webSchemes = {'http', 'https', 'about', 'data', 'blob', 'file'};
            if (webSchemes.contains(uri.scheme)) {
              return NavigationDecision.navigate;
            }

            // 그 외 (intent://, ktauthexternalcall://, kpn-auth://, ipcollect:// 등
            //  통신사 PASS 본인인증 앱 또는 PG/카드사 앱 스킴) — WebView 가 처리 불가하므로
            // 외부 앱으로 실행. 실패 시 무시 — 사용자에게는 다시 시도 안내.
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (e) {
              debugPrint('[KCP] external launch failed for ${uri.scheme}: $e');
            }
            return NavigationDecision.prevent;
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
      final merged = params['merged'] == 'true';

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

      if (merged || nextRoute == 'home') {
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          AppToast.info('본인인증을 완료해야 이용 가능합니다.');
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('본인인증'),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        automaticallyImplyLeading: false, // 뒤로가기 버튼 숨김
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


