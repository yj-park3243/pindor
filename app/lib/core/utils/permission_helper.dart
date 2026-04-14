import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 앱 전체에서 통일된 권한 요청 및 거부 안내 다이얼로그를 제공하는 헬퍼
///
/// 각 메서드는 권한이 허용되면 true, 거부되면 false를 반환한다.
/// 거부/영구거부 시 설정으로 이동하도록 안내하는 다이얼로그를 표시한다.
class PermissionHelper {
  PermissionHelper._();

  // ─── 공개 메서드 ──────────────────────────────────────────────────

  /// 카메라 권한 요청
  static Future<bool> requestCamera(BuildContext context) async {
    return _request(
      context: context,
      permission: Permission.camera,
      title: '카메라 권한이 필요합니다',
      description: '경기 결과 인증 사진 촬영을 위해 카메라 접근이 필요합니다.',
    );
  }

  /// 사진 라이브러리 권한 요청
  static Future<bool> requestPhotos(BuildContext context) async {
    // Android 13+ (API 33+)는 Permission.photos가 READ_MEDIA_IMAGES로 매핑됨
    // permission_handler가 플랫폼별로 적절한 권한을 처리해줌
    return _request(
      context: context,
      permission: Permission.photos,
      title: '사진 라이브러리 권한이 필요합니다',
      description: '프로필 사진 및 경기 결과 사진 선택을 위해 사진 접근이 필요합니다.',
    );
  }

  /// 위치 권한 요청 (LocationPermission.deniedForever 케이스에 사용)
  ///
  /// 일반적인 위치 권한 요청은 Geolocator가 처리한다.
  /// 이 메서드는 영구 거부 상태일 때 설정 안내 다이얼로그를 표시하고 false를 반환한다.
  static Future<bool> showLocationDeniedDialog(BuildContext context) async {
    await _showPermissionDialog(
      context: context,
      title: '위치 권한이 필요합니다',
      description: '주변 스포츠 매칭 상대를 찾기 위해 위치 정보가 필요합니다.',
    );
    return false;
  }

  /// 알림 권한 요청
  static Future<bool> requestNotification(BuildContext context) async {
    return _request(
      context: context,
      permission: Permission.notification,
      title: '알림 권한이 필요합니다',
      description: '매칭 성사, 채팅 메시지 등 중요한 알림을 받기 위해 알림 권한이 필요합니다.',
    );
  }

  // ─── 내부 구현 ────────────────────────────────────────────────────

  /// 공통 권한 요청 처리
  static Future<bool> _request({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String description,
  }) async {
    final status = await permission.status;

    // 이미 허용된 경우
    if (status.isGranted || status.isLimited) return true;

    // 아직 결정 전이면 요청
    if (status.isDenied) {
      final result = await permission.request();
      if (result.isGranted || result.isLimited) return true;

      // 요청 후에도 거부 (사용자가 "거부" 선택)
      if (!context.mounted) return false;
      await _showPermissionDialog(
          context: context, title: title, description: description);
      return false;
    }

    // 영구 거부 또는 제한됨
    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!context.mounted) return false;
      await _showPermissionDialog(
          context: context, title: title, description: description);
      return false;
    }

    return false;
  }

  /// 설정으로 이동 안내 다이얼로그
  static Future<void> _showPermissionDialog({
    required BuildContext context,
    required String title,
    required String description,
  }) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이콘
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF4F46E5),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              // 제목
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              // 설명
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // 버튼 행
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        '취소',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        openAppSettings();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text(
                        '설정으로 이동',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
