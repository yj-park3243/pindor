import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../network/api_client.dart';

/// 앱 버전 체크 서비스
/// - 앱 시작 시 서버에서 최소/최신 버전 정보를 조회
/// - 현재 버전이 최소 버전보다 낮으면 강제 업데이트 다이얼로그 표시
/// - 현재 버전이 최신 버전보다 낮으면 선택 업데이트 다이얼로그 표시
class VersionCheckService {
  VersionCheckService._();

  static Future<void> check(BuildContext context) async {
    try {
      final currentVersion = AppConfig.appVersion;
      final platform = Platform.isIOS ? 'IOS' : 'ANDROID';

      final response = await ApiClient.instance.get(
        '/app-version',
        queryParameters: {'platform': platform},
      );

      final data = response['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final minVersion = data['minVersion'] as String?;
      final latestVersion = data['latestVersion'] as String?;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final updateMessage = data['updateMessage'] as String?;
      final storeUrl = data['storeUrl'] as String?;

      if (!context.mounted) return;

      if (minVersion != null && _isVersionLower(currentVersion, minVersion)) {
        // 필수 업데이트 — 다이얼로그 해제 불가
        _showUpdateDialog(
          context,
          title: '업데이트 필요',
          message: updateMessage ?? '새 버전이 출시되었습니다. 업데이트 후 이용해주세요.',
          storeUrl: storeUrl,
          force: true,
        );
      } else if (latestVersion != null &&
          _isVersionLower(currentVersion, latestVersion) &&
          !forceUpdate) {
        // 선택 업데이트
        _showUpdateDialog(
          context,
          title: '새 버전 출시',
          message: updateMessage ?? '새로운 기능이 추가되었습니다. 업데이트하시겠습니까?',
          storeUrl: storeUrl,
          force: false,
        );
      }
    } catch (e) {
      // 버전 체크 실패해도 앱 사용은 계속 가능
      debugPrint('[VersionCheck] Error: $e');
    }
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
    return false; // 동일 버전
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String message,
    String? storeUrl,
    required bool force,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        // 뒤로가기로도 강제 업데이트 다이얼로그 닫기 방지
        canPop: !force,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
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
                if (!force && ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('업데이트'),
            ),
          ],
        ),
      ),
    );
  }
}
