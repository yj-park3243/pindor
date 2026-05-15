import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 앱 아이콘 배지 제어 — iOS native method channel 사용.
/// Android는 OEM이 자동 처리하므로 호출만 무시한다.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  static const MethodChannel _channel = MethodChannel('kr.pins/badge');

  /// 배지를 0으로 초기화하고 표시된 알림도 제거한다.
  /// 호출 실패는 무시 (시뮬레이터/권한 거부 등).
  Future<void> clear() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('clearBadge');
    } catch (_) {
      // 무시
    }
  }
}
