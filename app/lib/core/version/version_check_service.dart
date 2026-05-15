import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../network/api_client.dart';
import '../utils/location_utils.dart';
import '../../widgets/common/app_toast.dart';

/// 앱 버전 체크 서비스
/// - 앱 시작 시 서버에서 최소/최신 버전 정보를 조회
/// - 현재 버전이 최소 버전보다 낮으면 강제 업데이트 오버레이 표시 (해제 불가)
/// - 현재 버전이 최신 버전보다 낮으면 선택 업데이트 다이얼로그 표시
class VersionCheckService {
  VersionCheckService._();

  /// 강제 업데이트 오버레이 핸들 — 라우팅 변경에 영향받지 않도록 OverlayEntry 사용
  static OverlayEntry? _forceOverlay;

  /// 서버에서 받은 광고 표시 여부 (원격 토글)
  /// default false — 서버 응답 받기 전엔 광고 미표시
  static bool showAd = false;

  /// 서버에서 받은 핸드폰(KCP) 본인인증 강제 여부 (원격 토글, platform별)
  /// default true — 서버 응답 받기 전엔 안전하게 인증 강제
  static bool requirePhoneVerification = true;

  /// `check()` 완료(성공/실패 무관) 시그널. 로그인 분기에서 await로 사용.
  static final Completer<void> _loadedCompleter = Completer<void>();
  static bool _checkStarted = false;

  /// 서버 토글이 로드되거나 fetch가 끝날 때까지 대기.
  /// - 이미 완료됐으면 즉시 반환
  /// - 아직 check() 호출 전이면 직접 호출
  /// - 타임아웃 시 캐시된(혹은 기본) 값으로 진행
  static Future<void> ensureLoaded({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_loadedCompleter.isCompleted) return;
    if (!_checkStarted) {
      // navigator/overlay가 없어도 동작하도록 BuildContext 없이 호출
      // ignore: discarded_futures
      check(null);
    }
    try {
      await _loadedCompleter.future.timeout(timeout);
    } catch (_) {
      // 타임아웃은 무시 — 기본값으로 진행
    }
  }

  /// pubspec.yaml의 version에서 자동 추출 (캐시).
  static String? _cachedAppVersion;

  static Future<String> getCurrentAppVersion() async {
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = info.version;
      return info.version;
    } catch (e) {
      // dev/시뮬레이터에서 plugin 미등록 시 강제 업데이트 다이얼로그가 뜨지 않도록
      // 매우 높은 버전을 fallback으로 사용 (production 빌드에선 PackageInfo 정상 동작).
      debugPrint('[VersionCheck] PackageInfo 조회 실패: $e — dev fallback 999.0.0');
      _cachedAppVersion = '999.0.0';
      return _cachedAppVersion!;
    }
  }

  static Future<void> check(BuildContext? context) async {
    _checkStarted = true;
    try {
      final currentVersion = await getCurrentAppVersion();
      final platform = Platform.isIOS ? 'IOS' : 'ANDROID';

      debugPrint('[VersionCheck] 시작 — current=$currentVersion platform=$platform');

      // 위치 권한이 이미 허용된 경우에만 좌표 조회 (권한 팝업 X, 3초 타임아웃)
      double? lat;
      double? lng;
      if (await LocationUtils.hasPermission()) {
        final pos = await LocationUtils.getCurrentPosition(
          accuracy: LocationAccuracy.low,
          timeout: const Duration(seconds: 3),
        );
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      }

      final response = await ApiClient.instance.get(
        '/app-version',
        queryParameters: {
          'platform': platform,
          'appVersion': currentVersion,
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
        },
      );

      final data = response['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final minVersion = data['minVersion'] as String?;
      final latestVersion = data['latestVersion'] as String?;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final updateMessage = data['updateMessage'] as String?;
      final storeUrl = data['storeUrl'] as String?;
      showAd = data['showAd'] as bool? ?? false;
      // 서버 응답에 필드가 없으면(옛 서버) 안전하게 true(인증 강제)로 유지.
      requirePhoneVerification = data['requirePhoneVerification'] as bool? ?? true;
      if (!_loadedCompleter.isCompleted) _loadedCompleter.complete();

      debugPrint(
        '[VersionCheck] 서버 — min=$minVersion latest=$latestVersion force=$forceUpdate',
      );

      final mustUpdate =
          minVersion != null && _isVersionLower(currentVersion, minVersion);

      if (mustUpdate) {
        // 강제 업데이트 — Overlay로 표시 (라우팅에 영향 안 받음)
        debugPrint('[VersionCheck] 강제 업데이트 오버레이 표시');
        _showForceUpdateOverlay(
          message: updateMessage ?? '필수 업데이트가 있습니다. 새 버전으로 업데이트해주세요.',
          storeUrl: storeUrl,
        );
      } else if (latestVersion != null &&
          _isVersionLower(currentVersion, latestVersion) &&
          !forceUpdate) {
        debugPrint('[VersionCheck] 선택 업데이트 다이얼로그 표시');
        _showOptionalUpdateDialog(
          message: updateMessage ?? '새로운 기능이 추가되었습니다. 업데이트하시겠습니까?',
          storeUrl: storeUrl,
        );
      } else {
        debugPrint('[VersionCheck] 업데이트 불필요');
      }
    } catch (e, st) {
      debugPrint('[VersionCheck] Error: $e\n$st');
    } finally {
      if (!_loadedCompleter.isCompleted) _loadedCompleter.complete();
    }
  }

  /// 강제 업데이트 — 화면 전체를 덮는 OverlayEntry. dismiss 불가.
  static void _showForceUpdateOverlay({
    required String message,
    String? storeUrl,
  }) {
    if (_forceOverlay != null) return; // 이미 표시 중
    final overlayState = AppToast.navigatorKey.currentState?.overlay;
    if (overlayState == null) {
      // 오버레이 준비 안 됨 — 다음 프레임 재시도
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showForceUpdateOverlay(message: message, storeUrl: storeUrl);
      });
      return;
    }
    _forceOverlay = OverlayEntry(
      builder: (_) => _ForceUpdateOverlay(message: message, storeUrl: storeUrl),
    );
    overlayState.insert(_forceOverlay!);
  }

  static void _showOptionalUpdateDialog({
    required String message,
    String? storeUrl,
  }) {
    final ctx = AppToast.navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog(
      context: ctx,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('새 버전 출시'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () async {
              if (storeUrl != null) {
                final uri = Uri.parse(storeUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
  }

  /// 현재 버전이 대상 버전보다 낮은지 비교 (semver x.y.z)
  static bool _isVersionLower(String current, String target) {
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final t = target.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final tv = i < t.length ? t[i] : 0;
      if (cv < tv) return true;
      if (cv > tv) return false;
    }
    return false;
  }
}

/// 강제 업데이트 풀스크린 오버레이 — 사용자가 닫을 수 없음.
class _ForceUpdateOverlay extends StatelessWidget {
  final String message;
  final String? storeUrl;

  const _ForceUpdateOverlay({required this.message, this.storeUrl});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        size: 32,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '업데이트 필요',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFB0B7C3),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (storeUrl != null) {
                            final uri = Uri.parse(storeUrl!);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '업데이트하러 가기',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
